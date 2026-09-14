// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasAssetInfo} from "contracts/interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IOracleHeartbeat} from "contracts/interfaces/IOracleHeartbeat.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IMidasDepositVault} from "contracts/interfaces/midas/IMidasDepositVault.sol";
import {IMidasRedemptionVault} from "contracts/interfaces/midas/IMidasRedemptionVault.sol";
import {MidasDepositVaultContractGuard} from "contracts/guards/contractGuards/midas/MidasDepositVaultContractGuard.sol";
import {MidasRedemptionVaultContractGuard} from "contracts/guards/contractGuards/midas/MidasRedemptionVaultContractGuard.sol";
import {PoolsWhitelist} from "contracts/utils/PoolsWhitelist.sol";
import {MidasMTokenAssetGuard} from "contracts/guards/assetGuards/midas/MidasMTokenAssetGuard.sol";
import {MidasPendingRedemptionAssetGuard} from "contracts/guards/assetGuards/midas/MidasPendingRedemptionAssetGuard.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {IERC20 as IERC20Local} from "contracts/interfaces/IERC20.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

/// @notice Shared fork setup + test suite for the Midas mAPOLLO integration.
/// @dev    Withdrawal design: the mToken (type 42) is transferred in-kind; the pending async
///         redemption claim (type 43, keyed by the redemption vault address) is paid out of the pool's
///         FREE mToken balance. Type 43 > type 42 guarantees the pending leg is processed first in
///         `PoolLogic._withdrawTo` (supported assets are sorted by asset type descending), which makes
///         the helper's `1/(1-portion)` grossing-up exact: the withdrawer nets `portion * (free + pending)`.
/// @dev    The default 24h exit cooldown is kept on purpose: withdrawal tests skip a full day, proving
///         the Midas feed (7-day heartbeat) stays fresh across a realistic deposit-to-withdrawal gap.
abstract contract MidasMApolloTestSetup is BackboneSetup {
  /// @notice Chain-specific Midas deployment addresses, supplied by the concrete chain test contract.
  struct MidasChainData {
    address mToken;
    address depositVault;
    address redemptionVault;
    address mTokenFeed;
    address requestRedeemer;
  }

  // solhint-disable var-name-mixedcase
  address public immutable MAPOLLO;
  address public immutable DEPOSIT_VAULT;
  address public immutable REDEMPTION_VAULT;
  address public immutable MAPOLLO_FEED;
  address public immutable REQUEST_REDEEMER;
  // solhint-enable var-name-mixedcase

  uint256 internal constant HEARTBEAT = 7 days;
  uint256 internal constant INITIAL_USDC = 20_000e6;
  uint256 internal constant BUY_AMOUNT = 5_000e18; // depositInstant amount (Midas base-18 convention)

  /// @dev Fee charged by Midas `redeemInstant` (bps of 100_00), matches `redemptionVault.instantFee()`.
  ///      `depositInstant` on the mAPOLLO vault carries no fee.
  uint256 internal constant MIDAS_INSTANT_FEE_BPS = 50; // 0.5%
  /// @dev Buffer for rounding drift between this suite's oracle math and Midas's internal rate math,
  ///      used to derive `minReceiveAmount` floors for instant operations.
  uint256 internal constant RATE_TOLERANCE_BPS = 50; // 0.5%
  /// @dev Relative delta for NAV continuity assertions (`assertApproxEqRel` scale, 1e18 = 100%).
  uint256 internal constant NAV_TOLERANCE = 1e14; // 0.01%
  /// @dev Relative delta for comparing Midas-produced amounts against this suite's oracle-fair math.
  ///      Wider than NAV_TOLERANCE for a systematic reason: Midas clamps stable tokens (USDC) to a
  ///      1:1 rate internally, while dHEDGE prices USDC via its Chainlink feed (~0.9998), a ~0.02% gap.
  uint256 internal constant MIDAS_RATE_TOLERANCE = 5e14; // 0.05%

  // --- Deployed test infrastructure ---
  address public midasPriceAggregator; // MidasPriceAggregator (deployed via deployCode, 0.8.28)
  MidasMTokenAssetGuard public mTokenAssetGuard;
  MidasDepositVaultContractGuard public depositGuard;
  MidasRedemptionVaultContractGuard public redemptionGuard;
  MidasPendingRedemptionAssetGuard public pendingGuard;

  PoolLogic public testPool;
  PoolManagerLogic public fundManagerLogic;

  constructor(MidasChainData memory _chainData) {
    MAPOLLO = _chainData.mToken;
    DEPOSIT_VAULT = _chainData.depositVault;
    REDEMPTION_VAULT = _chainData.redemptionVault;
    MAPOLLO_FEED = _chainData.mTokenFeed;
    REQUEST_REDEEMER = _chainData.requestRedeemer;
  }

  function setUp() public virtual override {
    super.setUp();

    vm.startPrank(owner);

    // Price aggregator wrapping the Midas custom feed (0.8.28 contract, cross-version deploy).
    midasPriceAggregator = deployCode(
      "MidasPriceAggregator.sol:MidasPriceAggregator",
      abi.encode(MAPOLLO_FEED, HEARTBEAT)
    );

    // Contract guards; both check instant-operation output against the shared SlippageAccumulator.
    depositGuard = new MidasDepositVaultContractGuard(address(slippageAccumulator));
    // The redemption guard is the integration's single owned contract: it tracks async requests AND
    // holds the pool whitelist. Deployed with an empty whitelist; pools are whitelisted in
    // `_createMidasPool`.
    redemptionGuard = new MidasRedemptionVaultContractGuard(address(slippageAccumulator), new address[](0));
    governance.setContractGuard(DEPOSIT_VAULT, address(depositGuard));
    governance.setContractGuard(REDEMPTION_VAULT, address(redemptionGuard));

    // mToken asset guard (type 42): plain in-kind ERC20 withdrawal, valued at NAV. Serves the
    // mTokens derived from the supplied redemption vaults; resolves the whitelist at call time via
    // the mToken's redemption vault -> its contract guard. New Midas products extend this vault set
    // on the SAME asset type (see the guard's natspec).
    address[] memory redemptionVaults = new address[](1);
    redemptionVaults[0] = REDEMPTION_VAULT;
    mTokenAssetGuard = new MidasMTokenAssetGuard(redemptionVaults);
    governance.setAssetGuard(uint16(AssetTypeIncomplete.MIDAS_MTOKEN), address(mTokenAssetGuard));
    assetHandlerProxy.addAsset(MAPOLLO, uint16(AssetTypeIncomplete.MIDAS_MTOKEN), midasPriceAggregator);

    // Pending redemption asset guard (type 43): keyed by the redemption vault address, valued at NAV,
    // withdrawals paid out of the pool's free mAPOLLO balance.
    pendingGuard = new MidasPendingRedemptionAssetGuard();
    governance.setAssetGuard(uint16(AssetTypeIncomplete.MIDAS_PENDING_REDEMPTION), address(pendingGuard));
    assetHandlerProxy.addAsset(
      REDEMPTION_VAULT,
      uint16(AssetTypeIncomplete.MIDAS_PENDING_REDEMPTION),
      midasPriceAggregator
    );

    vm.stopPrank();

    // The default (zero-fee) test pool; fee-sensitive tests create their own via `_createMidasPool`.
    testPool = _createMidasPool(0, 0, 0, 0);
    fundManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());
  }

  /// @dev Creates a pool supporting USDC (deposit) + mAPOLLO + the redemption vault (pending claim),
  ///      seeds it with USDC and sets the manager approvals towards the Midas vaults.
  ///      Mirrors the production flow: pool addresses only exist after `createFund`, so the pool is
  ///      created with USDC only, whitelisted by the protocol owner, and the Midas assets are then
  ///      enabled via `changeAssets`.
  function _createMidasPool(
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _entryFeeNumerator,
    uint256 _exitFeeNumerator
  ) internal returns (PoolLogic pool) {
    vm.prank(manager);
    pool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "MidasApolloVault",
        _fundSymbol: "MAV",
        _performanceFeeNumerator: _performanceFeeNumerator,
        _managerFeeNumerator: _managerFeeNumerator,
        _entryFeeNumerator: _entryFeeNumerator,
        _exitFeeNum: _exitFeeNumerator,
        _supportedAssets: _usdcOnlyAssets()
      })
    );

    // Protocol owner whitelists the pool for the Midas integration.
    vm.prank(owner);
    redemptionGuard.setPoolsWhitelist(_whitelistSetting(address(pool), true));

    vm.startPrank(manager);

    // Manager enables the Midas assets (both non-deposit).
    IHasSupportedAsset.Asset[] memory midasAssets = new IHasSupportedAsset.Asset[](2);
    midasAssets[0] = IHasSupportedAsset.Asset({asset: REDEMPTION_VAULT, isDeposit: false});
    midasAssets[1] = IHasSupportedAsset.Asset({asset: MAPOLLO, isDeposit: false});
    PoolManagerLogic(pool.poolManagerLogic()).changeAssets(midasAssets, new address[](0));

    // Seed the pool with USDC.
    deal(usdcData.asset, manager, INITIAL_USDC);
    IERC20(usdcData.asset).approve(address(pool), INITIAL_USDC);
    pool.deposit(usdcData.asset, INITIAL_USDC);

    // Manager approvals: USDC -> deposit vault (buy), mAPOLLO -> redemption vault (sell).
    pool.execTransaction(
      usdcData.asset,
      abi.encodeWithSelector(IERC20.approve.selector, DEPOSIT_VAULT, type(uint256).max)
    );
    pool.execTransaction(MAPOLLO, abi.encodeWithSelector(IERC20.approve.selector, REDEMPTION_VAULT, type(uint256).max));
    vm.stopPrank();
  }

  function _usdcOnlyAssets() internal view returns (IHasSupportedAsset.Asset[] memory supportedAssets) {
    supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: usdcData.asset, isDeposit: true});
  }

  function _whitelistSetting(
    address _poolLogic,
    bool _whitelisted
  ) internal pure returns (PoolsWhitelist.WhitelistSetting[] memory settings) {
    settings = new PoolsWhitelist.WhitelistSetting[](1);
    settings[0] = PoolsWhitelist.WhitelistSetting({poolLogic: _poolLogic, whitelisted: _whitelisted});
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════

  function _managerDepositInstant(uint256 _amountToken18, uint256 _minReceive) internal {
    bytes memory data = abi.encodeWithSelector(
      IMidasDepositVault.depositInstant.selector,
      usdcData.asset,
      _amountToken18,
      _minReceive,
      bytes32(0)
    );
    vm.prank(manager);
    testPool.execTransaction(DEPOSIT_VAULT, data);
  }

  function _managerRedeemInstant(uint256 _amountMToken, uint256 _minReceive) internal {
    bytes memory data = abi.encodeWithSelector(
      IMidasRedemptionVault.redeemInstant.selector,
      usdcData.asset,
      _amountMToken,
      _minReceive
    );
    vm.prank(manager);
    testPool.execTransaction(REDEMPTION_VAULT, data);
  }

  function _managerRedeemRequest(uint256 _amountMToken) internal returns (uint256 requestId) {
    // The request created by this call is assigned the current (pre-increment) counter value.
    requestId = IMidasRedemptionVault(REDEMPTION_VAULT).currentRequestId();
    bytes memory data = abi.encodeWithSelector(
      IMidasRedemptionVault.redeemRequest.selector,
      usdcData.asset,
      _amountMToken
    );
    vm.prank(manager);
    testPool.execTransaction(REDEMPTION_VAULT, data);
  }

  /// @dev Withdraws via `withdrawSafe` with empty (zeroed) complex-asset data — the production entry
  ///      point; plain `withdraw` is just a wrapper building this same empty array.
  function _withdrawSafe(address _who, uint256 _shares) internal {
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(testPool));
    vm.prank(_who);
    testPool.withdrawSafe(_shares, complexAssetsData);
  }

  /// @dev Withdraws and asserts the withdrawer nets `portion * (free + pending)` in mAPOLLO.
  function _withdrawAndAssertFairMTokenShare(address _who, uint256 _shares, uint256 _pendingAmt) internal {
    uint256 free = _mApolloBalance();
    uint256 portion = (_shares * 1e18) / testPool.totalSupply();
    uint256 mBefore = IERC20(MAPOLLO).balanceOf(_who);

    _withdrawSafe(_who, _shares);

    assertApproxEqRel(
      IERC20(MAPOLLO).balanceOf(_who) - mBefore,
      ((free + _pendingAmt) * portion) / 1e18,
      1e12,
      "fair mAPOLLO share"
    );
  }

  /// @dev Resolves the access-control contract and admin role the vault actually checks, then mocks
  ///      an address into that role.
  function _mockMidasVaultAdmin() internal returns (address midasAdmin) {
    (, bytes memory acData) = REDEMPTION_VAULT.staticcall(abi.encodeWithSignature("accessControl()"));
    address accessControl = abi.decode(acData, (address));
    (, bytes memory roleData) = REDEMPTION_VAULT.staticcall(abi.encodeWithSignature("vaultRole()"));
    bytes32 vaultRole = abi.decode(roleData, (bytes32));

    midasAdmin = makeAddr("midasAdmin");
    vm.mockCall(
      accessControl,
      abi.encodeWithSelector(bytes4(keccak256("hasRole(bytes32,address)")), vaultRole, midasAdmin),
      abi.encode(true)
    );
  }

  /// @dev Simulates the Midas curator approving a standard redemption request.
  ///      How the real process works: `requestRedeemer` is a Midas-operated liquidity account, NOT the
  ///      vault itself. When the curator decides to fulfil a request, Midas ops first fund that account
  ///      with `tokenOut` (USDC) and have it approve the vault; the vault admin then calls
  ///      `approveRequest`, which pulls `amountMToken * mTokenRate / tokenOutRate` of `tokenOut` via
  ///      `transferFrom(requestRedeemer -> request.sender)` and burns the escrowed mToken. On a pinned
  ///      fork block the redeemer's live balance/allowance are arbitrary, so the test provisions them
  ///      (deal + approve) exactly the way Midas ops would right before approving.
  function _settleRedeemRequest(uint256 _requestId) internal {
    (, , , , uint256 mTokenRate, ) = IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(_requestId);
    _settleRedeemRequestAtRate(_requestId, mTokenRate);
  }

  /// @dev Settles at an explicit rate: plain `approveRequest` carries no variance bound (only
  ///      `safeApproveRequest` does), so any curator-chosen rate goes through.
  function _settleRedeemRequestAtRate(uint256 _requestId, uint256 _mTokenRate) internal {
    (, , uint8 status, , , ) = IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(_requestId);
    require(status == uint8(IMidasRedemptionVault.RequestStatus.Pending), "request not pending");

    deal(usdcData.asset, REQUEST_REDEEMER, 1_000_000e6);
    vm.prank(REQUEST_REDEEMER);
    IERC20(usdcData.asset).approve(REDEMPTION_VAULT, type(uint256).max);

    vm.prank(_mockMidasVaultAdmin());
    (bool ok, ) = REDEMPTION_VAULT.call(
      abi.encodeWithSignature("approveRequest(uint256,uint256)", _requestId, _mTokenRate)
    );
    require(ok, "approveRequest failed");
  }

  function _investorDeposit(address _investor, uint256 _usdcAmount) internal returns (uint256 shares) {
    deal(usdcData.asset, _investor, _usdcAmount);
    vm.startPrank(_investor);
    IERC20(usdcData.asset).approve(address(testPool), _usdcAmount);
    shares = testPool.deposit(usdcData.asset, _usdcAmount);
    vm.stopPrank();
  }

  /// @dev Simulates the Midas vault admin rejecting a request. NOTE: Midas `rejectRequest` only flips
  ///      the status to Canceled — the mToken stays in the vault and is returned manually by ops.
  function _rejectRedeemRequest(uint256 _requestId) internal {
    vm.prank(_mockMidasVaultAdmin());
    (bool ok, ) = REDEMPTION_VAULT.call(abi.encodeWithSignature("rejectRequest(uint256)", _requestId));
    require(ok, "rejectRequest failed");
  }

  /// @dev Simulates Midas ops manually returning rejected mTokens to the pool (`withdrawToken`).
  function _midasOpsReturnMTokens(uint256 _amount) internal {
    vm.prank(_mockMidasVaultAdmin());
    (bool ok, ) = REDEMPTION_VAULT.call(
      abi.encodeWithSignature("withdrawToken(address,uint256,address)", MAPOLLO, _amount, address(testPool))
    );
    require(ok, "withdrawToken failed");
  }

  function _trackedBalanceOf(
    IWithdrawalVault.TrackedAsset[] memory _trackedAssets,
    address _token
  ) internal pure returns (uint256 balance) {
    for (uint256 i; i < _trackedAssets.length; ++i) {
      if (_trackedAssets[i].token == _token) return _trackedAssets[i].balance;
    }
  }

  function _mApolloBalance() internal view returns (uint256) {
    return IERC20(MAPOLLO).balanceOf(address(testPool));
  }

  function _usdcBalance() internal view returns (uint256) {
    return IERC20(usdcData.asset).balanceOf(address(testPool));
  }

  function _balanceOfPool(address _who) internal view returns (uint256) {
    return IERC20(address(testPool)).balanceOf(_who);
  }

  /// @dev Fair mAPOLLO out (base-18) for a given USDC-in amount (base-18), at pool oracle prices.
  function _fairMTokenOut(uint256 _amountToken18) internal view returns (uint256) {
    uint256 srcValueUsd = (_amountToken18 * _assetPrice(usdcData.asset)) / 1e18;
    return (srcValueUsd * 1e18) / _assetPrice(MAPOLLO);
  }

  /// @dev Fair USDC out (base-18) for a given mAPOLLO-in amount (base-18), at pool oracle prices.
  function _fairUsdcOut(uint256 _amountMToken18) internal view returns (uint256) {
    uint256 srcValueUsd = (_amountMToken18 * _assetPrice(MAPOLLO)) / 1e18;
    return (srcValueUsd * 1e18) / _assetPrice(usdcData.asset);
  }

  /// @dev `minReceiveAmount` floor for `depositInstant` (fee-free): fair value less the rate buffer.
  function _minMTokenOut(uint256 _usdcAmount18) internal view returns (uint256) {
    return (_fairMTokenOut(_usdcAmount18) * (100_00 - RATE_TOLERANCE_BPS)) / 100_00;
  }

  /// @dev `minReceiveAmount` floor for `redeemInstant`: fair value less the instant fee and rate buffer.
  function _minUsdcOut(uint256 _mTokenAmount) internal view returns (uint256) {
    return (_fairUsdcOut(_mTokenAmount) * (100_00 - MIDAS_INSTANT_FEE_BPS - RATE_TOLERANCE_BPS)) / 100_00;
  }

  function _assetPrice(address _asset) internal view returns (uint256) {
    return IHasAssetInfo(address(poolFactoryProxy)).getAssetPrice(_asset);
  }

  function _managerRemoveAsset(address _asset) internal {
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = _asset;
    vm.prank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), removeAssets);
  }

  function _managerAddDepositAsset(address _asset) internal {
    IHasSupportedAsset.Asset[] memory addAssets = new IHasSupportedAsset.Asset[](1);
    addAssets[0] = IHasSupportedAsset.Asset({asset: _asset, isDeposit: true});
    vm.prank(manager);
    fundManagerLogic.changeAssets(addAssets, new address[](0));
  }

  /// @dev Raw `create` so deploy-time reverts surface as a zero address instead of bubbling.
  function _tryDeploy(bytes memory _initCode) internal returns (address deployed) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      deployed := create(0, add(_initCode, 0x20), mload(_initCode))
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Oracle wrapper
  // ═══════════════════════════════════════════════════════════════════════

  function test_oracle_wrapper_config() public view {
    assertEq(uint256(IAggregatorV3Interface(midasPriceAggregator).decimals()), 8, "decimals");
    assertEq(IOracleHeartbeat(midasPriceAggregator).oracleHeartbeat(), HEARTBEAT, "heartbeat");

    (, int256 underlyingAnswer, , , ) = IAggregatorV3Interface(MAPOLLO_FEED).latestRoundData();
    (, int256 answer, , , ) = IAggregatorV3Interface(midasPriceAggregator).latestRoundData();
    assertGt(answer, 0, "answer > 0");
    assertEq(answer, underlyingAnswer, "passthrough");
  }

  function test_mapollo_priced_at_nav() public view {
    (, int256 answer, , , ) = IAggregatorV3Interface(MAPOLLO_FEED).latestRoundData();
    assertEq(assetHandlerProxy.getUSDPrice(MAPOLLO), uint256(answer) * 1e10, "NAV price (18 decimals)");
  }

  function test_revert_aggregator_constructor_validation() public {
    bytes memory creationCode = vm.getCode("MidasPriceAggregator.sol:MidasPriceAggregator");

    address deployed = _tryDeploy(abi.encodePacked(creationCode, abi.encode(address(0), HEARTBEAT)));
    assertEq(deployed, address(0), "zero feed rejected");

    deployed = _tryDeploy(abi.encodePacked(creationCode, abi.encode(MAPOLLO_FEED, uint256(0))));
    assertEq(deployed, address(0), "zero heartbeat rejected");

    // The mAPOLLO token address doubles as a contract reporting 18 decimals (feed must report 8).
    deployed = _tryDeploy(abi.encodePacked(creationCode, abi.encode(MAPOLLO, HEARTBEAT)));
    assertEq(deployed, address(0), "non-8-decimals feed rejected");

    deployed = _tryDeploy(abi.encodePacked(creationCode, abi.encode(MAPOLLO_FEED, HEARTBEAT)));
    assertTrue(deployed != address(0), "valid params deploy");
  }

  /// @notice The 7-day heartbeat is the aggregator's whole purpose: prices survive the 25h default
  ///         Chainlink timeout (Midas pushes NAV roughly per business day) but brick past 7 days.
  function test_midas_feed_staleness_enforced_by_heartbeat() public {
    // BackboneSetup disables the global timeout (1 year); restore the production 25h default.
    vm.prank(owner);
    assetHandlerProxy.setChainlinkTimeout(90000);

    (, , , uint256 updatedAt, ) = IAggregatorV3Interface(midasPriceAggregator).latestRoundData();

    // Older than the 25h default but within the heartbeat: the override keeps the asset priced.
    vm.warp(updatedAt + HEARTBEAT - 1);
    assertGt(assetHandlerProxy.getUSDPrice(MAPOLLO), 0, "priced within heartbeat");

    // Beyond the heartbeat: pricing (and thus the pool) bricks until Midas pushes a fresh NAV.
    vm.warp(updatedAt + HEARTBEAT + 1);
    vm.expectRevert("Chainlink price expired");
    assetHandlerProxy.getUSDPrice(MAPOLLO);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Buy (depositInstant)
  // ═══════════════════════════════════════════════════════════════════════

  function test_manager_can_buy_mapollo_via_depositInstant() public {
    uint256 fvBefore = fundManagerLogic.totalFundValue();
    uint256 usdcBefore = _usdcBalance();
    uint256 minOut = _minMTokenOut(BUY_AMOUNT);

    _managerDepositInstant(BUY_AMOUNT, minOut);

    assertGe(_mApolloBalance(), minOut, "min mAPOLLO out respected");
    // No deposit fee on the Midas mAPOLLO vault, so the minted amount matches the oracle-fair
    // amount up to the stable-rate clamp difference.
    assertApproxEqRel(_mApolloBalance(), _fairMTokenOut(BUY_AMOUNT), MIDAS_RATE_TOLERANCE, "minted ~ fair amount");
    assertEq(_usdcBalance(), usdcBefore - BUY_AMOUNT / 1e12, "USDC spent (6 decimals)");
    assertApproxEqRel(fundManagerLogic.totalFundValue(), fvBefore, NAV_TOLERANCE, "NAV preserved");
  }

  function test_revert_deposit_guard_rejects_unknown_selector() public {
    bytes memory data = abi.encodeWithSignature("notAMidasFunction(address)", usdcData.asset);
    vm.prank(manager);
    vm.expectRevert(bytes("dh23"));
    testPool.execTransaction(DEPOSIT_VAULT, data);
  }

  function test_revert_depositInstant_unsupported_source_asset() public {
    bytes memory data = abi.encodeWithSelector(
      IMidasDepositVault.depositInstant.selector,
      daiData.asset, // not enabled in the pool
      100e18,
      0,
      bytes32(0)
    );
    vm.prank(manager);
    vm.expectRevert("unsupported source asset");
    testPool.execTransaction(DEPOSIT_VAULT, data);
  }

  function test_revert_depositInstant_when_mtoken_not_supported() public {
    _managerRemoveAsset(MAPOLLO); // allowed: zero balance, nothing pending

    bytes memory data = abi.encodeWithSelector(
      IMidasDepositVault.depositInstant.selector,
      usdcData.asset,
      BUY_AMOUNT,
      0,
      bytes32(0)
    );
    vm.prank(manager);
    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(DEPOSIT_VAULT, data);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Sell (redeemInstant)
  // ═══════════════════════════════════════════════════════════════════════

  function test_manager_can_redeemInstant_mapollo_to_usdc() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 mBal = _mApolloBalance();

    // Force the vault's simple (self-liquidity) instant-redeem branch.
    deal(usdcData.asset, REDEMPTION_VAULT, 1_000_000e6);
    uint256 usdcBefore = _usdcBalance();
    uint256 minOut = _minUsdcOut(mBal);

    _managerRedeemInstant(mBal, minOut);

    assertEq(_mApolloBalance(), 0, "mAPOLLO fully redeemed");
    uint256 received18 = (_usdcBalance() - usdcBefore) * 1e12; // 6 -> 18 decimals
    assertGe(received18, minOut, "min USDC out respected");
    assertApproxEqRel(
      received18,
      (_fairUsdcOut(mBal) * (100_00 - MIDAS_INSTANT_FEE_BPS)) / 100_00,
      MIDAS_RATE_TOLERANCE,
      "USDC out ~ fair minus instant fee"
    );
  }

  /// @notice The measured-delta slippage protection actually bites: if dHEDGE values the mToken
  ///         higher than what Midas pays out, the manager's redeem is blocked by the accumulator
  ///         (5% per 6h window) regardless of the manager-supplied `minReceiveAmount`.
  function test_slippage_accumulator_blocks_underpriced_redeemInstant() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 mBal = _mApolloBalance();

    // Force the vault's simple (self-liquidity) instant-redeem branch.
    deal(usdcData.asset, REDEMPTION_VAULT, 1_000_000e6);

    // Inflate ONLY dHEDGE's mAPOLLO valuation by 25% (mock our wrapper, not the Midas feed —
    // Midas reads its own data feed and keeps executing at the real NAV). 25% inflation => a 20%
    // realized slippage (25/125), comfortably above the 10% cumulative cap.
    (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = (
      IAggregatorV3Interface(midasPriceAggregator).latestRoundData()
    );
    vm.mockCall(
      midasPriceAggregator,
      abi.encodeWithSelector(IAggregatorV3Interface.latestRoundData.selector),
      abi.encode(roundId, (answer * 125) / 100, startedAt, updatedAt, answeredInRound)
    );

    // Midas pays ~20% less than dHEDGE's inflated valuation of the mAPOLLO sold -> over the cap.
    bytes memory data = abi.encodeWithSelector(IMidasRedemptionVault.redeemInstant.selector, usdcData.asset, mBal, 0);
    vm.prank(manager);
    vm.expectRevert("slippage impact exceeded");
    testPool.execTransaction(REDEMPTION_VAULT, data);
  }

  function test_revert_redemption_guard_rejects_unknown_selector() public {
    bytes memory data = abi.encodeWithSignature("notAMidasFunction(address)", usdcData.asset);
    vm.prank(manager);
    vm.expectRevert(bytes("dh23"));
    testPool.execTransaction(REDEMPTION_VAULT, data);
  }

  function test_revert_redeemInstant_unsupported_destination_asset() public {
    bytes memory data = abi.encodeWithSelector(
      IMidasRedemptionVault.redeemInstant.selector,
      daiData.asset, // not enabled in the pool
      1e18,
      0
    );
    vm.prank(manager);
    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(REDEMPTION_VAULT, data);
  }

  function test_revert_redeemRequest_unsupported_destination_asset() public {
    bytes memory data = abi.encodeWithSelector(IMidasRedemptionVault.redeemRequest.selector, daiData.asset, 1e18);
    vm.prank(manager);
    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(REDEMPTION_VAULT, data);
  }

  function test_revert_redeemRequest_when_mtoken_not_supported() public {
    _managerRemoveAsset(MAPOLLO); // allowed: zero balance, nothing pending

    bytes memory data = abi.encodeWithSelector(IMidasRedemptionVault.redeemRequest.selector, usdcData.asset, 1e18);
    vm.prank(manager);
    vm.expectRevert("unsupported source asset");
    testPool.execTransaction(REDEMPTION_VAULT, data);
  }

  function test_revert_redeemRequest_when_pending_asset_not_supported() public {
    _managerRemoveAsset(REDEMPTION_VAULT); // allowed: nothing pending

    bytes memory data = abi.encodeWithSelector(IMidasRedemptionVault.redeemRequest.selector, usdcData.asset, 1e18);
    vm.prank(manager);
    vm.expectRevert("pending redemption not supported");
    testPool.execTransaction(REDEMPTION_VAULT, data);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Withdrawal, state 1: pool only holds mAPOLLO (nothing pending)
  // ═══════════════════════════════════════════════════════════════════════

  function test_assetGuard_getBalance_returns_token_amount() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 tokenBal = _mApolloBalance();
    assertGt(tokenBal, 0, "holds mAPOLLO");
    assertEq(mTokenAssetGuard.getBalance(address(testPool), MAPOLLO), tokenBal, "raw token amount");
  }

  function test_withdraw_transfers_mapollo_in_kind() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 poolBal = _mApolloBalance();

    skip(testPool.getExitRemainingCooldown(manager) + 1);

    uint256 fvBefore = fundManagerLogic.totalFundValue();
    uint256 mBefore = IERC20(MAPOLLO).balanceOf(manager);
    uint256 shares = _balanceOfPool(manager) / 2;
    uint256 portion = (shares * 1e18) / testPool.totalSupply();
    _withdrawSafe(manager, shares);

    uint256 received = IERC20(MAPOLLO).balanceOf(manager) - mBefore;
    assertEq(received, (poolBal * portion) / 1e18, "received exact mAPOLLO portion in-kind");
    assertApproxEqRel(
      fundManagerLogic.totalFundValue(),
      fvBefore - (fvBefore * portion) / 1e18,
      NAV_TOLERANCE,
      "NAV reduced by exactly the withdrawn portion"
    );
  }

  /// @notice The last holder can fully exit (portion = 1e18) when nothing is pending — the pending
  ///         guard early-returns on a zero claim before its 100%-portion restriction.
  function test_full_withdraw_works_when_nothing_pending() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 poolMBal = _mApolloBalance();
    uint256 poolUsdc = _usdcBalance();

    skip(testPool.getExitRemainingCooldown(manager) + 1);

    uint256 usdcBefore = IERC20(usdcData.asset).balanceOf(manager);
    _withdrawSafe(manager, _balanceOfPool(manager));

    assertEq(testPool.totalSupply(), 0, "all shares burned");
    assertEq(IERC20(MAPOLLO).balanceOf(manager), poolMBal, "entire mAPOLLO position received");
    assertEq(IERC20(usdcData.asset).balanceOf(manager) - usdcBefore, poolUsdc, "entire USDC balance received");
    assertEq(_mApolloBalance(), 0, "pool emptied of mAPOLLO");
    assertEq(_usdcBalance(), 0, "pool emptied of USDC");
  }

  /// @notice A settled-but-unpruned request id must not block a full exit: only Pending status
  ///         counts toward the claim.
  function test_full_withdraw_works_with_stale_settled_request_id() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 requestId = _managerRedeemRequest(_mApolloBalance() / 2);
    _settleRedeemRequest(requestId);
    assertEq(redemptionGuard.getPendingRequestIds(address(testPool), REDEMPTION_VAULT).length, 1, "stale id present");

    skip(testPool.getExitRemainingCooldown(manager) + 1);
    _withdrawSafe(manager, _balanceOfPool(manager));

    assertEq(testPool.totalSupply(), 0, "all shares burned");
    assertEq(_mApolloBalance(), 0, "pool emptied of mAPOLLO");
    assertEq(_usdcBalance(), 0, "pool emptied of USDC");
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Async redemption (redeemRequest) tracking + withdrawal in state 2
  // ═══════════════════════════════════════════════════════════════════════

  function test_manager_redeemRequest_tracks_pending_and_preserves_value() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 mBal = _mApolloBalance();
    uint256 fvBefore = fundManagerLogic.totalFundValue();

    uint256 redeemAmt = mBal / 2;
    uint256 requestId = _managerRedeemRequest(redeemAmt);

    // The request is recorded for the pool.
    uint256[] memory ids = redemptionGuard.getPendingRequestIds(address(testPool), REDEMPTION_VAULT);
    assertEq(ids.length, 1, "one pending request");
    assertEq(ids[0], requestId, "request id recorded");

    // The pending claim is valued at the net mToken amount recorded in the request (this vault
    // charges no standard-redemption fee, so net equals the requested amount).
    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), redeemAmt, "pending balance");

    // mAPOLLO left the pool but its NAV is carried by the pending claim.
    assertEq(_mApolloBalance(), mBal - redeemAmt, "mAPOLLO reduced");
    assertApproxEqRel(fundManagerLogic.totalFundValue(), fvBefore, NAV_TOLERANCE, "NAV continuity");
  }

  /// @notice The tracked request list is capped: every id costs an external status check in each NAV
  ///         computation, so a manager must not be able to bloat the pricing loop with dust requests.
  function test_revert_redeemRequest_above_max_tracked_requests() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));

    uint256 max = redemptionGuard.MAX_TRACKED_REQUESTS();
    for (uint256 i; i < max; ++i) {
      _managerRedeemRequest(1e18); // Midas minimum redemption amount
    }

    bytes memory data = abi.encodeWithSelector(IMidasRedemptionVault.redeemRequest.selector, usdcData.asset, 1e18);
    vm.prank(manager);
    vm.expectRevert("too many pending requests");
    testPool.execTransaction(REDEMPTION_VAULT, data);
  }

  /// @notice Realistic manager behavior: several concurrent requests. The claim is the SUM of the
  ///         still-Pending amounts; settling one leaves the others intact, and pruning a mixed
  ///         settled/pending list keeps exactly the pending ids (exercises the swap-and-pop path).
  function test_multiple_pending_requests_sum_settle_and_prune() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 mBal = _mApolloBalance();
    uint256 fvBefore = fundManagerLogic.totalFundValue();

    uint256 amt1 = mBal / 4;
    uint256 amt2 = mBal / 8;
    uint256 amt3 = mBal / 16;
    uint256 id1 = _managerRedeemRequest(amt1);
    uint256 id2 = _managerRedeemRequest(amt2);
    uint256 id3 = _managerRedeemRequest(amt3);

    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), amt1 + amt2 + amt3, "sum of pending");
    assertApproxEqRel(fundManagerLogic.totalFundValue(), fvBefore, NAV_TOLERANCE, "NAV continuity");

    // Settle the middle request; the other two keep carrying the claim.
    _settleRedeemRequest(id2);
    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), amt1 + amt3, "settled request excluded");

    // Pruning the mixed list removes exactly the settled id (order is not preserved by swap-and-pop).
    redemptionGuard.pruneSettledRequests(address(testPool), REDEMPTION_VAULT);
    uint256[] memory ids = redemptionGuard.getPendingRequestIds(address(testPool), REDEMPTION_VAULT);
    assertEq(ids.length, 2, "only pending ids kept");
    assertTrue((ids[0] == id1 && ids[1] == id3) || (ids[0] == id3 && ids[1] == id1), "pending ids kept");
    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), amt1 + amt3, "balance unchanged by prune");

    // Withdrawal math holds against the summed claim.
    skip(testPool.getExitRemainingCooldown(manager) + 1);
    _withdrawAndAssertFairMTokenShare(manager, _balanceOfPool(manager) / 4, amt1 + amt3);
  }

  /// @notice Two holders, sequential withdrawals while a claim is outstanding: each nets their exact
  ///         share of every leg (free+pending mAPOLLO and the USDC balance), and the second
  ///         withdrawal is still exact after the first changed supply and balances.
  function test_two_holders_sequential_withdrawals_while_pending() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));

    // Second depositor enters while the pool holds mAPOLLO; shares are minted at NAV.
    address investor = makeAddr("investor");
    uint256 investorShares = _investorDeposit(investor, 10_000e6);
    assertApproxEqRel(
      (investorShares * testPool.tokenPrice()) / 1e18,
      fundManagerLogic.assetValue(usdcData.asset, 10_000e6),
      NAV_TOLERANCE,
      "shares minted at NAV"
    );

    uint256 pendingAmt = _mApolloBalance() / 2;
    _managerRedeemRequest(pendingAmt);

    skip(testPool.getExitRemainingCooldown(investor) + 1);

    // Holder 1: investor exits fully.
    uint256 free1 = _mApolloBalance();
    uint256 usdcPool1 = _usdcBalance();
    uint256 portion1 = (investorShares * 1e18) / testPool.totalSupply();
    _withdrawSafe(investor, investorShares);

    assertApproxEqRel(
      IERC20(MAPOLLO).balanceOf(investor),
      ((free1 + pendingAmt) * portion1) / 1e18,
      1e12,
      "holder1 fair mAPOLLO share"
    );
    assertEq(IERC20(usdcData.asset).balanceOf(investor), (usdcPool1 * portion1) / 1e18, "holder1 exact USDC leg");

    // Holder 2: manager withdraws 10% afterwards; math still exact on the reduced pool. (A much
    // larger cut would rightly revert: the grossed-up pending payment must fit in the free balance,
    // which holder 1's exit just reduced.)
    uint256 free2 = _mApolloBalance();
    uint256 usdcPool2 = _usdcBalance();
    uint256 mgrShares = _balanceOfPool(manager) / 10;
    uint256 portion2 = (mgrShares * 1e18) / testPool.totalSupply();
    uint256 mgrMBefore = IERC20(MAPOLLO).balanceOf(manager);
    uint256 mgrUsdcBefore = IERC20(usdcData.asset).balanceOf(manager);
    _withdrawSafe(manager, mgrShares);

    assertApproxEqRel(
      IERC20(MAPOLLO).balanceOf(manager) - mgrMBefore,
      ((free2 + pendingAmt) * portion2) / 1e18,
      1e12,
      "holder2 fair mAPOLLO share"
    );
    assertEq(
      IERC20(usdcData.asset).balanceOf(manager) - mgrUsdcBefore,
      (usdcPool2 * portion2) / 1e18,
      "holder2 exact USDC leg"
    );

    // The claim never moved: it still belongs to the pool for the remaining holders.
    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), pendingAmt, "claim intact");
  }

  /// @notice While a redemption is pending, a withdrawer receives their full mAPOLLO entitlement —
  ///         `portion * (free + pending)` — entirely out of the pool's free mAPOLLO balance, and the
  ///         pending claim stays with the pool.
  function test_withdraw_while_pending_pays_share_from_free_mtoken() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 mBal = _mApolloBalance();

    uint256 pendingAmt = mBal / 2;
    _managerRedeemRequest(pendingAmt);
    uint256 free = _mApolloBalance();

    skip(testPool.getExitRemainingCooldown(manager) + 1);

    uint256 fvBefore = fundManagerLogic.totalFundValue();
    uint256 shares = _balanceOfPool(manager) / 4;
    uint256 portion = (shares * 1e18) / testPool.totalSupply();
    uint256 mBefore = IERC20(MAPOLLO).balanceOf(manager);
    _withdrawSafe(manager, shares);

    // Fair share of the combined position (free + pending), all paid in mAPOLLO from the free balance.
    uint256 received = IERC20(MAPOLLO).balanceOf(manager) - mBefore;
    assertApproxEqRel(received, ((free + pendingAmt) * portion) / 1e18, 1e12, "fair mAPOLLO share");
    assertEq(_mApolloBalance(), free - received, "paid from free balance");

    // The pending claim is untouched and still belongs to the pool.
    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), pendingAmt, "pending claim intact");
    assertApproxEqRel(
      fundManagerLogic.totalFundValue(),
      fvBefore - (fvBefore * portion) / 1e18,
      NAV_TOLERANCE,
      "NAV reduced by exactly the withdrawn portion"
    );
  }

  /// @notice If the free mAPOLLO balance cannot cover the withdrawer's share of the pending claim,
  ///         the withdrawal reverts until the curator settles the request.
  function test_revert_withdraw_while_pending_when_insufficient_free_mtoken() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    _managerRedeemRequest(_mApolloBalance()); // everything pending, free balance = 0

    skip(testPool.getExitRemainingCooldown(manager) + 1);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(testPool));
    uint256 shares = _balanceOfPool(manager) / 2;
    vm.prank(manager);
    vm.expectRevert("not enough available balance_1");
    testPool.withdrawSafe(shares, complexAssetsData);
  }

  /// @notice A 100% withdrawal cannot be serviced while a claim is outstanding (helper restriction);
  ///         irrelevant in practice as protocol-owned holders never fully exit.
  function test_revert_full_withdraw_while_pending() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    _managerRedeemRequest(_mApolloBalance() / 2);

    skip(testPool.getExitRemainingCooldown(manager) + 1);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(testPool));
    uint256 shares = _balanceOfPool(manager);
    vm.prank(manager);
    vm.expectRevert("invalid withdraw portion");
    testPool.withdrawSafe(shares, complexAssetsData);
  }

  /// @notice Deposits keep working while a claim is outstanding — even with zero free mAPOLLO, when
  ///         withdrawals are blocked — and shares are minted at a NAV that includes the claim.
  function test_deposit_works_while_redemption_pending() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    _managerRedeemRequest(_mApolloBalance()); // everything pending: withdrawals blocked, deposits not

    uint256 tokenPriceBefore = testPool.tokenPrice();

    uint256 minted = _investorDeposit(makeAddr("investor"), 10_000e6);

    assertApproxEqRel(
      (minted * testPool.tokenPrice()) / 1e18,
      fundManagerLogic.assetValue(usdcData.asset, 10_000e6),
      NAV_TOLERANCE,
      "shares minted at NAV including the claim"
    );
    assertApproxEqRel(testPool.tokenPrice(), tokenPriceBefore, NAV_TOLERANCE, "share price continuity");
  }

  /// @notice HAZARD PIN, NOT A SUPPORTED FLOW. Plain `approveRequest` carries no rate variance bound
  ///         (only `safeApproveRequest` checks against the request-time rate), so a curator settling
  ///         below the recorded rate pays the pool less tokenOut than the claim was valued at — the
  ///         difference lands on the holders remaining at settlement. This test pins the size of that
  ///         markdown so the exposure stays visible.
  function test_settlement_at_drifted_rate_hazard_marks_nav_down() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 redeemAmt = _mApolloBalance() / 2;
    uint256 requestId = _managerRedeemRequest(redeemAmt);

    uint256 fvBefore = fundManagerLogic.totalFundValue();
    uint256 claimValue = fundManagerLogic.assetValue(MAPOLLO, redeemAmt);
    (, , , , uint256 mTokenRate, ) = IMidasRedemptionVault(REDEMPTION_VAULT).redeemRequests(requestId);

    // Curator approves 1% below the request-time rate.
    _settleRedeemRequestAtRate(requestId, (mTokenRate * 99) / 100);

    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), 0, "pending cleared");
    assertApproxEqRel(
      fundManagerLogic.totalFundValue(),
      fvBefore - claimValue / 100,
      MIDAS_RATE_TOLERANCE,
      "NAV marked down by exactly the rate drift on the claim"
    );
  }

  function test_redeemRequest_settlement_clears_pending_and_withdrawals_flow() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 requestId = _managerRedeemRequest(_mApolloBalance() / 2);
    uint256 fvBefore = fundManagerLogic.totalFundValue();

    uint256 usdcBefore = _usdcBalance();
    _settleRedeemRequest(requestId);

    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), 0, "pending cleared");
    assertGt(_usdcBalance(), usdcBefore, "USDC settled into pool");
    // Settlement swaps the claim for USDC at the request-time rate, so NAV is continuous.
    assertApproxEqRel(fundManagerLogic.totalFundValue(), fvBefore, NAV_TOLERANCE, "NAV continuity across settlement");

    // With nothing pending, withdrawals proceed on the plain in-kind path.
    skip(testPool.getExitRemainingCooldown(manager) + 1);
    _withdrawSafe(manager, _balanceOfPool(manager) / 2);
  }

  /// @notice Anyone can prune settled ids so NAV computations stop paying for stale entries.
  function test_pruneSettledRequests_cleans_stale_ids_after_settlement() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 requestId = _managerRedeemRequest(_mApolloBalance() / 2);
    _settleRedeemRequest(requestId);

    // The settled id lingers (pruning is lazy) but no longer counts toward the pending balance.
    assertEq(redemptionGuard.getPendingRequestIds(address(testPool), REDEMPTION_VAULT).length, 1, "stale id kept");
    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), 0, "no pending balance");

    vm.prank(makeAddr("anyone"));
    redemptionGuard.pruneSettledRequests(address(testPool), REDEMPTION_VAULT);

    assertEq(redemptionGuard.getPendingRequestIds(address(testPool), REDEMPTION_VAULT).length, 0, "pruned");
  }

  /// @notice The state-2 withdrawal math composes with pool fees (the production vault is fee-bearing):
  ///         exit-fee share transfers shrink the effective portion, but every leg — free+pending
  ///         mAPOLLO and the USDC balance — must be paid at the SAME effective portion.
  function test_fee_pool_state2_withdrawal_consistent_across_legs() public {
    // 10% performance, 1% streaming, 0.25% entry, 0.5% exit.
    testPool = _createMidasPool(1000, 100, 25, 50);
    fundManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 pendingAmt = _mApolloBalance() / 2;
    _managerRedeemRequest(pendingAmt);

    skip(testPool.getExitRemainingCooldown(manager) + 1);

    uint256 free = _mApolloBalance();
    uint256 usdcPool = _usdcBalance();
    uint256 shares = _balanceOfPool(manager) / 4;
    uint256 supplyBefore = testPool.totalSupply();
    uint256 mBefore = IERC20(MAPOLLO).balanceOf(manager);
    uint256 usdcBefore = IERC20(usdcData.asset).balanceOf(manager);
    _withdrawSafe(manager, shares);

    uint256 portionM = ((IERC20(MAPOLLO).balanceOf(manager) - mBefore) * 1e18) / (free + pendingAmt);
    uint256 portionU = ((IERC20(usdcData.asset).balanceOf(manager) - usdcBefore) * 1e18) / usdcPool;
    assertApproxEqRel(portionM, portionU, 1e12, "same effective portion across all legs");
    // Exit fee (and fee share minting) shrink the withdrawn portion below the nominal share ratio.
    assertLt(portionM, (shares * 1e18) / supplyBefore, "exit fee reduces the withdrawn portion");
    assertGt(portionM, 0, "withdrawal paid out");
  }

  /// @notice INVARIANT DEFENSE: a vault must never transact at an over/understated total value.
  ///         Midas `rejectRequest` turns a request Canceled (terminal) WITHOUT returning the mToken,
  ///         and the manual ops return is not attributable on-chain — so the pending guard freezes
  ///         ALL pricing (deposits, withdrawals, trading) instead of understating total value, until
  ///         the guard owner verifies the tokens are back and reconciles.
  function test_reject_request_freezes_pricing_until_owner_reconciles() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 mBal = _mApolloBalance();
    uint256 fvBefore = fundManagerLogic.totalFundValue();

    uint256 redeemAmt = mBal / 2;
    uint256 requestId = _managerRedeemRequest(redeemAmt);
    _rejectRedeemRequest(requestId);
    assertEq(_mApolloBalance(), mBal - redeemAmt, "mAPOLLO NOT auto-returned by Midas");

    // All pricing is frozen, so every vault interaction reverts.
    vm.expectRevert("canceled redemption unreconciled");
    fundManagerLogic.totalFundValue();

    address investor = makeAddr("investor");
    deal(usdcData.asset, investor, 1_000e6);
    vm.startPrank(investor);
    IERC20(usdcData.asset).approve(address(testPool), 1_000e6);
    vm.expectRevert("canceled redemption unreconciled");
    testPool.deposit(usdcData.asset, 1_000e6);
    vm.stopPrank();

    skip(testPool.getExitRemainingCooldown(manager) + 1);
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _getEmptyPoolComplexAssetsData(address(testPool));
    uint256 shares = _balanceOfPool(manager) / 2;
    vm.prank(manager);
    vm.expectRevert("canceled redemption unreconciled");
    testPool.withdrawSafe(shares, complexAssetsData);

    // Permissionless pruning skips Canceled ids: the freeze holds.
    vm.prank(makeAddr("anyone"));
    redemptionGuard.pruneSettledRequests(address(testPool), REDEMPTION_VAULT);
    vm.expectRevert("canceled redemption unreconciled");
    fundManagerLogic.totalFundValue();

    // Even after Midas ops return the tokens the freeze holds — the return transfer carries no
    // on-chain link to the request, so only an explicit attestation can lift it.
    _midasOpsReturnMTokens(redeemAmt);
    assertEq(_mApolloBalance(), mBal, "mAPOLLO back in the pool");
    vm.expectRevert("canceled redemption unreconciled");
    fundManagerLogic.totalFundValue();

    // Guard owner reconciles -> pricing resumes at exactly the pre-reject value: at no point could
    // anyone deposit or withdraw at an understated value.
    vm.prank(owner);
    redemptionGuard.reconcileCanceledRequests(address(testPool), REDEMPTION_VAULT);
    assertApproxEqRel(fundManagerLogic.totalFundValue(), fvBefore, NAV_TOLERANCE, "value restored, freeze lifted");

    vm.prank(manager);
    testPool.withdrawSafe(shares, complexAssetsData);
  }

  function test_revert_reconcile_canceled_requests_not_owner() public {
    // Reasonless revert with an EOA owner (the Safe-signer probe calls a non-contract).
    vm.prank(manager);
    vm.expectRevert();
    redemptionGuard.reconcileCanceledRequests(address(testPool), REDEMPTION_VAULT);
  }

  /// @notice mAPOLLO also cannot be disabled while a rejected request awaits its manual return —
  ///         the incoming tokens must land accounted.
  function test_revert_remove_mapollo_asset_while_canceled_unreconciled() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 requestId = _managerRedeemRequest(_mApolloBalance()); // mAPOLLO balance -> 0
    _rejectRedeemRequest(requestId);

    vm.expectRevert("pending redemption in progress");
    _managerRemoveAsset(MAPOLLO);
  }

  /// @notice The integration is gated to protocol-chosen vaults: a pool that was never whitelisted
  ///         cannot enable the mToken (type 42) or the pending-redemption asset (type 43, which
  ///         reads the type 42 guard's whitelist).
  function test_revert_add_midas_assets_when_pool_not_whitelisted() public {
    vm.startPrank(manager);
    PoolManagerLogic otherManagerLogic = PoolManagerLogic(
      PoolLogic(
        poolFactoryProxy.createFund({
          _privatePool: false,
          _manager: manager,
          _managerName: "Manager",
          _fundName: "NotWhitelisted",
          _fundSymbol: "NWL",
          _performanceFeeNumerator: 0,
          _managerFeeNumerator: 0,
          _entryFeeNumerator: 0,
          _exitFeeNum: 0,
          _supportedAssets: _usdcOnlyAssets()
        })
      ).poolManagerLogic()
    );

    IHasSupportedAsset.Asset[] memory addAssets = new IHasSupportedAsset.Asset[](1);
    addAssets[0] = IHasSupportedAsset.Asset({asset: REDEMPTION_VAULT, isDeposit: false});
    vm.expectRevert("pool not whitelisted");
    otherManagerLogic.changeAssets(addAssets, new address[](0));

    addAssets[0] = IHasSupportedAsset.Asset({asset: MAPOLLO, isDeposit: false});
    vm.expectRevert("pool not whitelisted");
    otherManagerLogic.changeAssets(addAssets, new address[](0));

    // The redemption vault's txGuard enforces the same whitelist for consistency.
    PoolLogic otherPool = PoolLogic(otherManagerLogic.poolLogic());
    bytes memory data = abi.encodeWithSelector(IMidasRedemptionVault.redeemRequest.selector, usdcData.asset, 1e18);
    vm.expectRevert("pool not whitelisted");
    otherPool.execTransaction(REDEMPTION_VAULT, data);
    vm.stopPrank();
  }

  /// @notice Un-whitelisting blocks new asset configuration but does not disturb a live position.
  function test_unwhitelisted_pool_keeps_operating_but_cannot_reconfigure() public {
    vm.prank(owner);
    redemptionGuard.setPoolsWhitelist(_whitelistSetting(address(testPool), false));

    // Re-adding (or updating) the Midas assets is blocked...
    IHasSupportedAsset.Asset[] memory addAssets = new IHasSupportedAsset.Asset[](1);
    addAssets[0] = IHasSupportedAsset.Asset({asset: MAPOLLO, isDeposit: false});
    vm.prank(manager);
    vm.expectRevert("pool not whitelisted");
    fundManagerLogic.changeAssets(addAssets, new address[](0));

    // ...but the already-enabled assets keep functioning.
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    assertGt(_mApolloBalance(), 0, "existing position still operable");
  }

  function test_revert_whitelist_setter_not_owner() public {
    // With an EOA owner the Safe-signer probe reverts reasonlessly (call to a non-contract), so no
    // message is matched; a Safe owner would produce "not owner or Safe owner".
    PoolsWhitelist.WhitelistSetting[] memory settings = _whitelistSetting(address(testPool), false);
    vm.prank(manager);
    vm.expectRevert();
    redemptionGuard.setPoolsWhitelist(settings);
  }

  /// @notice Several pools can be (un)whitelisted in a single transaction.
  function test_whitelist_batch_setter() public {
    address poolA = makeAddr("poolA");
    address poolB = makeAddr("poolB");

    PoolsWhitelist.WhitelistSetting[] memory settings = new PoolsWhitelist.WhitelistSetting[](3);
    settings[0] = PoolsWhitelist.WhitelistSetting({poolLogic: poolA, whitelisted: true});
    settings[1] = PoolsWhitelist.WhitelistSetting({poolLogic: poolB, whitelisted: true});
    settings[2] = PoolsWhitelist.WhitelistSetting({poolLogic: address(testPool), whitelisted: false});

    vm.prank(owner);
    redemptionGuard.setPoolsWhitelist(settings);

    assertTrue(redemptionGuard.poolsWhitelist(poolA), "poolA whitelisted");
    assertTrue(redemptionGuard.poolsWhitelist(poolB), "poolB whitelisted");
    assertFalse(redemptionGuard.poolsWhitelist(address(testPool)), "testPool un-whitelisted");
  }

  /// @notice Neither Midas asset may ever be configured as an investor deposit asset.
  function test_revert_add_mapollo_as_deposit_asset() public {
    vm.expectRevert("deposit not supported");
    _managerAddDepositAsset(MAPOLLO);
  }

  function test_revert_add_redemption_vault_as_deposit_asset() public {
    vm.expectRevert("deposit not supported");
    _managerAddDepositAsset(REDEMPTION_VAULT);
  }

  /// @notice The redemption vault position asset cannot be disabled while a claim is Pending —
  ///         the claim IS the asset's balance, so the standard non-empty-asset check rejects removal.
  function test_revert_remove_redemption_vault_asset_while_redemption_pending() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    _managerRedeemRequest(_mApolloBalance() / 2);

    vm.expectRevert("cannot remove non-empty asset");
    _managerRemoveAsset(REDEMPTION_VAULT);
  }

  /// @notice mAPOLLO cannot be disabled while a redemption is Pending: a rejected request is settled
  ///         by ops transferring mAPOLLO back to the pool, which must remain an accounted asset.
  function test_revert_remove_mapollo_asset_while_redemption_pending() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    // Everything pending: mAPOLLO balance drops to 0, so the base ERC20 removal check would pass.
    _managerRedeemRequest(_mApolloBalance());

    vm.expectRevert("pending redemption in progress");
    _managerRemoveAsset(MAPOLLO);
  }

  /// @notice USDC (the request's `tokenOut`) cannot be disabled while a redemption is Pending:
  ///         settlement pays USDC into the pool, which must remain an accounted asset.
  function test_revert_remove_usdc_asset_while_redemption_pending() public {
    // Convert the entire USDC balance so its balance is 0 and the base ERC20 removal check passes.
    uint256 allUsdc18 = INITIAL_USDC * 1e12;
    _managerDepositInstant(allUsdc18, _minMTokenOut(allUsdc18));
    assertEq(_usdcBalance(), 0, "all USDC converted");
    _managerRedeemRequest(_mApolloBalance() / 2);

    vm.expectRevert("pending redemption in progress");
    _managerRemoveAsset(usdcData.asset);
  }

  /// @dev Rejection here is only a device to reach a "nothing Pending, zero USDC balance" state;
  ///      the subject under test is that the removal block lifts once no request is Pending.
  function test_remove_usdc_asset_after_reject() public {
    uint256 allUsdc18 = INITIAL_USDC * 1e12;
    _managerDepositInstant(allUsdc18, _minMTokenOut(allUsdc18));
    uint256 requestId = _managerRedeemRequest(_mApolloBalance() / 2);
    _rejectRedeemRequest(requestId);

    // Nothing Pending anymore (request is Canceled), so the tokenOut can be disabled again.
    // Swap in another deposit asset since a pool must always keep at least one.
    IHasSupportedAsset.Asset[] memory addAssets = new IHasSupportedAsset.Asset[](1);
    addAssets[0] = IHasSupportedAsset.Asset({asset: wethData.asset, isDeposit: true});
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = usdcData.asset;
    vm.prank(manager);
    fundManagerLogic.changeAssets(addAssets, removeAssets);

    assertFalse(fundManagerLogic.isSupportedAsset(usdcData.asset), "USDC removed");
  }

  function test_remove_mapollo_asset_after_settlement() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 requestId = _managerRedeemRequest(_mApolloBalance());
    _settleRedeemRequest(requestId);

    _managerRemoveAsset(MAPOLLO);

    assertFalse(fundManagerLogic.isSupportedAsset(MAPOLLO), "mAPOLLO removed");
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EasySwapperV2 withdrawal (claim-only: the mToken cannot be swapped)
  // ═══════════════════════════════════════════════════════════════════════

  /// @notice Two-step EasySwapperV2 withdrawal: `initWithdrawal` pays the mAPOLLO leg in-kind into
  ///         the WithdrawalVault, which tracks it; the no-swap `completeWithdrawal()` then claims
  ///         every tracked leg to the depositor. (The swap-based variant is not applicable —
  ///         mAPOLLO has no secondary-market liquidity for the swapper to unroll.)
  function test_easyswapper_initWithdrawal_tracks_mapollo_and_claim_pays_in_kind() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 free = _mApolloBalance();
    uint256 usdcPool = _usdcBalance();

    skip(testPool.getExitRemainingCooldown(manager) + 1);

    uint256 shares = _balanceOfPool(manager) / 2;
    uint256 portion = (shares * 1e18) / testPool.totalSupply();

    vm.startPrank(manager);
    IERC20(address(testPool)).approve(address(easySwapperV2Proxy), shares);
    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Proxy.initWithdrawal(
      address(testPool),
      shares,
      _getEmptyPoolComplexAssetsData(address(testPool))
    );

    // The vault holds and tracks both legs: the in-kind mAPOLLO and the USDC share.
    uint256 expectedMToken = (free * portion) / 1e18;
    assertEq(IERC20(MAPOLLO).balanceOf(vault), expectedMToken, "mAPOLLO portion in vault");
    assertEq(_trackedBalanceOf(trackedAssets, MAPOLLO), expectedMToken, "mAPOLLO tracked");
    assertEq(_trackedBalanceOf(trackedAssets, usdcData.asset), (usdcPool * portion) / 1e18, "USDC tracked");

    uint256 mBefore = IERC20(MAPOLLO).balanceOf(manager);
    uint256 usdcBefore = IERC20(usdcData.asset).balanceOf(manager);
    easySwapperV2Proxy.completeWithdrawal();
    vm.stopPrank();

    assertEq(IERC20(MAPOLLO).balanceOf(manager) - mBefore, expectedMToken, "mAPOLLO claimed in-kind");
    assertEq(IERC20(usdcData.asset).balanceOf(manager) - usdcBefore, (usdcPool * portion) / 1e18, "USDC claimed");
    assertEq(IERC20(MAPOLLO).balanceOf(vault), 0, "vault emptied of mAPOLLO");
  }

  /// @notice While an async redemption is pending, the EasySwapperV2 withdrawal nets the full
  ///         entitlement `portion * (free + pending)` in mAPOLLO — the pending leg (type 43) is
  ///         paid out of the pool's free balance into the WithdrawalVault, tracked via the mToken's
  ///         own entry (type 42), and claimed without a swap. The claim stays with the pool.
  function test_easyswapper_withdrawal_while_pending_claims_fair_mtoken_share() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));
    uint256 pendingAmt = _mApolloBalance() / 2;
    _managerRedeemRequest(pendingAmt);
    uint256 free = _mApolloBalance();

    skip(testPool.getExitRemainingCooldown(manager) + 1);

    uint256 shares = _balanceOfPool(manager) / 4;
    uint256 portion = (shares * 1e18) / testPool.totalSupply();

    vm.startPrank(manager);
    IERC20(address(testPool)).approve(address(easySwapperV2Proxy), shares);
    easySwapperV2Proxy.initWithdrawal(address(testPool), shares, _getEmptyPoolComplexAssetsData(address(testPool)));

    uint256 mBefore = IERC20(MAPOLLO).balanceOf(manager);
    easySwapperV2Proxy.completeWithdrawal();
    vm.stopPrank();

    assertApproxEqRel(
      IERC20(MAPOLLO).balanceOf(manager) - mBefore,
      ((free + pendingAmt) * portion) / 1e18,
      1e12,
      "fair mAPOLLO share claimed"
    );
    assertEq(pendingGuard.getBalance(address(testPool), REDEMPTION_VAULT), pendingAmt, "claim stays with the pool");
  }

  /// @notice Hard stop: the swap-based `completeWithdrawal` refuses to route the mToken through the
  ///         swapper, even if a frontend supplies swap data that found a route through some thin
  ///         pool. The mToken stays tracked and claimable via the no-swap `completeWithdrawal()`.
  function test_revert_easyswapper_swap_completeWithdrawal_with_mapollo_src() public {
    _managerDepositInstant(BUY_AMOUNT, _minMTokenOut(BUY_AMOUNT));

    skip(testPool.getExitRemainingCooldown(manager) + 1);

    uint256 shares = _balanceOfPool(manager) / 2;

    vm.startPrank(manager);
    IERC20(address(testPool)).approve(address(easySwapperV2Proxy), shares);
    (, address vault) = easySwapperV2Proxy.initWithdrawal(
      address(testPool),
      shares,
      _getEmptyPoolComplexAssetsData(address(testPool))
    );

    // Swap data listing the tracked mAPOLLO as a source token; router payload is irrelevant —
    // the vault must reject the source before ever reaching the swapper.
    IWithdrawalVault.MultiInSingleOutData memory swapData;
    swapData.srcData = new ISwapper.SrcTokenSwapDetails[](1);
    swapData.srcData[0] = ISwapper.SrcTokenSwapDetails({
      token: IERC20Local(MAPOLLO),
      amount: IERC20(MAPOLLO).balanceOf(vault),
      aggregatorData: ISwapper.AggregatorData({routerKey: bytes32(0), swapData: ""})
    });
    swapData.destData = ISwapper.DestData({destToken: IERC20Local(usdcData.asset), minDestAmount: 0});

    vm.expectRevert("src token not swappable");
    easySwapperV2Proxy.completeWithdrawal(swapData, 0);

    // The rejected mToken is still claimable in-kind.
    uint256 mBefore = IERC20(MAPOLLO).balanceOf(manager);
    easySwapperV2Proxy.completeWithdrawal();
    vm.stopPrank();

    assertGt(IERC20(MAPOLLO).balanceOf(manager) - mBefore, 0, "mAPOLLO still claimable in-kind");
  }
}
