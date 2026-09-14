// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin/v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Vm} from "forge-std/Vm.sol";

import {HyperEVMSetup} from "test/integration/utils/foundry/chains/HyperEVMSetup.t.sol";
import {CoreSimulatorLib} from "test/integration/hyperevm/test-suite/hyperevm-lib/CoreSimulatorLib.sol";
import {HLConstants} from "test/integration/hyperevm/test-suite/hyperevm-lib/lib/HLConstants.sol";
import {PrecompileLib} from "test/integration/hyperevm/test-suite/hyperevm-lib/lib/PrecompileLib.sol";
import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";

import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IAssetGuard} from "contracts/interfaces/guards/IAssetGuard.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "contracts/interfaces/IPoolManagerLogic.sol";
import {ICoreWriter} from "contracts/interfaces/hyperliquid/ICoreWriter.sol";
import {IHyperliquidWithdrawalManager} from "contracts/interfaces/hyperliquid/IHyperliquidWithdrawalManager.sol";
import {IHyperliquidCoreWriterContractGuard} from "contracts/interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";
import {HyperliquidConstants} from "contracts/utils/hyperliquid/HyperliquidConstants.sol";
import {HyperliquidWithdrawalManager} from "contracts/utils/hyperliquid/HyperliquidWithdrawalManager.sol";
import {PrecompileHelper} from "contracts/utils/hyperliquid/PrecompileHelper.sol";
import {HyperliquidSpotPriceAggregator} from "contracts/priceAggregators/HyperliquidSpotPriceAggregator.sol";
import {FixedPointMathLib} from "contracts/utils/FixedPointMathLib.sol";
import {IChangeAssets} from "test/integration/utils/foundry/CoreBackboneSetup.sol";

/// @title HyperliquidWithdrawalManager integration tests
/// @notice Exercises the async withdrawal lifecycle (announceAndReduce -> bridge -> settle / cancel)
///         and the withdrawal-specific isPublic / validation branches added to the guards.
/// @dev Inherits PrecompileHelper for shared constants (_USDC_ADDRESS, _DEX_ID_CORE_PERP, etc.)
///      and precompile read helpers (accountMarginSummary, spotBalance, position).
/// @dev The `Skip` suffix excludes this suite from default `forge test` runs (`no_match_contract = "Skip"`
///      in foundry.toml). The CoreWriter guard no longer marks withdrawal-manager actions public, so the WM
///      cannot execute through the pool and these tests cannot pass until the guard is wired back up.
contract HyperliquidWithdrawalManagerTestsSkip is HyperEVMSetup, PrecompileHelper {
  using FixedPointMathLib for uint256;

  uint256 public constant blockNumber = 36674788;

  IHyperliquidWithdrawalManager internal withdrawalManager;

  /// @notice A non-manager caller used to prove WM-driven actions are public.
  address internal anon = makeAddr("anon");

  /// @dev Second withdrawer sharing the pool with `investor` (concurrency test).
  address internal investorB = makeAddr("investorB");

  /// @dev Perp index 150 on the forked HyperCore (MOODENG; szDecimals 0, maxLeverage 3).
  uint32 internal constant _PERP_INDEX = 150;
  /// @dev BTC (szDecimals 5) and ETH (szDecimals 4).
  uint32 internal constant _PERP_INDEX_BTC = 0;
  uint32 internal constant _PERP_INDEX_ETH = 1;

  /// @dev Native HYPE token index (150) and its HYPE/USDC spot pair index (107) on HyperCore. Unlike
  ///      XAUT0 (a regular spot token whose system address is `0x2000... + tokenIndex`), HYPE is a
  ///      *system* spot asset reached via the special system address 0x2222...2222.
  uint64 internal constant _HYPE_TOKEN_INDEX = 150;
  uint64 internal constant _HYPE_SPOT_INDEX = 107;

  /// @dev HIP-3 dex id 1 and a perp on it (asset id = 100_000 + dexId * 10_000 + meta index),
  ///      mirroring the production xyz:GOLD deployment. The Core simulator has no per-dex accounting
  ///      (margin summaries ignore the dex id and sendAsset is a no-op), so the HIP-3 dex's margin
  ///      summary and position are supplied via targeted precompile mocks (exact-calldata match, so
  ///      core-dex reads still hit the real simulator).
  uint256 internal constant _HIP3_DEX_ID = 1;
  uint32 internal constant _HIP3_PERP_ASSET_ID = 110_003;
  uint32 internal constant _HIP3_PERP_INDEX = 10_003;

  /// @dev Mirror of the CoreWriter's event, for expectEmit assertions on queued Core actions.
  event RawAction(address indexed user, bytes data);

  /////////////////////////////////////////////
  //                  Setup                  //
  /////////////////////////////////////////////

  function setUp() public virtual override {
    super.setUp();
    _deployAndWireWithdrawalManager();
  }

  /// @dev Pin a fresher fork block than the shared HyperEVM default.
  function _forkBlockNumber() internal pure override returns (uint256) {
    return blockNumber;
  }

  /// @dev Use the real forked USDC/USD Chainlink answer instead of pinning it to exactly $1, so the
  ///      value invariants are exercised against a slightly de-pegged USDC (the realistic case).
  // solhint-disable-next-line no-empty-blocks
  function _mockUSDCPriceFeed() internal override {}

  /// @dev Deploys the WM behind a transparent proxy and registers it on the CoreWriter guard.
  function _deployAndWireWithdrawalManager() internal {
    vm.startPrank(owner);

    address wmImplementation = deployCode("HyperliquidWithdrawalManager.sol");

    bytes memory initializeData = abi.encodeWithSignature(
      "initialize(address,address,address)",
      owner,
      address(poolFactoryProxy),
      address(hyperliquidCoreWriterContractGuard)
    );

    withdrawalManager = IHyperliquidWithdrawalManager(
      address(new TransparentUpgradeableProxy(wmImplementation, proxyAdmin, initializeData))
    );

    hyperliquidCoreWriterContractGuard.setWithdrawalManager(address(withdrawalManager));

    vm.stopPrank();
  }

  /////////////////////////////////////////////
  //              Test Helpers               //
  /////////////////////////////////////////////

  /// @dev Investor deposits USDC and waits out the exit cooldown so pool tokens are transferrable.
  function _depositAndCooldown(uint256 amount) internal returns (uint256 shares) {
    vm.prank(investor);
    IPoolLogic(hyperliquidTestPool).deposit(usdc, amount);
    shares = IPoolLogic(hyperliquidTestPool).balanceOf(investor);
    // Pool token transfers (used by announceAndReduce) are blocked during exit cooldown.
    skip(6 minutes);
  }

  /// @dev Funds an arbitrary `user` with USDC, deposits it, and waits out the exit cooldown. Used by
  ///      the concurrency test, where a second investor must be funded and approved on the fly.
  function _depositAndCooldown(address user, uint256 amount) internal returns (uint256 shares) {
    deal(usdc, user, amount);
    vm.startPrank(user);
    IERC20(usdc).approve(hyperliquidTestPool, amount);
    IPoolLogic(hyperliquidTestPool).deposit(usdc, amount);
    vm.stopPrank();
    shares = IPoolLogic(hyperliquidTestPool).balanceOf(user);
    // Pool token transfers (used by announceAndReduce) are blocked during exit cooldown.
    skip(6 minutes);
  }

  /// @dev Bridges USDC from the pool to a Core dex and processes the next Core block.
  function _bridgeAndProcess(uint256 amount, uint32 destinationDex) internal {
    _bridgeUSDCToCore(amount, destinationDex);
    CoreSimulatorLib.nextBlock();
  }

  /// @dev Moves nearly all of the pool's Core spot USDC into the perp account (leaving a small
  ///      buffer) and opens a MOODENG perp long, locking most funding as margin so the WM's
  ///      withdrawal must reduce the position rather than bridge idle USDC. Returns position size.
  function _openPerpLong() internal returns (int64 szi) {
    return _openPerpLong(2, 11_000);
  }

  /// @dev Parameterized perp long open. `leverage` is forced on the position; `notionalBps` sizes
  ///      the notional as a fraction of the perp funding (10_000 = 1x). Higher notionalBps means more
  ///      of the funding is locked as margin and less is free to bridge during withdrawal.
  function _openPerpLong(uint16 leverage, uint256 notionalBps) internal returns (int64 szi) {
    return _openPerp(true, leverage, notionalBps);
  }

  /// @dev Opens a perp SHORT mirroring {_openPerpLong}'s default sizing. Returns the (negative) size.
  function _openPerpShort() internal returns (int64 szi) {
    return _openPerp(false, 2, 11_000);
  }

  /// @dev Parameterized perp open. `isLong` chooses the direction; `leverage` is forced on the
  ///      position; `notionalBps` sizes the notional as a fraction of the perp funding (10_000 = 1x).
  ///      Higher notionalBps means more of the funding is locked as margin and less is free to bridge.
  function _openPerp(bool isLong, uint16 leverage, uint256 notionalBps) internal returns (int64 szi) {
    // The manager may only open a non-reduce-only perp order on an approved asset.
    IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[]
      memory approvals = new IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[](1);
    approvals[0] = IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting({assetId: _PERP_INDEX, approved: true});
    vm.prank(owner);
    hyperliquidCoreWriterContractGuard.setApprovedAssets(approvals);

    // Bridging only credits Core spot USDC; move all but a small buffer into the perp account so it
    // backs the position as margin (manager-initiated USD class transfer, spot -> perp).
    uint256 perpFundingUsdc6 = _coreSpotUsdc() - 50e6;
    bytes memory toPerp = abi.encodePacked(
      uint8(1),
      HLConstants.USD_CLASS_TRANSFER_ACTION,
      abi.encode(uint64(perpFundingUsdc6), true)
    );
    _placeLimitOrder(toPerp);
    CoreSimulatorLib.nextBlock();

    // The perp position must carry leverage > 0 for the simulator to open it (fork value may be 0).
    CoreSimulatorLib.forcePerpLeverage(hyperliquidTestPool, uint16(_PERP_INDEX), leverage);

    uint64 markPx = PrecompileLib.oraclePx(_PERP_INDEX);
    if (markPx == 0) markPx = uint64(40e6);
    CoreSimulatorLib.setMarkPx(_PERP_INDEX, markPx);

    // Size the position so notional ~= notionalBps/10_000 of the funding. A notional above 1x keeps
    // the perp's free `rawUsd` negative (a leveraged position borrows), so the WM sees no free Core
    // USDC and must reduce. MOODENG has szDecimals 0, so size = notional / markPx; CoreWriter order
    // sizes are 8 decimals, hence the * 1e8.
    uint256 targetNotional6 = (perpFundingUsdc6 * notionalBps) / 10_000;
    uint64 orderSz = uint64((targetNotional6 / markPx) * 1e8);

    // IOC order limited 1% past mark (above for a buy, below for a sell) so it fills while staying
    // within the guard's 2% slippage cap.
    uint256 normMark = uint256(PrecompileLib.normalizedMarkPx(_PERP_INDEX)) * 100;
    uint64 limitPx = isLong ? uint64((normMark * 101) / 100) : uint64((normMark * 99) / 100);
    bytes memory openOrder = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(uint32(_PERP_INDEX), isLong, limitPx, orderSz, false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );
    _placeLimitOrder(openOrder);
    CoreSimulatorLib.nextBlock();

    szi = position(hyperliquidTestPool, _PERP_INDEX).szi;
  }

  /// @dev Approves the WM to pull the user's pool tokens and announces a withdrawal.
  function _announce(
    address user,
    uint256 tokenAmount,
    uint32[] memory perpAssetIds,
    uint32[] memory spotAssetIds
  ) internal {
    vm.prank(user);
    IERC20(hyperliquidTestPool).approve(address(withdrawalManager), tokenAmount);
    vm.prank(user);
    withdrawalManager.announceAndReduce(hyperliquidTestPool, tokenAmount, perpAssetIds, spotAssetIds);
  }

  /// @dev Announces a withdrawal with no perp/spot ids on behalf of `user`. Returns true if it was
  ///      accepted (the reduce was skipped), false if it reverted (so the shared perp is untouched).
  function _tryAnnounceWithoutPerpId(address user, uint256 tokenAmount) internal returns (bool accepted) {
    vm.prank(user);
    IERC20(hyperliquidTestPool).approve(address(withdrawalManager), tokenAmount);
    vm.prank(user);
    try withdrawalManager.announceAndReduce(hyperliquidTestPool, tokenAmount, _emptyIds(), _emptyIds()) {
      return true;
    } catch {
      return false;
    }
  }

  function _emptyIds() internal pure returns (uint32[] memory ids) {
    ids = new uint32[](0);
  }

  /// @dev Current Core spot USDC balance (token index 0) in 6 decimals.
  function _coreSpotUsdc() internal view returns (uint256) {
    return uint256(PrecompileLib.spotBalance(hyperliquidTestPool, uint64(_USDC_TOKEN_INDEX)).total) / 1e2;
  }

  /// @dev Effective leverage of the pool's core perp account in WAD (open notional / equity). A
  ///      partial withdrawal must preserve this: the reduce-only order shrinks notional and the
  ///      proportional margin bridge shrinks equity by the same fraction, so remaining holders keep
  ///      the same position health. Returns 0 when there is no perp equity.
  function _perpLeverageWad() internal view returns (uint256) {
    PrecompileHelper.AccountMarginSummary memory summary = accountMarginSummary(hyperliquidTestPool, _DEX_ID_CORE_PERP);
    if (summary.accountValue <= 0) return 0;
    return (uint256(summary.ntlPos) * 1e18) / uint256(uint64(summary.accountValue));
  }

  /// @dev Sets the XAUT0 spot price and buys `sizeE8` (8-dec) XAUT0 on Core. Returns the spot pair id.
  function _buyXaut0(uint64 sizeE8) internal returns (uint32 xaut0AssetId) {
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100);
    xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, limitPrice, sizeE8, false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );
    _placeLimitOrder(orderActionData);
    CoreSimulatorLib.nextBlock();
  }

  /// @dev Registers native HYPE (system address 0x2222...2222) as a type-40 spot asset on the asset
  ///      handler and the test pool, mirroring how the shared setup wires XAUT0. Exercises the
  ///      *system* spot asset path (special-cased system address) rather than the `0x2000 + index`
  ///      derived address used for ordinary spot tokens.
  function _enableHypeSpotAsset() internal {
    vm.startPrank(owner);
    address hypeAggregator = address(
      new HyperliquidSpotPriceAggregator(_HYPE_SPOT_INDEX, HyperEVMConfig.USDC_USD_PRICE_FEED)
    );
    assetHandlerProxy.addAsset(
      HyperEVMConfig.HYPE_SYSTEM_ADDRESS,
      uint16(AssetTypeIncomplete.HYPERLIQUID_SPOT),
      hypeAggregator
    );
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: HyperEVMConfig.HYPE_SYSTEM_ADDRESS, isDeposit: false});
    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(assetsToAdd, new address[](0));
  }

  /// @dev Sets the HYPE spot price ($40) and buys `sizeE8` (8-dec) HYPE on Core. Returns the spot pair
  ///      id. HYPE has szDecimals 2, so the price is expressed in (8 - 2) = 6 decimals.
  function _buyHype(uint64 sizeE8) internal returns (uint32 hypeAssetId) {
    uint64 hypePrice = 40e6;
    hyperCore.setSpotPx(uint32(_HYPE_SPOT_INDEX), hypePrice);

    uint64 normalizedPrice = hypePrice * 100; // 6 -> 8 decimals
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100); // +1% slippage for immediate fill
    hypeAssetId = 10000 + uint32(_HYPE_SPOT_INDEX);

    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(hypeAssetId, true, limitPrice, sizeE8, false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );
    _placeLimitOrder(orderActionData);
    CoreSimulatorLib.nextBlock();
  }

  /// @dev Wraps a single asset id in a length-1 array.
  function _ids(uint32 id) internal pure returns (uint32[] memory arr) {
    arr = new uint32[](1);
    arr[0] = id;
  }

  /// @dev Announces with the given ids, advances a block, bridges, advances again, then asserts that
  ///      settle reverts. If `reason` is non-empty it must match exactly; an empty `reason` accepts
  ///      any revert (used where an un-reduced perp can no longer be valued after the bridge pull).
  function _announceBridgeExpectSettleRevert(
    uint256 tokenAmount,
    uint32[] memory perpIds,
    uint32[] memory spotIds,
    bytes memory reason
  ) internal {
    _announce(investor, tokenAmount, perpIds, spotIds);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    if (reason.length == 0) {
      vm.expectRevert();
    } else {
      vm.expectRevert(reason);
    }
    withdrawalManager.settle(hyperliquidTestPool);
  }

  /// @dev Announces with the given ids and asserts that the announce call itself reverts with
  ///      `reason`. Used where the WM rejects the withdrawal up front (e.g. an open perp whose id
  ///      was omitted, or a spot id with no matching balance).
  function _announceExpectRevert(
    uint256 tokenAmount,
    uint32[] memory perpIds,
    uint32[] memory spotIds,
    bytes memory reason
  ) internal {
    vm.prank(investor);
    IERC20(hyperliquidTestPool).approve(address(withdrawalManager), tokenAmount);
    vm.prank(investor);
    vm.expectRevert(reason);
    withdrawalManager.announceAndReduce(hyperliquidTestPool, tokenAmount, perpIds, spotIds);
  }

  /// @dev Deposits, parks all USDC on Core, buys a 1 XAUT0 spot position and opens a perp long.
  ///      Returns the quarter-share withdrawal amount and both asset ids. With an open perp, the
  ///      reduce branch runs whenever the perp id is omitted, so announce reverts up front rather
  ///      than risking the bridge over-draining the un-reduced position.
  function _setupPerpAndSpot() internal returns (uint256 withdrawShares, uint32 perpId, uint32 xaut0AssetId) {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    xaut0AssetId = _buyXaut0(uint64(1e8)); // 1 XAUT0
    assertGt(_openPerpLong(), 0, "perp long opened");
    withdrawShares = shares / 4;
    perpId = _PERP_INDEX;
  }

  /// @dev Enables a HIP-3 dex id on the CoreWriter guard so the WM iterates it during withdrawals.
  function _enableHip3Dex(uint256 dexId) internal {
    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory settings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: dexId,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.ENABLED
    });
    vm.prank(owner);
    hyperliquidCoreWriterContractGuard.setDexIdStatus(settings);
  }

  /// @dev Mocks the account-margin-summary precompile for (`_HIP3_DEX_ID`, pool). Exact-calldata
  ///      match: reads for other dex ids (different first word) still hit the real simulator.
  function _mockHip3DexSummary(int64 accountValue, uint64 marginUsed, uint64 ntlPos) internal {
    vm.mockCall(
      _ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS,
      abi.encode(_HIP3_DEX_ID, hyperliquidTestPool),
      abi.encode(
        PrecompileHelper.AccountMarginSummary({
          accountValue: accountValue,
          marginUsed: marginUsed,
          ntlPos: ntlPos,
          rawUsd: accountValue - int64(ntlPos)
        })
      )
    );
  }

  /// @dev Mocks the position/oracle/asset-info precompiles for `_HIP3_PERP_INDEX` so announce can
  ///      cover and size the HIP-3 reduce-only order (the simulator has no HIP-3 perp registry).
  function _mockHip3PerpPosition(int64 szi, uint64 oraclePrice, uint8 szDecimals) internal {
    vm.mockCall(
      _POSITION_PRECOMPILE_ADDRESS,
      abi.encode(hyperliquidTestPool, uint16(_HIP3_PERP_INDEX)),
      abi.encode(PrecompileHelper.Position({szi: szi, entryNtl: 0, isolatedRawUsd: 0, leverage: 20, isIsolated: false}))
    );
    vm.mockCall(_ORACLE_PX_PRECOMPILE_ADDRESS, abi.encode(_HIP3_PERP_INDEX), abi.encode(oraclePrice));
    vm.mockCall(
      _PERP_ASSET_INFO_PRECOMPILE_ADDRESS,
      abi.encode(_HIP3_PERP_INDEX),
      abi.encode(
        PrecompileHelper.PerpAssetInfo({
          coin: "xyz:GOLD",
          marginTableId: 0,
          szDecimals: szDecimals,
          maxLeverage: 25,
          onlyIsolated: false
        })
      )
    );
  }

  /// @dev Mocks the spot-balance precompile for (pool, `tokenIndex`) with part of the balance on
  ///      hold under resting orders (the simulator hard-codes hold = 0). Exact-calldata match;
  ///      other tokens still hit the real simulator.
  function _mockSpotBalanceWithHold(uint64 tokenIndex, uint64 total, uint64 hold) internal {
    vm.mockCall(
      _SPOT_BALANCE_PRECOMPILE_ADDRESS,
      abi.encode(hyperliquidTestPool, tokenIndex),
      abi.encode(PrecompileHelper.SpotBalance({total: total, hold: hold, entryNtl: 0}))
    );
  }

  /// @dev The Core-wei sendAsset payload the WM must queue to consolidate `amountUsdc6` from the
  ///      HIP-3 dex into the core perp dex during bridge.
  function _expectedConsolidationAction(uint256 amountUsdc6) internal view returns (bytes memory) {
    return
      abi.encodePacked(
        uint8(1),
        HyperliquidConstants.ACTION_SEND_ASSET,
        abi.encode(
          hyperliquidTestPool,
          address(0),
          uint32(_HIP3_DEX_ID),
          _DEX_ID_CORE_PERP,
          _USDC_TOKEN_INDEX,
          uint64(amountUsdc6 * 1e2)
        )
      );
  }

  /// @dev Creates a valid factory pool that supports only USDC — no CoreWriter asset, so it has no
  ///      Hyperliquid integration. Used to exercise the PoolHasNoHLIntegration guard.
  function _createNonHlPool() internal returns (address pool) {
    IHasSupportedAsset.Asset[] memory assets = new IHasSupportedAsset.Asset[](1);
    assets[0] = IHasSupportedAsset.Asset({asset: usdc, isDeposit: true});
    vm.prank(manager);
    pool = poolFactoryProxy.createFund({
      _privatePool: false,
      _manager: manager,
      _managerName: "No HL Manager",
      _fundName: "No HL Pool",
      _fundSymbol: "NHL",
      _performanceFeeNumerator: 0,
      _managerFeeNumerator: 0,
      _entryFeeNumerator: 0,
      _exitFeeNum: 0,
      _supportedAssets: assets
    });
  }

  /////////////////////////////////////////////
  //         Phase 1: Lifecycle              //
  /////////////////////////////////////////////

  /// @notice Full happy path where Core already holds enough free USDC, so no positions are reduced.
  /// @dev The WM (not the manager) drives the perp/spot CoreWriter actions during bridge(); these
  ///      only succeed if the guard returns isPublic=true for WM-initiated usdClassTransfer/spotSend.
  function test_withdraw_core_spot_only__no_positions_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    // Move ALL of the pool's USDC to the Core spot account. With no USDC left on EVM, the bridge
    // step must actually queue the spot send action, exercising the guard's isPublic gating.
    uint256 poolUsdc = _getPoolUSDCBalance();
    _bridgeAndProcess(poolUsdc, HLConstants.SPOT_DEX);

    // The whole EVM balance lands on Core (1:1, no fee on this deposit path).
    assertEq(_coreSpotUsdc(), poolUsdc, "core holds all bridged USDC");
    assertEq(IERC20(usdc).balanceOf(hyperliquidTestPool), 0, "pool EVM USDC drained to core");

    uint256 withdrawShares = shares / 4;
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    // Value invariants: the withdrawal lifecycle must not change price per share, and may only
    // reduce total fund value at settle (by the amount paid to the user).
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 fundValueStart = _getTotalFundValue();

    _announce(investor, withdrawShares, _emptyIds(), _emptyIds());

    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.REDUCED), "state REDUCED");
    assertEq(pending.amount, withdrawShares, "amount recorded");

    // Escrowing shares in the WM changes neither price per share nor total fund value (exactly).
    assertEq(IPoolLogic(hyperliquidTestPool).tokenPrice(), tokenPriceStart, "tokenPrice == after announce");
    assertEq(_getTotalFundValue(), fundValueStart, "fundValue == after announce");

    // Bridge must wait at least one block after announce.
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);

    pending = withdrawalManager.pendingWithdrawals(investor, hyperliquidTestPool);
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.BRIDGED), "state BRIDGED");

    // Bridging just relocates USDC from Core to EVM, so the totals are unchanged (exactly).
    assertEq(IPoolLogic(hyperliquidTestPool).tokenPrice(), tokenPriceStart, "tokenPrice == after bridge");
    assertEq(_getTotalFundValue(), fundValueStart, "fundValue == after bridge");

    // Process the queued Core->EVM bridge so USDC lands back in the pool.
    CoreSimulatorLib.nextBlock();
    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and investor received USDC.
    pending = withdrawalManager.pendingWithdrawals(investor, hyperliquidTestPool);
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");

    // No trading happened, so the investor receives the USD value of the burned shares priced at the
    // pre-withdrawal token price.
    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    uint256 expectedReceived = withdrawShares.mulWadDown(tokenPriceStart) / 1e12; // 18dp USD -> 6dp USDC
    // `expectedReceived` prices the burned shares at $1/USDC, but the investor is paid in USDC valued
    // at the real (slightly de-pegged) Chainlink price, so allow a wider delta for that FX drift.
    assertApproxEqRel(received, expectedReceived, 0.0005e18, "investor received ~ expected USDC value"); // 0.05% max relative delta

    // Price per share is preserved; total fund value drops by what was paid out.
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    assertApproxEqRel(
      _getTotalFundValue(),
      fundValueStart - expectedReceived * 1e12,
      0.0001e18, // 0.01% max relative delta
      "fundValue dropped by payout"
    );
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");
  }

  /// @notice Happy path with USDC split across EVM and the Core spot account (no positions). The
  ///         EVM USDC partially offsets the bridge target, so the WM bridges only the remaining
  ///         deficit and settles — distinct from the full-offset case which fails fast with
  ///         NoBridgeNeeded (see {test_revert_announce_noBridgeNeeded_whenEvmUsdcSufficient}).
  function test_withdraw_evm_core_spot__no_positions_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    // Keep a small slice of USDC on EVM and bridge the bulk to Core spot. The EVM slice is smaller
    // than the bridge target for a quarter withdrawal, so the deficit is positive (partial offset).
    uint256 poolUsdc = _getPoolUSDCBalance();
    uint256 evmKeep = poolUsdc / 10;
    _bridgeAndProcess(poolUsdc - evmKeep, HLConstants.SPOT_DEX);

    assertGt(IERC20(usdc).balanceOf(hyperliquidTestPool), 0, "pool retains some EVM USDC");

    uint256 withdrawShares = shares / 4;
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 fundValueStart = _getTotalFundValue();

    _announce(investor, withdrawShares, _emptyIds(), _emptyIds());
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");

    // No trading happened, so price per share holds and fund value only drops by the payout.
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0001e18, "fundValue dropped by payout"); // 0.01% max relative delta
  }

  /// @notice Large-portion withdrawal with idle EVM USDC in the "dead band": the EVM balance clears
  ///         the raw `hlValue * portion` bridge target but NOT the grossed-up settle demand
  ///         `hlValue * portion / (1 - portion)`. Only `(1 - portion)` of the EVM USDC survives as
  ///         settlement liquidity (the rest is sent to the user directly as the USDC token), so the WM must still bridge the deficit.
  /// @dev Before crediting only the retained EVM liquidity, this reverted `NoBridgeNeeded` on announce
  ///      (raw target < EVM) while a direct withdraw reverted `not enough available balance_1` — the
  ///      withdrawal was unservable by either path.
  function test_withdraw_evm_core_spot__no_positions_largePortion_bridgesAndSettles() public {
    _depositAndCooldown(20_000e6);

    // ~40% of NAV on EVM, ~60% on Core spot, then withdraw 60% of supply. EVM (40%) sits between the
    // raw target (hlValue * 0.6 = 36% of Core) and the grossed demand (hlValue * 1.5 = 90% of Core).
    uint256 poolUsdc = _getPoolUSDCBalance();
    uint256 evmKeep = (poolUsdc * 40) / 100;
    _bridgeAndProcess(poolUsdc - evmKeep, HLConstants.SPOT_DEX);

    assertGt(IERC20(usdc).balanceOf(hyperliquidTestPool), 0, "pool retains EVM USDC");

    uint256 withdrawShares = (IERC20(hyperliquidTestPool).totalSupply() * 60) / 100;
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 fundValueStart = _getTotalFundValue();

    _announce(investor, withdrawShares, _emptyIds(), _emptyIds());
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");

    // No trading happened, so price per share holds and fund value only drops by the payout.
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    // `received * 1e12` prices the payout at $1/USDC; the pool values it at the de-pegged Chainlink
    // price, so at a 60% withdrawal the depeg shows up amplified against the smaller remaining value.
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0008e18, "fundValue dropped by payout"); // 0.08% max relative delta
  }

  /// @notice Happy path with a spot position (XAUT0) present: with no idle EVM USDC, the withdrawal
  ///         bridges the position value from free Core USDC and settles. (Free Core USDC already
  ///         covers the spot-excluding HL bridge, so the reduce branch is skipped and the spot is
  ///         not sold — the small XAUT0 leg is handled proportionally at settle.)
  function test_withdraw_core_spot_only__spot_only_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    // Buy 1 XAUT0 on Core so the pool holds a spot position to be partially sold.
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    // Move all USDC to Core so there is no idle EVM USDC: the withdrawal must bridge from Core
    uint256 poolUsdc = _getPoolUSDCBalance();
    _bridgeAndProcess(poolUsdc, HLConstants.SPOT_DEX);

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100);
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, limitPrice, uint64(1e8), false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );
    _placeLimitOrder(orderActionData);
    CoreSimulatorLib.nextBlock();

    assertEq(
      PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      1e8,
      "pool holds 1 XAUT0"
    );

    uint256 withdrawShares = shares / 4;
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 fundValueStart = _getTotalFundValue();

    uint32[] memory spotIds = new uint32[](1);
    spotIds[0] = xaut0AssetId;

    _announce(investor, withdrawShares, _emptyIds(), spotIds);

    // Advance a Core block so the announce's queued actions are processed on Core.
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");

    // Selling spot incurs slippage, but price per share must stay stable and fund value must only
    // drop by the payout.
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0001e18, "fundValue dropped by payout"); // 0.01% max relative delta
  }

  /// @notice Spot-heavy pool withdrawal must leave remaining holders their proportional spot exposure,
  ///         not over-liquidate the position.
  function test_spotWithdraw_preservesProportionalExposure() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    uint32 xaut0AssetId = _buyXaut0(uint64(7e8)); // 7 XAUT0 @ $2,800 = $19,600

    uint256 spotBefore = PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total;

    uint256 withdrawShares = (shares * 60) / 100;
    uint256 poolPortion = (withdrawShares * 1e18) / IERC20(hyperliquidTestPool).totalSupply();
    uint256 idealRemaining = (spotBefore * (1e18 - poolPortion)) / 1e18;

    uint32[] memory spotIds = _ids(xaut0AssetId);
    _announce(investor, withdrawShares, _emptyIds(), spotIds);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    uint256 spotAfter = PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total;
    assertApproxEqRel(spotAfter, idealRemaining, 0.05e18, "remaining holders keep proportional XAUT0");
  }

  /// @notice Happy path that reduces a perp long position during withdrawal, then settles.
  /// @dev Verifies the WM's reduce-only order path: announcing with the perp asset id must shrink
  ///      the position before bridging and settling.
  function test_withdraw_core_spot_core_perp__perp_only_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    // Park all pool USDC on the Core spot account; the open helper moves most of it into the perp
    // account as margin, leaving little free USDC so the withdrawal must reduce the position.
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    int64 sziBefore = _openPerpLong();
    assertGt(sziBefore, 0, "perp long opened");

    uint256 leverageBefore = _perpLeverageWad();
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    uint32[] memory perpIds = new uint32[](1);
    perpIds[0] = _PERP_INDEX;
    _announce(investor, shares / 4, perpIds, _emptyIds());
    CoreSimulatorLib.nextBlock();

    // The reduce-only sell must have shrunk the long position — by exactly the withdrawal portion
    // (floored onto MOODENG's whole-contract lot grid, hence the small tolerance).
    int64 sziAfter = position(hyperliquidTestPool, _PERP_INDEX).szi;
    assertLt(sziAfter, sziBefore, "perp position reduced");
    assertGt(sziAfter, 0, "position only partially reduced");
    uint256 portion = (shares / 4).divWadDown(IERC20(hyperliquidTestPool).totalSupply());
    assertApproxEqRel(
      uint256(uint64(sziAfter)),
      uint256(uint64(sziBefore)).mulWadDown(1e18 - portion),
      0.01e18, // 1% max relative delta (one whole-contract lot on a few-hundred-contract position)
      "perp position reduced proportionally"
    );
    // Reducing must never make the remaining position riskier (leverage can only stay or drop here,
    // since the freed margin is still in the perp account until bridged out).
    assertLe(_perpLeverageWad(), leverageBefore, "perp leverage not increased by reduce");

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    uint256 fundValueStart = _getTotalFundValue();
    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0001e18, "fundValue dropped by payout"); // 0.01% max relative delta
    // End-to-end: the freed margin was bridged out in proportion to the notional reduced, so the
    // remaining position keeps the same leverage / health as before the withdrawal.
    assertApproxEqRel(_perpLeverageWad(), leverageBefore, 0.001e18, "perp leverage preserved"); // 0.1% max relative delta
  }

  /// @dev Opens one core-perp long of `notionalUsdc6` notional at `leverage`, against margin already
  ///      in the perp account. Can be called twice to stand up two perps in one cross-margin account.
  ///      Order size is 8-dec: `notionalUsdc6 * 10^(8 - szDecimals) / markPx`.
  function _openCorePerpLong(uint32 perpIndex, uint16 leverage, uint256 notionalUsdc6) internal {
    IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[]
      memory approvals = new IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[](1);
    approvals[0] = IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting({assetId: perpIndex, approved: true});
    vm.prank(owner);
    hyperliquidCoreWriterContractGuard.setApprovedAssets(approvals);

    CoreSimulatorLib.forcePerpLeverage(hyperliquidTestPool, uint16(perpIndex), leverage);
    uint64 markPx = PrecompileLib.oraclePx(perpIndex);
    CoreSimulatorLib.setMarkPx(perpIndex, markPx);

    uint8 szDecimals = PrecompileLib.perpAssetInfo(perpIndex).szDecimals;
    uint64 orderSz = uint64((notionalUsdc6 * (10 ** (8 - uint256(szDecimals)))) / markPx);
    uint256 normMark = uint256(PrecompileLib.normalizedMarkPx(perpIndex)) * 100;
    uint64 limitPx = uint64((normMark * 101) / 100);
    bytes memory openOrder = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(uint32(perpIndex), true, limitPx, orderSz, false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );
    _placeLimitOrder(openOrder);
    CoreSimulatorLib.nextBlock();
  }

  /// @dev Deposits, funds one shared cross-margin perp account, and opens two equal core-perp longs
  ///      (BTC + ETH, ~55% of funding each => ~110% aggregate notional). With `_getFreeCoreUsdc` ~0
  ///      the withdrawal is forced onto the reduce path. Returns the deposited share amount.
  function _setupTwoCorePerps() internal returns (uint256 shares) {
    shares = _depositAndCooldown(20_000e6);

    // Park all pool USDC on Core spot, then fund the perp account once (leave a small spot buffer).
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    uint256 fundingUsdc6 = _coreSpotUsdc() - 50e6;

    // Move the funding from Core spot into the shared perp (cross-margin) account so both perps below
    // have margin to open against. (`_openCorePerpLong` opens against this shared balance.)
    bytes memory toPerp = abi.encodePacked(
      uint8(1),
      HLConstants.USD_CLASS_TRANSFER_ACTION,
      abi.encode(uint64(fundingUsdc6), true) // true = spot -> perp
    );
    _placeLimitOrder(toPerp);
    CoreSimulatorLib.nextBlock();

    uint256 perpNotional6 = (fundingUsdc6 * 55) / 100;
    _openCorePerpLong(_PERP_INDEX_BTC, 2, perpNotional6);
    _openCorePerpLong(_PERP_INDEX_ETH, 2, perpNotional6);

    assertGt(position(hyperliquidTestPool, _PERP_INDEX_BTC).szi, 0, "perp BTC opened");
    assertGt(position(hyperliquidTestPool, _PERP_INDEX_ETH).szi, 0, "perp ETH opened");
  }

  /// @notice Two core perps (BTC + ETH) share one cross-margin account and the announce names only
  ///         BTC, omitting the equally-open ETH. Because the bridge's margin pull would shrink the
  ///         shared equity while ETH keeps its full notional (raising leverage for the holders who
  ///         remain), the WM rejects the announce: the supplied ids don't cover the account's open
  ///         perp notional.
  function test_revert_announce_multiPerp_missingOnePerpId() public {
    uint256 shares = _setupTwoCorePerps();

    // Name ONLY BTC; ETH (~half the account's notional) is left uncovered, so the check reverts.
    uint32[] memory perpIds = new uint32[](1);
    perpIds[0] = _PERP_INDEX_BTC;

    _announceExpectRevert(
      shares / 4,
      perpIds,
      _emptyIds(),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__UnreducedPerpPosition.selector)
    );
  }

  /// @notice Companion to the omitted-id revert: naming BOTH open core perps lets the reduce path
  ///         proceed and shrinks each position proportionally, so the shared account's leverage is
  ///         preserved for the holders who remain after a partial withdrawal.
  function test_withdraw_multiPerp_bothIds_preservesLeverage() public {
    uint256 shares = _setupTwoCorePerps();

    int64 sziA_before = position(hyperliquidTestPool, _PERP_INDEX_BTC).szi;
    int64 sziB_before = position(hyperliquidTestPool, _PERP_INDEX_ETH).szi;
    uint256 leverageBefore = _perpLeverageWad();
    assertGt(leverageBefore, 0, "account has leverage");

    // Name both open perps (ascending order, as required). Both are reduced proportionally.
    uint32[] memory perpIds = new uint32[](2);
    perpIds[0] = _PERP_INDEX_BTC;
    perpIds[1] = _PERP_INDEX_ETH;
    _announce(investor, shares / 4, perpIds, _emptyIds());
    CoreSimulatorLib.nextBlock();

    // Move the freed/idle equity out to EVM (action 7 pulls shared perp margin here).
    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    int64 sziA_after = position(hyperliquidTestPool, _PERP_INDEX_BTC).szi;
    int64 sziB_after = position(hyperliquidTestPool, _PERP_INDEX_ETH).szi;

    assertLt(sziA_after, sziA_before, "perp BTC reduced");
    assertLt(sziB_after, sziB_before, "perp ETH reduced");
    // Reduce fills nudge realized PnL/fees, so allow the same 0.1% drift as the single-perp tests.
    assertApproxEqRel(_perpLeverageWad(), leverageBefore, 0.001e18, "perp leverage preserved"); // 0.1% max relative delta
  }

  /// @notice Perp vault that ALSO holds a mid-range amount of idle EVM USDC must still settle. The
  ///         idle EVM USDC is settlement liquidity, but at settle the position guard grosses its
  ///         demand up against the (reduced) perp value and is paid out of that same EVM USDC FIRST,
  ///         so only `(1 - portion)` of the idle EVM USDC effectively backs the gross-up — the WM must
  ///         bridge the rest of the demand from perp margin, not assume the idle EVM USDC covers it.
  /// @dev Reproduces the under-bridge corner the sibling tests miss: a reducible perp (so `coreUsdc6`
  ///      stays ~0, no gross-up applied to the bridge) PLUS idle EVM USDC `E_0 > 0`. The bridge is
  ///      sized `perpValue * portion` but the FULL `E_0` is then subtracted, leaving EVM USDC below
  ///      the guard's `getBalance * portion / (1 - portion)` settle demand, so `settle` reverts. Every
  ///      sibling perp test parks all USDC on Core first (`E_0 = 0`), and the idle-EVM tests hold no
  ///      reducible position (Core USDC is grossed up), so none exercise this shape.
  function test_withdraw_core_perp_with_idle_evm_usdc__bridgesAndSettles() public {
    _depositAndCooldown(20_000e6);

    // Keep ~$4k idle on EVM as settlement liquidity; park the rest on Core, where the open helper
    // moves it into the perp account as margin. Result: perp value + idle EVM USDC, ~no idle Core
    // USDC — the exact shape where the proportional-minus-full-EVM bridge under-provisions.
    uint256 evmKeep = 4_000e6;
    _bridgeAndProcess(_getPoolUSDCBalance() - evmKeep, HLConstants.SPOT_DEX);

    assertGt(_openPerpLong(), 0, "perp long opened");
    assertApproxEqAbs(IERC20(usdc).balanceOf(hyperliquidTestPool), evmKeep, 1, "pool retains idle EVM USDC");

    uint256 leverageBefore = _perpLeverageWad();
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);
    uint256 fundValueStart = _getTotalFundValue();

    // Withdraw half of supply (investor holds ~2/3), naming the perp to reduce. A direct withdraw is
    // impossible here ($4k EVM << the grossed-up demand), so the bridge path must provision correctly.
    uint256 withdrawShares = IERC20(hyperliquidTestPool).totalSupply() / 2;
    _announce(investor, withdrawShares, _ids(_PERP_INDEX), _emptyIds());
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.001e18,
      "tokenPrice ~ after settle"
    ); // 0.1% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.001e18, "fundValue dropped by payout"); // 0.1% max relative delta
    // The idle EVM USDC credit shrinks the margin pull while the position is still reduced by the
    // full portion, so remaining holders' leverage can only drop here — never rise.
    assertLe(_perpLeverageWad(), leverageBefore, "perp leverage not increased");
  }

  /// @notice A pool whose Core money is perp-wallet equity with NO open positions — the normal
  ///         state after a manager closes all perps (HyperCore leaves the freed margin in the perp
  ///         account) — must still bridge and settle. The bridge must decide the perp->spot class
  ///         transfer on perp-wallet EQUITY, not on open notional: gating it on
  ///         "is any position open?" misreads this pool as spot-only, clamps the send to the thin
  ///         spot balance, and every withdrawal dead-ends at settle until the manager manually
  ///         moves the equity to spot.
  function test_withdraw_perp_wallet_cash_no_positions_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // Park most Core cash in the perp wallet without opening any position, keeping a thin spot
    // buffer so the bridge's send exceeds spot and the class transfer is required.
    bytes memory toPerpAction = abi.encodePacked(
      uint8(1),
      HLConstants.USD_CLASS_TRANSFER_ACTION,
      abi.encode(uint64(_coreSpotUsdc() - 2_000e6), true) // true = spot -> perp (dex 0)
    );
    _placeLimitOrder(toPerpAction);
    CoreSimulatorLib.nextBlock();

    PrecompileHelper.AccountMarginSummary memory dex0 = accountMarginSummary(hyperliquidTestPool, _DEX_ID_CORE_PERP);
    assertGt(dex0.accountValue, 0, "perp wallet holds equity");
    assertEq(dex0.ntlPos, 0, "no open notional anywhere");

    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 fundValueStart = _getTotalFundValue();
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    // Perp-wallet equity counts as free, so the reduce is skipped (nothing to reduce anyway).
    _announce(investor, shares / 4, _emptyIds(), _emptyIds());
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");
    // No positions and no trading: price per share holds and fund value drops only by the payout.
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0005e18,
      "tokenPrice ~ after settle"
    ); // 0.05% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0005e18, "fundValue dropped by payout"); // 0.05% max relative delta
  }

  /// @notice A manager's resting reduce-only spot order locks balance under `hold`; an IOC sell
  ///         sized past the spendable `total - hold` is rejected by HyperCore outright — silently,
  ///         post-block — so nothing would be freed and the withdrawal would starve at settle.
  ///         Announce must fail loudly instead when the resting order leaves too little spendable
  ///         balance for the proportional sell.
  function test_revert_announce_spotBalanceOnHold_whenRestingOrderLocksBalance() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    uint32 xaut0AssetId = _buyXaut0(uint64(7e8)); // dominant 7 XAUT0 => the reduce path must sell

    // Full-position take-profit: the entire balance is on hold, nothing is spendable.
    _mockSpotBalanceWithHold(uint64(HyperEVMConfig.XAUT0_TOKEN_INDEX), 7e8, 7e8);

    _announceExpectRevert(
      (shares * 60) / 100,
      _emptyIds(),
      _ids(xaut0AssetId),
      abi.encodeWithSelector(
        HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__SpotBalanceOnHold.selector,
        xaut0AssetId
      )
    );
  }

  /// @notice The skip path's license is "draw only equity above open notional". That is checked at
  ///         announce, but announce and bridge are separate transactions: if the free equity
  ///         evaporates in between (here: a mark move against an open short), the bridge's pull
  ///         would take collateral backing the un-reduced position — remaining holders end up more
  ///         leveraged with no reduce ever running. The bridge must re-check the skip license
  ///         against CURRENT free equity and revert, leaving the withdrawal cancellable.
  function test_revert_bridge_insufficientCoreUsdc_whenSkipPathFreeEquityDrifts() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // Open a perp at ~60% notional: ~40% of the funding stays as free equity, enough for a
    // quarter-withdrawal to take the skip path.
    assertGt(_openPerpLong(2, 6_000), 0, "perp long opened");

    _announce(investor, shares / 4, _emptyIds(), _emptyIds());
    uint256 reserved = HyperliquidWithdrawalManager(address(withdrawalManager)).reservedBridgeUsdc(hyperliquidTestPool);
    assertGt(reserved, 0, "skip path taken");
    CoreSimulatorLib.nextBlock();

    // Drift: the mark doubles before the user bridges. In the simulator's margin model notional
    // grows faster than account value, so the account's free equity (equity - notional) drops
    // below the announced bridge while transferable margin stays ample — only the free-equity
    // bound protects the un-reduced position from being drained.
    CoreSimulatorLib.setMarkPx(uint32(_PERP_INDEX), uint64(10_000), true); // +100%
    PrecompileHelper.AccountMarginSummary memory dex0 = accountMarginSummary(hyperliquidTestPool, _DEX_ID_CORE_PERP);
    uint256 freeAfterDrift = uint64(dex0.accountValue) > dex0.ntlPos ? uint64(dex0.accountValue) - dex0.ntlPos : 0;
    assertLt(freeAfterDrift, reserved, "free equity no longer covers the announced bridge");

    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__InsufficientCoreUsdc.selector);
    withdrawalManager.bridge(hyperliquidTestPool);
  }

  /// @notice A modest resting order must not block the withdrawal: the proportional sell still
  ///         fits the spendable `total - hold`, so the flow sells, bridges and settles as usual.
  function test_withdraw_spot_with_partial_hold_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    uint32 xaut0AssetId = _buyXaut0(uint64(7e8));

    // 1 of 7 XAUT0 on hold: the buffered ~40% sell (~2.9 XAUT0) fits the 6 XAUT0 spendable.
    _mockSpotBalanceWithHold(uint64(HyperEVMConfig.XAUT0_TOKEN_INDEX), 7e8, 1e8);

    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    _announce(investor, (shares * 60) / 100, _emptyIds(), _ids(xaut0AssetId));
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertGt(IERC20(usdc).balanceOf(investor) - investorUsdcBefore, 0, "investor received USDC");
  }

  /// @notice Happy path that reduces a perp SHORT position during withdrawal, then settles.
  /// @dev Mirrors {test_withdraw_core_spot_core_perp__perp_only_bridgesAndSettles} for a short,
  ///      exercising the reduce order's `isBuy = pos.szi < 0` branch (a short is reduced by buying
  ///      back, so a wrong isBuy would grow the position instead of shrinking it).
  function test_withdraw_core_spot_core_perp__perp_only_short_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    int64 sziBefore = _openPerpShort();
    assertLt(sziBefore, 0, "perp short opened");

    uint256 leverageBefore = _perpLeverageWad();
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    uint32[] memory perpIds = new uint32[](1);
    perpIds[0] = _PERP_INDEX;
    _announce(investor, shares / 4, perpIds, _emptyIds());
    CoreSimulatorLib.nextBlock();

    // The reduce-only buy must have shrunk the short (szi moves toward zero), not flipped it long.
    int64 sziAfter = position(hyperliquidTestPool, _PERP_INDEX).szi;
    assertGt(sziAfter, sziBefore, "perp short position reduced");
    assertLt(sziAfter, 0, "position only partially reduced");
    // A wrong isBuy would GROW the short and raise leverage; reducing must only keep or lower it.
    assertLe(_perpLeverageWad(), leverageBefore, "perp leverage not increased by reduce");

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    uint256 fundValueStart = _getTotalFundValue();
    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0001e18, "fundValue dropped by payout"); // 0.01% max relative delta
    // End-to-end: notional and equity shrank by the same fraction, so the short keeps its leverage.
    assertApproxEqRel(_perpLeverageWad(), leverageBefore, 0.001e18, "perp leverage preserved"); // 0.1% max relative delta
  }

  /// @notice Happy path where the vault holds BOTH a perp long and a spot (XAUT0) position;
  ///         announcing with both ids reduces each, then the withdrawal bridges and settles.
  function test_withdraw_core_spot_core_perp__perp_and_spot_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    // Park all pool USDC on the Core spot account: enough to buy XAUT0 and (via the open helper's
    // USD class transfer) to fund the perp account.
    uint256 poolUsdc = _getPoolUSDCBalance();
    _bridgeAndProcess(poolUsdc, HLConstants.SPOT_DEX);

    // Buy a 0.5 XAUT0 spot position: small relative to the perp so the perp dominates the HL value
    // (selling spot transiently inflates the guard's getBalance as proceeds land as Core spot USDC),
    // but large enough that the 1/8 proportional sell clears HyperCore's lot grid (XAUT0 szDecimals 2
    // -> a 0.01-XAUT0 lot); a 0.1 position would floor the sell to zero.
    uint64 normalizedPrice = xaut0Price * 100;
    uint64 xaut0Limit = normalizedPrice + ((normalizedPrice * 1) / 100);
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);
    bytes memory buyXaut0 = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, xaut0Limit, uint64(5e7), false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );
    _placeLimitOrder(buyXaut0);
    CoreSimulatorLib.nextBlock();

    // Open a perp long.
    int64 sziBefore = _openPerpLong();
    assertGt(sziBefore, 0, "perp long opened");
    assertEq(
      PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      5e7,
      "pool holds 0.5 XAUT0"
    );
    uint256 leverageBefore = _perpLeverageWad();
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    uint32[] memory perpIds = new uint32[](1);
    perpIds[0] = _PERP_INDEX;
    uint32[] memory spotIds = new uint32[](1);
    spotIds[0] = xaut0AssetId;

    _announce(investor, shares / 8, perpIds, spotIds);
    CoreSimulatorLib.nextBlock();

    // Both positions were reduced.
    assertLt(position(hyperliquidTestPool, _PERP_INDEX).szi, sziBefore, "perp position reduced");
    assertLt(
      PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      5e7,
      "spot position reduced"
    );
    assertLe(_perpLeverageWad(), leverageBefore, "perp leverage not increased by reduce");

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    uint256 fundValueStart = _getTotalFundValue();
    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0001e18, "fundValue dropped by payout"); // 0.01% max relative delta
    // End-to-end: the perp's notional and equity shrank proportionally, preserving its leverage.
    assertApproxEqRel(_perpLeverageWad(), leverageBefore, 0.001e18, "perp leverage preserved"); // 0.1% max relative delta
  }

  /// @notice Stress variant of {test_withdraw_core_spot_core_perp__perp_and_spot_bridgesAndSettles}
  ///         with a LARGER spot leg (1 full XAUT0) and a LARGER withdrawal portion (half the shares).
  /// @dev Exercises the proportional sizing at a large portion. The position guard grosses the
  ///      required USDC up by 1/(1-portion) at settle (see
  ///      OutsidePositionWithdrawalHelper._calculateWithdrawBalance), but that gross-up applies to the
  ///      POST-reduction getBalance: the WM reduces the perp/spot proportionally during announce, so
  ///      the shrunk balance's grossed-up demand equals the plain proportional USDC the WM bridged.
  ///      Static Core USDC is the only component the bridge itself grosses up. The perp's notional and
  ///      equity shrink together, so leverage and price per share are preserved through settle.
  function test_withdraw_core_spot_core_perp__perp_and_spot_largeLeg_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    uint256 poolUsdc = _getPoolUSDCBalance();
    _bridgeAndProcess(poolUsdc, HLConstants.SPOT_DEX);

    // Buy a full 1 XAUT0 spot position (10x the happy-path leg) so the spot leg materially
    // contributes to the HL value being withdrawn.
    uint64 normalizedPrice = xaut0Price * 100;
    uint64 xaut0Limit = normalizedPrice + ((normalizedPrice * 1) / 100);
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);
    bytes memory buyXaut0 = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, xaut0Limit, uint64(1e8), false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );
    _placeLimitOrder(buyXaut0);
    CoreSimulatorLib.nextBlock();

    int64 sziBefore = _openPerpLong();
    assertGt(sziBefore, 0, "perp long opened");
    assertEq(
      PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      1e8,
      "pool holds 1 XAUT0"
    );

    uint256 leverageBefore = _perpLeverageWad();
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    uint32[] memory perpIds = new uint32[](1);
    perpIds[0] = _PERP_INDEX;
    uint32[] memory spotIds = new uint32[](1);
    spotIds[0] = xaut0AssetId;

    // Withdraw HALF the investor's shares (large portion magnifies the 1/(1-portion) gross-up).
    _announce(investor, shares / 2, perpIds, spotIds);
    CoreSimulatorLib.nextBlock();

    assertLt(position(hyperliquidTestPool, _PERP_INDEX).szi, sziBefore, "perp position reduced");
    assertLt(
      PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      1e8,
      "spot position reduced"
    );
    assertLe(_perpLeverageWad(), leverageBefore, "perp leverage not increased by reduce");

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    uint256 fundValueStart = _getTotalFundValue();
    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    // The large legs incur more slippage than the other happy paths, so fund value drops slightly
    // more than the raw payout; allow a wider tolerance for that trading cost.
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0005e18, "fundValue dropped by payout"); // 0.05% max relative delta
    // End-to-end: even at a large portion the proportional reduce + bridge preserves perp leverage.
    // Wider tolerance than the other happy paths: at this portion the guard's 1/(1-portion) gross-up
    // plus the lot-grid flooring of the reduce size (MOODENG szDecimals 0 -> whole-contract lots)
    // leave the position fractionally under-reduced, so post-cycle leverage drifts up a touch more.
    assertApproxEqRel(_perpLeverageWad(), leverageBefore, 0.02e18, "perp leverage preserved"); // 2% max relative delta
  }

  /// @notice Happy path for the *system* spot asset HYPE (system address 0x2222...2222): with no idle
  ///         EVM USDC the withdrawal bridges the position value from free Core USDC and settles.
  ///         Mirrors {test_withdraw_core_spot_only__spot_only_bridgesAndSettles} but for native HYPE
  ///         instead of XAUT0, proving the HYPE system address flows through the same withdrawal path.
  function test_withdraw_core_spot_only__spot_only_hype_bridgesAndSettles() public {
    _enableHypeSpotAsset();

    uint256 shares = _depositAndCooldown(20_000e6);

    // Move all USDC to Core so there is no idle EVM USDC: the withdrawal must bridge from Core.
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // Buy 1 HYPE on Core so the pool holds a system spot position.
    uint32 hypeAssetId = _buyHype(uint64(1e8));

    assertEq(PrecompileLib.spotBalance(hyperliquidTestPool, _HYPE_TOKEN_INDEX).total, 1e8, "pool holds 1 HYPE");

    uint256 withdrawShares = shares / 4;
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 fundValueStart = _getTotalFundValue();

    _announce(investor, withdrawShares, _emptyIds(), _ids(hypeAssetId));
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");

    // Selling spot incurs slippage, but price per share must stay stable and fund value must only
    // drop by the payout.
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0001e18, "fundValue dropped by payout"); // 0.01% max relative delta
  }

  /// @notice Happy path where the vault holds BOTH a perp long and a system spot (HYPE) position;
  ///         announcing with both ids reduces each, then the withdrawal bridges and settles. Mirrors
  ///         {test_withdraw_core_spot_core_perp__perp_and_spot_bridgesAndSettles} but with native HYPE.
  function test_withdraw_core_spot_core_perp__perp_and_spot_hype_bridgesAndSettles() public {
    _enableHypeSpotAsset();

    uint256 shares = _depositAndCooldown(20_000e6);

    // Park all pool USDC on the Core spot account: enough to buy HYPE and (via the open helper's
    // USD class transfer) to fund the perp account.
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // Buy a 0.5 HYPE spot position: small relative to the perp so the perp dominates the HL value,
    // but large enough that the 1/8 proportional sell clears HyperCore's lot grid (HYPE szDecimals 2
    // -> a 0.01-HYPE lot); a 0.1 position would floor the sell to zero.
    uint32 hypeAssetId = _buyHype(uint64(5e7));

    int64 sziBefore = _openPerpLong();
    assertGt(sziBefore, 0, "perp long opened");
    assertEq(PrecompileLib.spotBalance(hyperliquidTestPool, _HYPE_TOKEN_INDEX).total, 5e7, "pool holds 0.5 HYPE");

    uint256 leverageBefore = _perpLeverageWad();
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    uint32[] memory perpIds = new uint32[](1);
    perpIds[0] = _PERP_INDEX;

    _announce(investor, shares / 8, perpIds, _ids(hypeAssetId));
    CoreSimulatorLib.nextBlock();

    // Both positions were reduced.
    assertLt(position(hyperliquidTestPool, _PERP_INDEX).szi, sziBefore, "perp position reduced");
    assertLt(PrecompileLib.spotBalance(hyperliquidTestPool, _HYPE_TOKEN_INDEX).total, 5e7, "spot position reduced");
    assertLe(_perpLeverageWad(), leverageBefore, "perp leverage not increased by reduce");

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    uint256 fundValueStart = _getTotalFundValue();
    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0001e18, "fundValue dropped by payout"); // 0.01% max relative delta
    // End-to-end: the perp's notional and equity shrank proportionally, preserving its leverage.
    assertApproxEqRel(_perpLeverageWad(), leverageBefore, 0.001e18, "perp leverage preserved"); // 0.1% max relative delta
  }

  /////////////////////////////////////////////
  //      Phase 2: State machine & reverts   //
  /////////////////////////////////////////////

  function test_revert_announce_zeroAmount() public {
    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__ZeroAmount.selector);
    withdrawalManager.announceAndReduce(hyperliquidTestPool, 0, _emptyIds(), _emptyIds());
  }

  function test_revert_announce_invalidPool() public {
    address notAPool = makeAddr("notAPool");
    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__InvalidPool.selector);
    withdrawalManager.announceAndReduce(notAPool, 1e18, _emptyIds(), _emptyIds());
  }

  /// @notice Announcing on a valid factory pool that does not support the CoreWriter asset (no
  ///         Hyperliquid integration) reverts up front, before any pool tokens are pulled.
  function test_revert_announce_poolHasNoHLIntegration() public {
    address nonHlPool = _createNonHlPool();
    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__PoolHasNoHLIntegration.selector);
    withdrawalManager.announceAndReduce(nonHlPool, 1e18, _emptyIds(), _emptyIds());
  }

  /// @notice A 100% withdrawal (tokenAmount == totalSupply) is unsupported: `_getPortion` reverts
  ///         with FullWithdrawalNotSupported. The manager is the sole holder (only the setup seed
  ///         deposit exists), so they can attempt to withdraw the entire supply.
  function test_revert_announce_fullWithdrawalNotSupported() public {
    uint256 supply = IPoolLogic(hyperliquidTestPool).totalSupply();
    uint256 managerShares = IPoolLogic(hyperliquidTestPool).balanceOf(manager);
    assertEq(managerShares, supply, "manager is sole holder");

    // Clear the setup deposit's exit cooldown so the pool tokens are transferrable.
    skip(6 minutes);
    vm.prank(manager);
    IERC20(hyperliquidTestPool).approve(address(withdrawalManager), managerShares);
    vm.prank(manager);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__FullWithdrawalNotSupported.selector);
    withdrawalManager.announceAndReduce(hyperliquidTestPool, managerShares, _emptyIds(), _emptyIds());
  }

  /// @notice When the reduce branch runs, passing a perp id the pool holds no position in reverts
  ///         with NoPositionForAsset. A real perp (MOODENG) is open and named too, so the coverage
  ///         check passes, but the extra supplied id (BTC, index 0) has no position to reduce.
  function test_revert_announce_noPositionForAsset() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    assertGt(_openPerpLong(), 0, "perp long opened");

    uint32 unheldPerp = 0; // BTC: a valid perp index the pool holds no position in.
    // Name the held MOODENG perp (satisfies the coverage check) plus the unheld BTC (ascending order).
    uint32[] memory perpIds = new uint32[](2);
    perpIds[0] = unheldPerp;
    perpIds[1] = _PERP_INDEX;
    _announceExpectRevert(
      shares / 4,
      perpIds,
      _emptyIds(),
      abi.encodeWithSelector(
        HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__NoPositionForAsset.selector,
        unheldPerp
      )
    );
  }

  /// @notice Duplicate perp ids are rejected up front. Without the strict-ascending check a repeated
  ///         id would queue a second full-size reduce order — each sized off the same stale pre-block
  ///         position — so a small withdrawal could stack reduce-only orders toward a full unwind of
  ///         the perp. announce reverts with UnsortedAssetIds before any order is placed.
  function test_revert_announce_duplicatePerpIds() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    assertGt(_openPerpLong(), 0, "perp long opened");

    uint32[] memory dupPerpIds = new uint32[](2);
    dupPerpIds[0] = _PERP_INDEX;
    dupPerpIds[1] = _PERP_INDEX;

    _announceExpectRevert(
      shares / 4,
      dupPerpIds,
      _emptyIds(),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__UnsortedAssetIds.selector)
    );
  }

  /// @notice A core perp named twice — once by its plain index, once by its `100_000 + index` spelling
  ///         — is rejected. Both spellings resolve to (dex 0, perp index), so the coverage check would
  ///         count that one position's notional TWICE and let an equally-open co-resident perp be
  ///         omitted entirely, while the bridge still pulls the withdrawal's share of the shared
  ///         cross-margin equity — raising leverage for the holders who remain.
  /// @dev Asset ids 100_000..109_999 are never valid: dex 0 IS the core perp dex and its perps are
  ///      addressed by their plain index (see `calculateAssetId` in
  ///      deployment/hyperevm/whitelistPerpAssets.ts), so real HIP-3 ids start at 110_000. Companion to
  ///      {test_revert_announce_multiPerp_missingOnePerpId}, which covers plainly omitting the second
  ///      perp; this covers faking its coverage.
  function test_revert_announce_aliasedCorePerpId() public {
    uint256 shares = _setupTwoCorePerps();

    // BTC named twice: plain index 0, then its HIP-3-range alias 100_000. Distinct and ascending, so
    // the strictly-ascending check cannot catch it.
    uint32 aliasedBtc = 100_000 + _PERP_INDEX_BTC;
    uint32[] memory aliasedPerpIds = new uint32[](2);
    aliasedPerpIds[0] = _PERP_INDEX_BTC;
    aliasedPerpIds[1] = aliasedBtc;

    _announceExpectRevert(
      shares / 4,
      aliasedPerpIds,
      _emptyIds(),
      abi.encodeWithSelector(
        HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__NoPositionForAsset.selector,
        aliasedBtc
      )
    );
  }

  /// @notice Duplicate spot ids are rejected the same way: a repeat would queue a second full-size
  ///         sell order and double-count the spot value in the stored ids at bridge time.
  function test_revert_announce_duplicateSpotIds() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    uint32 xaut0AssetId = _buyXaut0(uint64(1e8)); // 1 XAUT0

    uint32[] memory dupSpotIds = new uint32[](2);
    dupSpotIds[0] = xaut0AssetId;
    dupSpotIds[1] = xaut0AssetId;

    _announceExpectRevert(
      shares / 4,
      _emptyIds(),
      dupSpotIds,
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__UnsortedAssetIds.selector)
    );
  }

  /// @notice Two DISTINCT spot pair ids that share one base token are rejected. XAUT0 trades in pair
  ///         182 (/USDC) and pair 209 (/USDT0); both resolve to the same XAUT0 Core balance, and the
  ///         sell is sized off that balance — so each id would queue its own FULL-SIZE sell, selling
  ///         ~2x the withdrawer's share of a position the remaining holders keep, and would also count
  ///         that balance twice when sizing the bridge.
  /// @dev Strictly-ascending pair ids cannot catch this (the ids differ), so the de-dup has to key on
  ///      the base token — the resource the sell actually consumes. Checked before any value is read or
  ///      order placed, so this reverts regardless of what else validates the pair.
  function test_revert_announce_duplicateSpotBaseTokens() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    uint32 xaut0AssetId = _buyXaut0(uint64(1e8)); // 1 XAUT0

    // Distinct, ascending pair ids — but the same base token.
    uint32[] memory sharedBaseSpotIds = new uint32[](2);
    sharedBaseSpotIds[0] = xaut0AssetId; // 10_182 (XAUT0/USDC)
    sharedBaseSpotIds[1] = 10_000 + uint32(HyperEVMConfig.XAUT0_ALT_SPOT_INDEX); // 10_209 (XAUT0/USDT0)
    assertLt(sharedBaseSpotIds[0], sharedBaseSpotIds[1], "spot ids strictly ascending");
    assertEq(
      spotInfo(HyperEVMConfig.XAUT0_ALT_SPOT_INDEX).tokens[0],
      HyperEVMConfig.XAUT0_TOKEN_INDEX,
      "alt pair shares the XAUT0 base token"
    );

    _announceExpectRevert(
      shares / 4,
      _emptyIds(),
      sharedBaseSpotIds,
      abi.encodeWithSelector(
        HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__DuplicateSpotBaseToken.selector,
        HyperEVMConfig.XAUT0_TOKEN_INDEX
      )
    );
  }

  /// @notice Distinct but non-ascending (descending) ids are also rejected: strict ascending order
  ///         is what enforces the uniqueness invariant in O(n) without extra storage.
  function test_revert_announce_unsortedPerpIds() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    // Two distinct but descending ids (10 then 0): unique, yet not strictly ascending.
    uint32[] memory descPerpIds = new uint32[](2);
    descPerpIds[0] = 10;
    descPerpIds[1] = 0;

    _announceExpectRevert(
      shares / 4,
      descPerpIds,
      _emptyIds(),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__UnsortedAssetIds.selector)
    );
  }

  function test_revert_announce_alreadyPending() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    uint256 withdrawShares = shares / 4;
    _announce(investor, withdrawShares, _emptyIds(), _emptyIds());

    vm.prank(investor);
    IERC20(hyperliquidTestPool).approve(address(withdrawalManager), withdrawShares);
    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__WithdrawalAlreadyPending.selector);
    withdrawalManager.announceAndReduce(hyperliquidTestPool, withdrawShares, _emptyIds(), _emptyIds());
  }

  function test_revert_bridge_invalidState_whenNotAnnounced() public {
    vm.prank(investor);
    vm.expectRevert(
      abi.encodeWithSelector(
        HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__InvalidState.selector,
        IHyperliquidWithdrawalManager.WithdrawalState.NONE,
        IHyperliquidWithdrawalManager.WithdrawalState.REDUCED
      )
    );
    withdrawalManager.bridge(hyperliquidTestPool);
  }

  function test_revert_bridge_tooEarly_sameBlockAsAnnounce() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    _announce(investor, shares / 4, _emptyIds(), _emptyIds());

    // No block advance between announce and bridge.
    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__TooEarly.selector);
    withdrawalManager.bridge(hyperliquidTestPool);
  }

  function test_revert_settle_invalidState_whenNotBridged() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    _announce(investor, shares / 4, _emptyIds(), _emptyIds());

    vm.prank(investor);
    vm.expectRevert(
      abi.encodeWithSelector(
        HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__InvalidState.selector,
        IHyperliquidWithdrawalManager.WithdrawalState.REDUCED,
        IHyperliquidWithdrawalManager.WithdrawalState.BRIDGED
      )
    );
    withdrawalManager.settle(hyperliquidTestPool);
  }

  function test_revert_announce_noBridgeNeeded_whenAllUsdcOnEvm() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    // All USDC stays on EVM; nothing is sent to Core, so the HL position value (and bridge) is 0.
    _announceExpectRevert(
      shares / 4,
      _emptyIds(),
      _emptyIds(),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__NoBridgeNeeded.selector)
    );
  }

  /// @notice settle() must wait at least one block after bridge(): the bridged USDC only lands on
  ///         EVM in the following Core block, so settling in the same block would draw against
  ///         stale liquidity. The WM rejects this with TooEarly.
  function test_revert_settle_tooEarly_sameBlockAsBridge() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    _announce(investor, shares / 4, _emptyIds(), _emptyIds());
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);

    // No block advance between bridge and settle.
    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__TooEarly.selector);
    withdrawalManager.settle(hyperliquidTestPool);
  }

  /// @notice If the pool holds a dominant spot position and announceAndReduce omits its asset id,
  ///         the position is never sold. The XAUT0 is paid out in USDC (not as the XAUT0 token itself), but the WM
  ///         only bridges USDC for the Hyperliquid *position* value, so the un-sold XAUT0 starves
  ///         the pool of the USDC the position guard needs at settle, reverting. The withdrawer must
  ///         include the spot id (to sell it) for the withdrawal to settle.
  function test_revert_settle_missingSpotId() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    // Move ALL USDC to Core spot so there is no spare EVM USDC to cover the un-sold position.
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // Buy a dominant 5 XAUT0 spot position so the un-sold position starves the pool of the USDC
    // liquidity the position guard needs at settle.
    _buyXaut0(uint64(5e8));

    // Announce WITHOUT the XAUT0 spot id: the position is not reduced/sold. The un-sold XAUT0 was
    // not bridged for, so the pool can't satisfy the full withdrawal and the position guard's
    // liquidity check (OutsidePositionWithdrawalHelper._calculateWithdrawBalance) reverts at settle.
    _announceBridgeExpectSettleRevert(shares / 4, _emptyIds(), _emptyIds(), bytes("not enough available balance_1"));
  }

  /// @notice Pool holds both a perp long and a spot (XAUT0) position, but announce omits BOTH ids.
  ///         The WM refuses up front: a reduce-requiring withdrawal that leaves the perp un-reduced
  ///         would let the bridge's margin pull over-drain it, so announce reverts.
  function test_revert_announce_perpAndSpot_missingBothIds() public {
    (uint256 withdrawShares, , ) = _setupPerpAndSpot();
    _announceExpectRevert(
      withdrawShares,
      _emptyIds(),
      _emptyIds(),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__UnreducedPerpPosition.selector)
    );
  }

  /// @notice Perp + spot open, but only the spot id is provided: the perp id is still missing, so
  ///         the WM rejects the announce before any reduction or bridge.
  function test_revert_announce_perpAndSpot_missingPerpId() public {
    (uint256 withdrawShares, , uint32 xaut0AssetId) = _setupPerpAndSpot();
    _announceExpectRevert(
      withdrawShares,
      _emptyIds(),
      _ids(xaut0AssetId),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__UnreducedPerpPosition.selector)
    );
  }

  /// @notice Perp + spot open, but only the perp id is provided: the perp is reduced (so it stays
  ///         healthy and valuable) yet the dominant XAUT0 is never sold, so there is no USDC for the
  ///         spot payout and settle reverts cleanly with the position guard's liquidity check.
  /// @dev Uses a small, well-collateralized perp and a dominant spot leg so the spot starvation —
  ///      not perp valuation — is what fails settle.
  function test_revert_settle_perpAndSpot_missingSpotId() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    _buyXaut0(uint64(5e8)); // dominant 5 XAUT0
    assertGt(_openPerpLong(), 0, "perp long opened");

    _announceBridgeExpectSettleRevert(
      shares / 4,
      _ids(_PERP_INDEX),
      _emptyIds(),
      bytes("not enough available balance_1")
    );
  }

  /// @notice Only a perp is open and its id is omitted: the reduce branch runs but the perp would be
  ///         left un-reduced, so the WM rejects the announce up front (regardless of the perp's
  ///         leverage), preventing the bridge from over-draining it.
  function test_revert_announce_perpOnly_missingPerpId() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    assertGt(_openPerpLong(), 0, "perp long opened");

    _announceExpectRevert(
      shares / 4,
      _emptyIds(),
      _emptyIds(),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__UnreducedPerpPosition.selector)
    );
  }

  /// @notice Only a perp is open, the perp id is omitted, but a spot id is also passed. The missing
  ///         perp id is rejected up front (before the spot is even evaluated), so the announce
  ///         reverts with UnreducedPerpPosition rather than NoSpotBalanceForAsset.
  function test_revert_announce_perpOnly_missingPerpIdWithSpotId() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    assertGt(_openPerpLong(), 0, "perp long opened");

    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);
    _announceExpectRevert(
      shares / 4,
      _emptyIds(),
      _ids(xaut0AssetId),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__UnreducedPerpPosition.selector)
    );
  }

  /// @notice Only a perp is open and the caller passes the valid perp id PLUS a bogus spot id. The
  ///         perp id satisfies the up-front check, the perp is reduced, then selling a spot with no
  ///         balance reverts at announce with NoSpotBalanceForAsset. A spurious spot id therefore
  ///         breaks an otherwise-valid withdrawal.
  function test_revert_announce_perpOnly_bothIdsWithoutSpotPosition() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    assertGt(_openPerpLong(), 0, "perp long opened");

    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);
    _announceExpectRevert(
      shares / 4,
      _ids(_PERP_INDEX),
      _ids(xaut0AssetId),
      abi.encodeWithSelector(
        HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__NoSpotBalanceForAsset.selector,
        xaut0AssetId
      )
    );
  }

  /// @notice Only a (dominant) spot is open, but the caller passes a perp id for a position that
  ///         doesn't exist.
  /// @dev Core already holds enough free USDC to cover the HL *position* bridge (XAUT0 is excluded
  ///      from that value), so the reduce branch is skipped entirely and the bogus perp id is never
  ///      validated — announce does NOT revert. The XAUT0 is still never sold, so settle reverts
  ///      exactly like {test_revert_settle_missingSpotId}: the irrelevant perp id is a no-op.
  function test_revert_settle_spotOnly_irrelevantPerpIdIgnored() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    _buyXaut0(uint64(5e8)); // dominant 5 XAUT0

    _announceBridgeExpectSettleRevert(
      shares / 4,
      _ids(_PERP_INDEX),
      _emptyIds(),
      bytes("not enough available balance_1")
    );
  }

  /// @notice Happy path: only a dominant spot position is open (no perp), and the caller passes the
  ///         correct spot id with empty perp ids.
  function test_withdraw_core_spot_only__spot_only_dominant_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    uint32 xaut0AssetId = _buyXaut0(uint64(5e8)); // dominant 5 XAUT0

    uint256 withdrawShares = shares / 4;
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 fundValueStart = _getTotalFundValue();

    _announce(investor, withdrawShares, _emptyIds(), _ids(xaut0AssetId));
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");

    // Price per share must stay stable and fund value must only drop by the payout.
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0001e18,
      "tokenPrice ~ after settle"
    ); // 0.01% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0001e18, "fundValue dropped by payout"); // 0.01% max relative delta
  }

  /// @notice Vault is ~100% in a single spot asset (HYPE) and the user withdraws 60% of their shares
  ///         (portion ~0.4 of supply) through the full WM lifecycle (announce -> bridge -> settle).
  ///         The remaining vault must keep ~the same composition (still ~100% HYPE) and ~the same
  ///         price per share.
  /// @dev Regression guard for the spot-sizing fix. The WM sells the HYPE position proportionally to
  ///      the withdrawal (raw portion plus a small slippage buffer) and bridges the proportional
  ///      share of Core value, instead of grossing the sell/bridge up by `1/(1-portion)`. The old
  ///      gross-up sized the sell at `value * portion/(1-portion)` (~1.67x here), so reduce-only
  ///      liquidated the ENTIRE position and the grossed-up Core->EVM spot-send over-requested,
  ///      reverting settle ("not enough available balance_0"); even had it settled, the vault would
  ///      have flipped from ~100% HYPE to ~100% USDC. Post-fix the position is only partially sold,
  ///      preserving composition and price per share. Price per share still drifts by
  ///      ~`portion * spot-sell slippage` on the liquidated leg (a single large single-asset exit).
  function test_withdraw_core_spot_only__spot_only_hype_60pct() public {
    _enableHypeSpotAsset();

    uint256 shares = _depositAndCooldown(20_000e6);

    // Park all USDC on Core spot, then convert ~all of it into HYPE so the pool is ~100% HYPE with
    // negligible free Core USDC (forcing the reduce/sell branch during announce). Size the buy from
    // the available Core USDC (HYPE is valued at $40) and leave a ~1% headroom for the order's slippage.
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    uint64 hypeSizeE8 = uint64((_coreSpotUsdc() * 1e8 * 99) / (40e6 * 100));
    uint32 hypeAssetId = _buyHype(hypeSizeE8);

    assertLt(_coreSpotUsdc(), 1_000e6, "pool is ~100% HYPE: almost no free Core USDC left");

    // Composition before: fraction of total fund value held in HYPE (~1.0 == 100% HYPE).
    uint256 hypeFractionBefore = _hypeValueFraction();
    assertGt(hypeFractionBefore, 0.95e18, "vault starts ~100% HYPE");

    // Withdraw 60% of the investor's shares through the WM.
    uint256 withdrawShares = (shares * 60) / 100;
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();

    _announce(investor, withdrawShares, _emptyIds(), _ids(hypeAssetId));
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    // A proportional withdrawal should leave the remaining vault with ~the same composition: still
    // ~100% HYPE, and ~the same price per share.
    assertApproxEqRel(_hypeValueFraction(), hypeFractionBefore, 0.05e18, "vault composition (HYPE fraction) preserved");
    // Price per share drifts only by the spot-sell slippage on the liquidated leg (~portion * fill
    // slippage); for a 40%-of-supply exit from a single-asset vault.
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0002e18,
      "tokenPrice ~ after settle"
    );
  }

  /// @notice A withdrawal above 50% of supply settles. The spot sells only the proportional portion,
  ///         so remaining holders keep their share of the position; the bridge target exceeds the Core
  ///         balance (capped to bridge everything movable) and settle's gross-up funds the payout.
  function test_withdraw_core_spot_only__spot_only_aboveHalfSupply_bridgesAndSettles() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    uint32 xaut0AssetId = _buyXaut0(uint64(9e8)); // dominant 9 XAUT0

    // Investor holds ~2/3 of supply (the setup seeds the rest); 90% of their shares puts the
    // withdrawal portion at ~60% of supply.
    uint256 withdrawShares = (shares * 9) / 10;
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 fundValueStart = _getTotalFundValue();

    uint256 spotBefore = PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total;
    uint256 poolPortion = (withdrawShares * 1e18) / IERC20(hyperliquidTestPool).totalSupply();

    _announce(investor, withdrawShares, _emptyIds(), _ids(xaut0AssetId));
    CoreSimulatorLib.nextBlock();

    // The sell takes only the proportional fraction; remaining holders keep their spot share.
    assertApproxEqRel(
      PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      (spotBefore * (1e18 - poolPortion)) / 1e18,
      0.05e18,
      "spot reduced proportionally"
    );

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared and shares released from the WM.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(pending.amount, 0, "amount cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");

    // Price per share must stay roughly stable and fund value must only drop by the payout.
    // Liquidating the entire spot position (~84% of the pool) costs proportionally more
    // slippage/fees than the sliver-sized withdrawals above, hence the looser 0.1% tolerance.
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.001e18,
      "tokenPrice ~ after settle"
    ); // 0.1% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.001e18, "fundValue dropped by payout"); // 0.1% max relative delta
  }

  /// @dev Fraction (WAD) of the pool's total fund value currently held in HYPE.
  function _hypeValueFraction() internal view returns (uint256) {
    uint256 total = IPoolManagerLogic(hyperliquidTestPoolManagerLogic).totalFundValue();
    if (total == 0) return 0;
    uint256 hypeValue = IPoolManagerLogic(hyperliquidTestPoolManagerLogic).assetValue(
      HyperEVMConfig.HYPE_SYSTEM_ADDRESS
    );
    return (hypeValue * 1e18) / total;
  }

  function test_revert_cancel_noPendingWithdrawal() public {
    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__NoPendingWithdrawal.selector);
    withdrawalManager.cancel(hyperliquidTestPool);
  }

  function test_revert_cancel_timeoutNotReached() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    _announce(investor, shares / 4, _emptyIds(), _emptyIds());

    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__TimeoutNotReached.selector);
    withdrawalManager.cancel(hyperliquidTestPool);
  }

  function test_cancel_returnsSharesAfterTimeout() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    uint256 withdrawShares = shares / 4;
    uint256 investorSharesBefore = IPoolLogic(hyperliquidTestPool).balanceOf(investor);
    _announce(investor, withdrawShares, _emptyIds(), _emptyIds());

    assertEq(
      IPoolLogic(hyperliquidTestPool).balanceOf(investor),
      investorSharesBefore - withdrawShares,
      "shares locked in WM"
    );

    skip(HyperliquidWithdrawalManager(address(withdrawalManager)).WITHDRAWAL_TIMEOUT() + 1);

    vm.prank(investor);
    withdrawalManager.cancel(hyperliquidTestPool);

    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(investor), investorSharesBefore, "shares returned after cancel");
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(pending.amount, 0, "pending cleared");
  }

  /////////////////////////////////////////////
  //         Phase 3: Anti-grief             //
  /////////////////////////////////////////////

  /// @notice When the pool already holds enough EVM USDC, the position bridge deficit is zero, so
  ///         announceAndReduce fails fast with NoBridgeNeeded — the user can withdraw directly
  ///         rather than route a no-op through the WM. Half the pool USDC is kept on EVM and the
  ///         withdrawal is small, so EVM USDC comfortably covers the bridge amount.
  function test_revert_announce_noBridgeNeeded_whenEvmUsdcSufficient() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    // Keep half of the pool USDC on EVM as withdrawal liquidity; move the rest to Core.
    _bridgeAndProcess(_getPoolUSDCBalance() / 2, HLConstants.SPOT_DEX);

    // Small withdrawal: bridgeAmount (hlValue * portion * 1.01) stays below the EVM USDC balance,
    // so the effective bridge deficit is zero and the announce reverts.
    _announceExpectRevert(
      shares / 40,
      _emptyIds(),
      _emptyIds(),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__NoBridgeNeeded.selector)
    );
  }

  /// @notice Anti-grief: a depositor cannot repeatedly shrink positions via announce -> cancel ->
  ///         announce. The first cycle reduces the perp and bridges the freed USDC to the pool's EVM
  ///         balance; cancelling (instead of settling) leaves that USDC idle in the pool. The second
  ///         announce then sees enough EVM USDC to cover the bridge, so it fails fast with
  ///         NoBridgeNeeded and the perp is left untouched.
  /// @dev This protects against trade-slippage griefing: the gate compares EVM+Core USDC against the
  ///      bridge target, and the already-bridged USDC makes the deficit zero, so the announce is
  ///      rejected before any further reduce-only order (and its slippage) is placed.
  function test_antiGrief_secondAnnounceDoesNotReducePerpAgain_afterCancel() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    int64 sziBefore = _openPerpLong();
    assertGt(sziBefore, 0, "perp long opened");

    uint256 withdrawShares = shares / 4;

    // First cycle: announce reduces the perp, then bridge moves the freed USDC to the pool on EVM.
    _announce(investor, withdrawShares, _ids(_PERP_INDEX), _emptyIds());
    CoreSimulatorLib.nextBlock();

    int64 sziAfterFirst = position(hyperliquidTestPool, _PERP_INDEX).szi;
    assertLt(sziAfterFirst, sziBefore, "first announce reduced perp");

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();
    assertGt(IERC20(usdc).balanceOf(hyperliquidTestPool), 0, "freed USDC bridged to pool EVM balance");

    // Cancel after the timeout: shares return to the investor, but the bridged USDC stays idle in
    // the pool as withdrawal liquidity.
    skip(HyperliquidWithdrawalManager(address(withdrawalManager)).WITHDRAWAL_TIMEOUT() + 1);
    vm.prank(investor);
    withdrawalManager.cancel(hyperliquidTestPool);

    // Second announce with the same id now fails fast: the idle EVM USDC already covers the bridge
    _announceExpectRevert(
      withdrawShares,
      _ids(_PERP_INDEX),
      _emptyIds(),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__NoBridgeNeeded.selector)
    );

    assertEq(
      position(hyperliquidTestPool, _PERP_INDEX).szi,
      sziAfterFirst,
      "second announce did not reduce the perp again"
    );
  }

  /// @notice Anti-grief (perp + spot variant): the first cycle reduces BOTH a perp and a spot leg
  ///         and bridges the freed USDC to the pool; after cancelling and re-announcing with the
  ///         same ids, the idle EVM USDC covers the bridge so the announce fails fast with
  ///         NoBridgeNeeded and neither position is touched again.
  function test_antiGrief_secondAnnounceDoesNotReducePerpOrSpotAgain_afterCancel() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    // Park all USDC on Core, then a 0.5 XAUT0 spot leg (large enough for the 1/8 sell to clear the
    // lot grid) + a perp long so the perp soaks up the free USDC and the first announce must reduce
    // BOTH legs (mirrors test_withdraw_core_spot_core_perp__perp_and_spot).
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 xaut0Limit = normalizedPrice + ((normalizedPrice * 1) / 100);
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);
    bytes memory buyXaut0 = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, xaut0Limit, uint64(5e7), false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );
    _placeLimitOrder(buyXaut0);
    CoreSimulatorLib.nextBlock();

    int64 sziBefore = _openPerpLong();
    assertGt(sziBefore, 0, "perp long opened");
    uint64 spotBefore = spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total;
    assertGt(spotBefore, 0, "spot position opened");

    uint256 withdrawShares = shares / 8;

    // First cycle: announce reduces both legs, then bridge moves the freed USDC to the pool on EVM.
    _announce(investor, withdrawShares, _ids(_PERP_INDEX), _ids(xaut0AssetId));
    CoreSimulatorLib.nextBlock();

    int64 sziAfterFirst = position(hyperliquidTestPool, _PERP_INDEX).szi;
    uint64 spotAfterFirst = spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total;
    assertLt(sziAfterFirst, sziBefore, "first announce reduced perp");
    assertLt(spotAfterFirst, spotBefore, "first announce sold spot");

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();
    assertGt(IERC20(usdc).balanceOf(hyperliquidTestPool), 0, "freed USDC bridged to pool EVM balance");

    // Cancel after the timeout; the bridged USDC stays idle in the pool as withdrawal liquidity.
    skip(HyperliquidWithdrawalManager(address(withdrawalManager)).WITHDRAWAL_TIMEOUT() + 1);
    vm.prank(investor);
    withdrawalManager.cancel(hyperliquidTestPool);

    // Second announce with the same ids now fails fast: the idle EVM USDC already covers the bridge,
    // so the WM rejects it with NoBridgeNeeded instead of re-reducing either leg.
    _announceExpectRevert(
      withdrawShares,
      _ids(_PERP_INDEX),
      _ids(xaut0AssetId),
      abi.encodeWithSelector(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__NoBridgeNeeded.selector)
    );

    assertEq(
      position(hyperliquidTestPool, _PERP_INDEX).szi,
      sziAfterFirst,
      "second announce did not reduce the perp again"
    );
    assertEq(
      spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      spotAfterFirst,
      "second announce did not sell the spot again"
    );
  }

  /////////////////////////////////////////////
  //      Phase 4: Guard isPublic gating     //
  /////////////////////////////////////////////

  /// @notice A non-manager cannot drive a CoreWriter spot send directly: the guard only returns
  ///         isPublic=true while the WM is executing, so an idle-WM public call is rejected (dh24).
  function test_revert_execTransaction_spotSend_notPublic_whenWmIdle() public {
    bytes memory spotSendAction = abi.encodePacked(
      uint8(1),
      HyperliquidConstants.ACTION_SPOT_SEND,
      abi.encode(getSystemAddress(_USDC_TOKEN_INDEX), _USDC_TOKEN_INDEX, uint64(1e8))
    );
    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, spotSendAction);

    // anon is neither manager, trader nor owner; with the WM idle the action is not public.
    vm.prank(anon);
    vm.expectRevert(bytes("dh24"));
    IPoolLogic(hyperliquidTestPool).execTransaction(coreWriter, txData);
  }

  /// @notice The permissionless route to the same thing is closed by the same guard check: ANY
  ///         shareholder naming a non-USDC-quoted pair in a withdrawal has their announce reverted when
  ///         the WM tries to place the proportional sell. Without this, the caller did not even need to
  ///         finish the withdrawal — the NAV damage landed at announce and `cancel` returned their
  ///         shares.
  /// @dev Sizing: ~$28k of the ~$30k fund sits in XAUT0, so idle Core USDC cannot cover the exit and the
  ///      announce is forced onto the sell path (on the skip path no order is placed, so there would be
  ///      nothing for the guard to reject).
  function test_revert_announce_spotIdOnNonUsdcQuotedPair() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    _buyXaut0(uint64(10e8)); // 10 XAUT0 @ $2,800

    _announceExpectRevert(
      (shares * 20) / 100,
      _emptyIds(),
      _ids(10_000 + uint32(HyperEVMConfig.XAUT0_ALT_SPOT_INDEX)),
      bytes("spot pair not USDC quoted")
    );

    // Nothing was sold and no unvalued token entered the vault.
    assertEq(spotBalance(hyperliquidTestPool, uint64(HyperEVMConfig.XAUT0_TOKEN_INDEX)).total, 10e8, "XAUT0 intact");
    assertEq(spotBalance(hyperliquidTestPool, HyperEVMConfig.USDT0_TOKEN_INDEX).total, 0, "no USDT0 received");
  }

  /// @notice Only the owner can repoint the WM reference on the CoreWriter guard.
  function test_revert_setWithdrawalManager_notOwner() public {
    vm.prank(anon);
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, anon));
    hyperliquidCoreWriterContractGuard.setWithdrawalManager(makeAddr("newWm"));
  }

  /////////////////////////////////////////////
  //         Phase 5: Concurrency            //
  /////////////////////////////////////////////

  /// @notice Two concurrent withdrawers both omit the perp id. The reservation serializes them: the
  ///         first skips against the shared free-equity buffer and reserves it; the second no longer
  ///         sees enough free buffer, is forced onto the reduce path, and — omitting the perp id — is
  ///         rejected. So the shared perp is drained at most once and its leverage stays within the
  ///         single-withdrawer bound (<= 1x) instead of being over-drained above it.
  function test_concurrentWithdrawers_omittingPerpId_doNotOverDrainSharedPerp() public {
    _depositAndCooldown(investor, 50_000e6);
    _depositAndCooldown(investorB, 50_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // ~85% notional leaves ~15% margin-free equity — enough for exactly ONE withdrawal's skip.
    assertGt(_openPerpLong(2, 8500), 0, "perp long opened");

    uint256 leverageBefore = _perpLeverageWad();

    // Each user withdraws ~10% of supply: one skip fits the ~15% buffer, two do not.
    uint256 withdrawAmount = (IERC20(hyperliquidTestPool).totalSupply() * 10) / 100;

    bool acceptedA = _tryAnnounceWithoutPerpId(investor, withdrawAmount);
    bool acceptedB = _tryAnnounceWithoutPerpId(investorB, withdrawAmount);

    // First skip is accepted and reserves the buffer; the second no longer fits, so it's forced to
    // reduce and — omitting the perp id — is rejected before touching the shared perp.
    assertTrue(acceptedA, "first withdrawal should skip against the free buffer");
    assertFalse(acceptedB, "second concurrent skip must be rejected (buffer already reserved)");

    // Only the first withdrawal bridges. Its skip pulls margin-free equity, nudging leverage up but
    // keeping it within the single-withdrawer bound; the rejected second one never drains the perp.
    CoreSimulatorLib.nextBlock();
    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    uint256 leverageAfter = _perpLeverageWad();
    assertGt(leverageAfter, leverageBefore, "first skip pulled free equity, raising leverage");
    assertLe(leverageAfter, 1e18, "shared perp must not be over-drained above 1x");
  }

  /// @notice A reduce-path withdrawal frees margin between its reduce and its bridge — margin its
  ///         own bridge will pull. That freed margin must not look "free" to a concurrent skip-path
  ///         announce: without reserving the reduce path's pending bridge, a second withdrawer
  ///         skips against it, and when the first bridge later pulls, it digs into collateral
  ///         backing the still-open notional — remaining holders end up more leveraged than before
  ///         either withdrawal.
  function test_concurrent_skip_cannot_claim_margin_freed_for_pending_reduce() public {
    _depositAndCooldown(investor, 20_000e6);
    _depositAndCooldown(investorB, 20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // ~90% notional leaves ~10% free equity — not enough for A's bridge, so A must reduce.
    assertGt(_openPerpLong(2, 9_000), 0, "perp long opened");

    // A: 20% of supply => reduce path (names the perp); the fill frees ~20% of the margin.
    uint256 withdrawA = IERC20(hyperliquidTestPool).totalSupply() / 5;
    _announce(investor, withdrawA, _ids(_PERP_INDEX), _emptyIds());
    CoreSimulatorLib.nextBlock(); // A's reduce fills; A has not bridged yet.

    // B: 15% of supply with no perp id — only viable as a skip. The margin A's reduce freed is
    // earmarked for A's pending bridge and must not fund B's skip.
    uint256 withdrawB = (IERC20(hyperliquidTestPool).totalSupply() * 15) / 100;
    assertFalse(
      _tryAnnounceWithoutPerpId(investorB, withdrawB),
      "skip must not double-spend margin freed for the pending reduce-path bridge"
    );

    // A's own flow is unaffected: the bridge pulls the freed margin and the withdrawal settles.
    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();
    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "A settled");
  }

  /////////////////////////////////////////////
  //          Phase 6: HIP-3 dexes           //
  /////////////////////////////////////////////

  /// @notice Skip-path withdrawals must not touch a leveraged HIP-3 dex's margin. The announce
  ///         skipped the reduce because idle Core spot cash covers the bridge, so the HIP-3
  ///         position is still at full size — consolidating a share of its equity (as the reduce
  ///         path does) would only raise its leverage for the holders who remain. With spot
  ///         covering the whole send, the bridge must emit NO sendAsset action at all.
  /// @dev No leverage assertions here (unlike the perp happy paths): the pool holds no real perp,
  ///      and the HIP-3 account is a static mock, so its leverage cannot move by construction —
  ///      the absence of the action-13 payload IS the "margin untouched" assertion.
  function test_withdraw_hip3_skip_path_leaves_leveraged_dex_margin_untouched() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    // Park ALL pool USDC on Core spot: the withdrawal must bridge from Core, and the spot buffer
    // covers the bridge so the announce skips the reduce (no reduce ids => no coverage check).
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    assertEq(IERC20(usdc).balanceOf(hyperliquidTestPool), 0, "pool EVM USDC drained to core");

    // A leveraged HIP-3 account: equity $5k backing $10k open notional (2x), initial margin $1k.
    uint256 hlValueBefore = IAssetGuard(hyperliquidPositionGuard).getBalance(hyperliquidTestPool, address(0));
    _enableHip3Dex(_HIP3_DEX_ID);
    _mockHip3DexSummary({accountValue: 5_000e6, marginUsed: 1_000e6, ntlPos: 10_000e6});
    uint256 hlValue = IAssetGuard(hyperliquidPositionGuard).getBalance(hyperliquidTestPool, address(0));
    assertEq(hlValue - hlValueBefore, 5_000e6, "mocked HIP-3 equity visible to the position guard");

    uint256 withdrawShares = shares / 4;
    uint256 portion = withdrawShares.divWadDown(IERC20(hyperliquidTestPool).totalSupply());
    uint256 tokenPriceStart = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 fundValueStart = _getTotalFundValue();
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    // Mirror of _computeBridgeAmount + _getEffectiveBridgeAmount (EVM USDC is 0, so no credit).
    uint256 expectedBridge = hlValue.mulWadUp(portion);
    expectedBridge = expectedBridge + (expectedBridge * 100) / 10_000;

    _announce(investor, withdrawShares, _emptyIds(), _emptyIds());

    // The Core spot buffer covered the bridge, so the reduce was skipped and the bridge reserved.
    assertEq(
      HyperliquidWithdrawalManager(address(withdrawalManager)).reservedBridgeUsdc(hyperliquidTestPool),
      expectedBridge,
      "skip path reserved the effective bridge"
    );
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);

    // Spot covers the whole send: nothing may be pulled out of the leveraged HIP-3 dex.
    assertFalse(_anySendAssetActionEmitted(), "no consolidation from the un-reduced leveraged dex");
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    // Withdrawal cleared, reservation released, and the investor was paid.
    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(
      HyperliquidWithdrawalManager(address(withdrawalManager)).reservedBridgeUsdc(hyperliquidTestPool),
      0,
      "reservation released"
    );
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");

    uint256 received = IERC20(usdc).balanceOf(investor) - investorUsdcBefore;
    assertGt(received, 0, "investor received USDC");
    // No trading happened (skip path, static HIP-3 mock), so price per share holds and fund value
    // only drops by the payout (both include the mocked HIP-3 equity consistently).
    assertApproxEqRel(
      IPoolLogic(hyperliquidTestPool).tokenPrice(),
      tokenPriceStart,
      0.0005e18,
      "tokenPrice ~ after settle"
    ); // 0.05% max relative delta
    assertApproxEqRel(_getTotalFundValue(), fundValueStart - received * 1e12, 0.0005e18, "fundValue dropped by payout"); // 0.05% max relative delta
  }

  /// @notice Reduce-path variant mirroring the production failure shape: every Core account is
  ///         leveraged (a real core-dex perp plus a mocked leveraged HIP-3 perp), so the announce is
  ///         forced onto the reduce path and must name BOTH perps; it must queue a reduce-only IOC
  ///         order for the HIP-3 asset, and the bridge must still consolidate the HIP-3 dex's margin
  ///         — CAPPED at its transferable margin when the proportional target exceeds it.
  /// @dev Leverage is asserted through the reduce (as in the perp happy paths) but NOT after settle:
  ///      the simulator's sendAsset is a no-op, so the mocked HIP-3 dex never actually delivers its
  ///      consolidated share and the bridge's class transfer pulls that share from the real core-dex
  ///      margin instead — post-settle core leverage drifts up as a fixture artifact, not contract
  ///      behavior.
  function test_withdraw_hip3_reduce_path_emits_capped_consolidation() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // The real core-dex perp locks the unified account's margin (~110% notional), leaving no free
    // Core USDC, so the announce cannot skip the reduce.
    int64 sziBefore = _openPerpLong();
    assertGt(sziBefore, 0, "perp long opened");

    // HIP-3 account mirroring production xyz:GOLD: equity $5k, open notional $10k (2x), with a high
    // initial margin ($4.5k) so the transferable margin 5k - max(4.5k, 10k / 10) = $0.5k CAPS the
    // proportional consolidation target (portion * $5k) below.
    _enableHip3Dex(_HIP3_DEX_ID);
    _mockHip3DexSummary({accountValue: 5_000e6, marginUsed: 4_500e6, ntlPos: 10_000e6});
    // 2.5 units at oracle $4,000 (szDecimals 4 -> oraclePx is 10^(6-4)-scaled) = exactly the mocked
    // $10k ntlPos, so naming the perp passes the announce coverage check.
    _mockHip3PerpPosition({szi: 25_000, oraclePrice: 400_000, szDecimals: 4});

    uint256 withdrawShares = shares / 4;
    uint256 portion = withdrawShares.divWadDown(IERC20(hyperliquidTestPool).totalSupply());
    uint256 leverageBefore = _perpLeverageWad();
    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    // Both open perps must be named (strictly ascending): the core-dex perp and the HIP-3 asset.
    uint32[] memory perpIds = new uint32[](2);
    perpIds[0] = _PERP_INDEX;
    perpIds[1] = _HIP3_PERP_ASSET_ID;

    vm.prank(investor);
    IERC20(hyperliquidTestPool).approve(address(withdrawalManager), withdrawShares);
    vm.prank(investor);
    withdrawalManager.announceAndReduce(hyperliquidTestPool, withdrawShares, perpIds, _emptyIds());

    // The announce must queue a reduce-only IOC sell for the HIP-3 perp: `portion` of the 2.5-unit
    // position floored onto the 10^(8-4) lot grid, priced 1% below the $4,000 oracle on the
    // 10^7 tick grid (5 significant figures).
    uint64 expectedReduceSz = uint64((uint256(2.5e8).mulWadDown(portion) / 1e4) * 1e4);
    bytes memory expectedReduceOrder = abi.encodePacked(
      uint8(1),
      HyperliquidConstants.ACTION_LIMIT_ORDER,
      abi.encode(
        _HIP3_PERP_ASSET_ID,
        false,
        uint64(396_000_000_000),
        expectedReduceSz,
        true,
        uint8(OrderType.IOC),
        uint128(0)
      )
    );
    assertTrue(_rawActionEmitted(expectedReduceOrder), "HIP-3 reduce-only order queued");
    CoreSimulatorLib.nextBlock();

    // The core-dex reduce filled: the position shrank and, with the freed margin still in the perp
    // account until bridged, its leverage can only stay or drop (as in the single-perp happy path).
    // The HIP-3 legs stay static by construction (mocked reads), so only the core dex is asserted.
    int64 sziAfter = position(hyperliquidTestPool, _PERP_INDEX).szi;
    assertLt(sziAfter, sziBefore, "core perp position reduced");
    assertGt(sziAfter, 0, "position only partially reduced");
    assertLe(_perpLeverageWad(), leverageBefore, "core perp leverage not increased by reduce");

    // The bridge must consolidate the HIP-3 dex's margin, capped at its $0.5k transferable margin
    // (the proportional portion * $5k target exceeds it). Under the old equity-minus-notional cap
    // this action was skipped entirely and the withdrawal could never be funded.
    vm.expectEmit(true, false, false, true, coreWriter);
    emit RawAction(hyperliquidTestPool, _expectedConsolidationAction(500e6));
    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");
    assertGt(IERC20(usdc).balanceOf(investor) - investorUsdcBefore, 0, "investor received USDC");
  }

  /// @notice Skip-path deficit covered by the core perp dex's own idle cash: spot alone is short of
  ///         the send, but dex 0 holds free position-less USDC, so the bridge tops spot up from
  ///         dex 0 (action 7) and must still NOT pull anything out of the un-reduced leveraged
  ///         HIP-3 dex.
  function test_withdraw_hip3_skip_path_deficit_covered_by_core_dex_cash() public {
    uint256 shares = _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // Park most Core cash on the core perp dex (no position — pure idle margin) and keep a thin
    // spot buffer, so the bridge's send exceeds spot and the deficit must come from dex 0.
    bytes memory toPerpAction = abi.encodePacked(
      uint8(1),
      HLConstants.USD_CLASS_TRANSFER_ACTION,
      abi.encode(uint64(_coreSpotUsdc() - 2_000e6), true) // true = spot -> perp (dex 0)
    );
    _placeLimitOrder(toPerpAction);
    CoreSimulatorLib.nextBlock();

    // A leveraged HIP-3 account: still at full size (nothing reduces on the skip path).
    _enableHip3Dex(_HIP3_DEX_ID);
    _mockHip3DexSummary({accountValue: 5_000e6, marginUsed: 1_000e6, ntlPos: 10_000e6});

    uint256 investorUsdcBefore = IERC20(usdc).balanceOf(investor);

    // dex-0 free cash (~$28k) + spot ($2k) cover the bridge => the reduce is skipped.
    _announce(investor, shares / 4, _emptyIds(), _emptyIds());
    assertGt(
      HyperliquidWithdrawalManager(address(withdrawalManager)).reservedBridgeUsdc(hyperliquidTestPool),
      0,
      "skip path taken"
    );
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);

    // The deficit is fully covered by dex 0's own free cash: no HIP-3 consolidation allowed.
    assertFalse(_anySendAssetActionEmitted(), "no consolidation from the un-reduced leveraged dex");
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
    assertGt(IERC20(usdc).balanceOf(investor) - investorUsdcBefore, 0, "investor received USDC");
  }

  /// @notice Skip-path deficit funded by an idle HIP-3 dex: the core dex's margin is locked by a
  ///         real perp (free equity ~0) and spot is thin, but a HIP-3 dex holds idle position-less
  ///         cash — the announce counts it as free and skips the reduce. The bridge must
  ///         consolidate from that dex EXACTLY the spot deficit, not the withdrawer's proportional
  ///         share of its equity: with no reduce having happened, anything beyond what the send
  ///         needs would leave a dex for no reason.
  function test_withdraw_hip3_skip_path_consolidates_exact_deficit_from_idle_dex() public {
    _depositAndCooldown(20_000e6);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // Real core-dex perp locks the unified account's margin (~110% notional, free equity ~0),
    // leaving only the ~$50 spot buffer as free real cash.
    assertGt(_openPerpLong(), 0, "perp long opened");

    // Idle HIP-3 dex: $5k of position-less cash, all of it free for the announce's skip decision.
    _enableHip3Dex(_HIP3_DEX_ID);
    _mockHip3DexSummary({accountValue: 5_000e6, marginUsed: 0, ntlPos: 0});

    uint256 withdrawShares = IERC20(hyperliquidTestPool).totalSupply() / 10;
    uint256 portion = withdrawShares.divWadDown(IERC20(hyperliquidTestPool).totalSupply());

    // Mirror of the bridge sizing: effectiveBridge (no EVM credit) plus the 0.1 USDC gas reserve,
    // net of the current spot balance — the exact deficit that must be routed to dex 0.
    uint256 hlValue = IAssetGuard(hyperliquidPositionGuard).getBalance(hyperliquidTestPool, address(0));
    uint256 expectedBridge = hlValue.mulWadUp(portion);
    expectedBridge = expectedBridge + (expectedBridge * 100) / 10_000;
    uint256 expectedDeficit = expectedBridge + 1e5 - _coreSpotUsdc();

    _announce(investor, withdrawShares, _emptyIds(), _emptyIds());
    assertGt(
      HyperliquidWithdrawalManager(address(withdrawalManager)).reservedBridgeUsdc(hyperliquidTestPool),
      0,
      "skip path taken"
    );
    CoreSimulatorLib.nextBlock();

    vm.expectEmit(true, false, false, true, coreWriter);
    emit RawAction(hyperliquidTestPool, _expectedConsolidationAction(expectedDeficit));
    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    IHyperliquidWithdrawalManager.PendingWithdrawal memory pending = withdrawalManager.pendingWithdrawals(
      investor,
      hyperliquidTestPool
    );
    assertEq(uint8(pending.state), uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE), "state cleared");
  }

  /// @notice The bridge must fail loudly when Core could not fund the perp->spot pull. The HIP-3
  ///         dex's transferable margin (~$1k of $500k equity, margin nearly exhausted) caps the
  ///         consolidation far below the pull, and dex 0 holds nothing — HyperCore would silently
  ///         drop the class transfer and then the spot send, "succeeding" on EVM while bridging
  ///         nothing and stranding the withdrawal in BRIDGED. The WM must revert the bridge with
  ///         InsufficientCoreUsdc instead, leaving the withdrawal cancellable.
  function test_revert_bridge_insufficientCoreUsdc_whenConsolidationCapped() public {
    uint256 shares = _depositAndCooldown(20_000e6);

    // All real cash stays on EVM; the pool's entire Core value is the mocked HIP-3 account whose
    // margin is nearly exhausted: transferable = 500k - max(499k, 1M / 10) = $1k.
    _enableHip3Dex(_HIP3_DEX_ID);
    _mockHip3DexSummary({accountValue: 500_000e6, marginUsed: 499_000e6, ntlPos: 1_000_000e6});
    // 250 units at oracle $4,000 = exactly the mocked $1M notional, for the announce coverage check.
    _mockHip3PerpPosition({szi: 2_500_000, oraclePrice: 400_000, szDecimals: 4});

    // No free Core USDC anywhere => reduce path; the HIP-3 perp must be named.
    uint256 withdrawShares = shares / 4;
    _announce(investor, withdrawShares, _ids(_HIP3_PERP_ASSET_ID), _emptyIds());
    CoreSimulatorLib.nextBlock();

    // The capped $1k consolidation plus an empty dex 0 cannot cover the pull: fail loudly.
    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__InsufficientCoreUsdc.selector);
    withdrawalManager.bridge(hyperliquidTestPool);

    // The withdrawal is not stranded: after the timeout the user recovers their pool tokens.
    uint256 investorSharesBefore = IERC20(hyperliquidTestPool).balanceOf(investor);
    skip(6 minutes);
    vm.prank(investor);
    withdrawalManager.cancel(hyperliquidTestPool);
    assertEq(
      IERC20(hyperliquidTestPool).balanceOf(investor),
      investorSharesBefore + withdrawShares,
      "pool tokens returned on cancel"
    );
  }

  /////////////////////////////////////////////
  //        Phase 7: Fair-share draws        //
  /////////////////////////////////////////////

  /// @notice A reduce-path withdrawal whose spot sell does not fill must NOT make up the shortfall
  ///         out of perp collateral. The announce places the sell 1% below the spot oracle; the book
  ///         moves further than that before Core processes the block, so the IOC frees no USDC.
  ///         The bridge's perp->spot pull is sized as "whatever the spot account is still short", so
  ///         without a cap it charges the perp wallet for the spot leg's share too — leaving the
  ///         position at full size on a fraction of its margin and silently raising leverage for
  ///         every holder who stayed, while the withdrawal itself settles normally. The bridge must
  ///         instead fail loudly, leaving the withdrawal cancellable and the perp untouched.
  function test_revert_bridge_unfilledSpotSell_doesNotDrainPerpMargin() public {
    _depositAndCooldown(20_000e6);

    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);

    // A spot leg large enough that its share of the bridge dwarfs the perp's own share: 5 XAUT0
    // (~$14k) against a ~$16k perp wallet. Everything left after the buy funds the perp at ~1.1x
    // notional, so free Core USDC is ~0 and the announce is forced onto the reduce path.
    uint32 xaut0AssetId = _buyXaut0(uint64(5e8));
    int64 sziBefore = _openPerpLong();
    assertGt(sziBefore, 0, "perp long opened");

    uint256 leverageBefore = _perpLeverageWad();
    uint256 withdrawShares = IERC20(hyperliquidTestPool).totalSupply() / 4;

    _announce(investor, withdrawShares, _ids(_PERP_INDEX), _ids(xaut0AssetId));

    // The sell was priced at oracle - 1%. Drop XAUT0 5% before Core processes the block: the IOC is
    // no longer marketable, so it frees nothing — the ordinary thin-book / gapping-market case.
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), (xaut0Price * 95) / 100);
    CoreSimulatorLib.nextBlock();

    // The perp leg DID fill; only the spot leg under-delivered.
    assertLt(position(hyperliquidTestPool, _PERP_INDEX).szi, sziBefore, "perp position reduced");
    assertEq(
      PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      5e8,
      "spot sell did not fill"
    );
    uint256 leverageAfterReduce = _perpLeverageWad();

    // Without the cap the pull succeeds and drives leverage from 0.83x to 1.53x while the withdrawal
    // settles normally — the holders who stayed absorb it silently.
    vm.prank(investor);
    vm.expectRevert(HyperliquidWithdrawalManager.HyperliquidWithdrawalManager__UnfundedReduceLeg.selector);
    withdrawalManager.bridge(hyperliquidTestPool);

    // Nothing was pulled: the perp keeps the margin backing its still-open notional, so the holders
    // who stayed keep the leverage the reduce left them with.
    assertEq(_perpLeverageWad(), leverageAfterReduce, "perp leverage untouched by the refused bridge");
    assertLe(leverageAfterReduce, leverageBefore, "reduce alone never raises leverage");

    // The withdrawal is not stranded: after the timeout the user recovers their pool tokens.
    uint256 investorSharesBefore = IERC20(hyperliquidTestPool).balanceOf(investor);
    skip(6 minutes);
    vm.prank(investor);
    withdrawalManager.cancel(hyperliquidTestPool);
    assertEq(
      IERC20(hyperliquidTestPool).balanceOf(investor),
      investorSharesBefore + withdrawShares,
      "pool tokens returned on cancel"
    );
  }

  /// @notice USDC a pending withdrawal has already bridged is sitting in the pool on EVM but is
  ///         earmarked for that withdrawal's settle. A second announce must not credit it as idle
  ///         pool liquidity: doing so sizes the second bridge too small — here to exactly zero, so
  ///         the announce reverts `NoBridgeNeeded` and sends the user to withdraw directly, which
  ///         spends the first withdrawal's bridged USDC and leaves it unable to settle. Both
  ///         withdrawals must be able to run their own cycle end to end.
  function test_secondAnnounce_ignoresUsdcBridgedForPendingWithdrawal() public {
    _depositAndCooldown(investor, 50_000e6);
    _depositAndCooldown(investorB, 50_000e6);

    // Park the pool's entire USDC balance on Core spot: any withdrawal must bridge from Core, and
    // idle EVM USDC can then only come from another withdrawal's bridge.
    _bridgeAndProcess(_getPoolUSDCBalance(), HLConstants.SPOT_DEX);
    assertEq(IERC20(usdc).balanceOf(hyperliquidTestPool), 0, "no idle EVM USDC to start");

    uint256 supply = IERC20(hyperliquidTestPool).totalSupply();
    // A withdraws 2% of supply, B ten times less: A's bridged USDC then dwarfs B's own requirement,
    // so crediting it as idle zeroes B's bridge outright.
    uint256 amountA = (supply * 200) / 10_000;
    uint256 amountB = (supply * 20) / 10_000;

    _announce(investor, amountA, _emptyIds(), _emptyIds());
    CoreSimulatorLib.nextBlock();
    vm.prank(investor);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    uint256 bridgedForA = IERC20(usdc).balanceOf(hyperliquidTestPool);
    assertGt(bridgedForA, 0, "A's bridged USDC is idle in the pool but owed to A's settle");

    // The crux: B's announce must size its own bridge as if A's USDC were not there.
    _announce(investorB, amountB, _emptyIds(), _emptyIds());
    CoreSimulatorLib.nextBlock();
    vm.prank(investorB);
    withdrawalManager.bridge(hyperliquidTestPool);
    CoreSimulatorLib.nextBlock();

    assertGt(IERC20(usdc).balanceOf(hyperliquidTestPool), bridgedForA, "B bridged its own share too");

    // Both settle. B goes first: settling A first would burn A's shares and grow B's portion beyond
    // what B bridged for, which is a separate limitation of concurrent settles.
    vm.prank(investorB);
    withdrawalManager.settle(hyperliquidTestPool);
    vm.prank(investor);
    withdrawalManager.settle(hyperliquidTestPool);

    assertEq(
      uint8(withdrawalManager.pendingWithdrawals(investorB, hyperliquidTestPool).state),
      uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE),
      "B settled"
    );
    assertEq(
      uint8(withdrawalManager.pendingWithdrawals(investor, hyperliquidTestPool).state),
      uint8(IHyperliquidWithdrawalManager.WithdrawalState.NONE),
      "A settled"
    );
    assertEq(IPoolLogic(hyperliquidTestPool).balanceOf(address(withdrawalManager)), 0, "WM holds no shares");
  }

  /// @dev Consumes the recorded logs and returns true if the CoreWriter emitted a RawAction from the
  ///      test pool with exactly `expectedAction` as payload. Safe to consume here: the simulator
  ///      only scans recorded logs for EVM->Core ERC20 transfers, which these transactions don't emit.
  function _rawActionEmitted(bytes memory expectedAction) internal view returns (bool found) {
    Vm.Log[] memory logs = vm.getRecordedLogs();
    bytes32 rawActionSig = keccak256("RawAction(address,bytes)");
    for (uint256 i; i < logs.length; ++i) {
      if (logs[i].emitter != coreWriter) continue;
      if (logs[i].topics[0] != rawActionSig) continue;
      if (logs[i].topics[1] != bytes32(uint256(uint160(hyperliquidTestPool)))) continue;
      if (keccak256(abi.decode(logs[i].data, (bytes))) == keccak256(expectedAction)) return true;
    }
  }

  /// @dev Consumes the recorded logs and returns true if the CoreWriter emitted any RawAction from
  ///      the test pool carrying a sendAsset (action 13) payload. Log consumption is safe here for
  ///      the same reason as {_rawActionEmitted}.
  function _anySendAssetActionEmitted() internal view returns (bool) {
    Vm.Log[] memory logs = vm.getRecordedLogs();
    bytes32 rawActionSig = keccak256("RawAction(address,bytes)");
    for (uint256 i; i < logs.length; ++i) {
      if (logs[i].emitter != coreWriter) continue;
      if (logs[i].topics[0] != rawActionSig) continue;
      if (logs[i].topics[1] != bytes32(uint256(uint160(hyperliquidTestPool)))) continue;
      bytes memory payload = abi.decode(logs[i].data, (bytes));
      if (payload.length < 4) continue;
      uint24 actionId = (uint24(uint8(payload[1])) << 16) |
        (uint24(uint8(payload[2])) << 8) |
        uint24(uint8(payload[3]));
      if (actionId == HyperliquidConstants.ACTION_SEND_ASSET) return true;
    }
    return false;
  }
}
