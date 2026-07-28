// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin/v5/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {HyperEVMSetup} from "test/integration/utils/foundry/chains/HyperEVMSetup.t.sol";
import {CoreSimulatorLib} from "test/integration/hyperevm/test-suite/hyperevm-lib/CoreSimulatorLib.sol";
import {HLConstants} from "test/integration/hyperevm/test-suite/hyperevm-lib/lib/HLConstants.sol";
import {PrecompileLib} from "test/integration/hyperevm/test-suite/hyperevm-lib/lib/PrecompileLib.sol";
import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";

import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
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
contract HyperliquidWithdrawalManagerTests is HyperEVMSetup, PrecompileHelper {
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

    // The reduce-only sell must have shrunk the long position.
    int64 sziAfter = position(hyperliquidTestPool, _PERP_INDEX).szi;
    assertLt(sziAfter, sziBefore, "perp position reduced");
    assertGt(sziAfter, 0, "position only partially reduced");
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
}
