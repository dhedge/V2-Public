//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/v5/contracts/utils/math/SafeCast.sol";
import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {PrecompileHelper} from "./PrecompileHelper.sol";
import {HyperliquidConstants} from "./HyperliquidConstants.sol";
import {FixedPointMathLib} from "../FixedPointMathLib.sol";

import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {IPoolFactory} from "../../interfaces/IPoolFactory.sol";
import {ICoreWriter} from "../../interfaces/hyperliquid/ICoreWriter.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IHasGuardInfo} from "../../interfaces/IHasGuardInfo.sol";
import {IAssetGuard} from "../../interfaces/guards/IAssetGuard.sol";
import {IHyperliquidWithdrawalManager} from "../../interfaces/hyperliquid/IHyperliquidWithdrawalManager.sol";
import {IHyperliquidCoreWriterContractGuard} from "../../interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";

/// @title HyperliquidWithdrawalManager
/// @notice Coordinates async user-driven withdrawals from pools with Hyperliquid perp positions.
///         Users lock pool tokens, the contract reduces positions proportionally, bridges USDC,
///         and settles the withdrawal.
/// @dev Relies on the CoreWriterContractGuard returning isPublic=true for withdrawal operations.
contract HyperliquidWithdrawalManager is IHyperliquidWithdrawalManager, OwnableUpgradeable, PrecompileHelper {
  using SafeERC20 for IERC20;
  using SafeCast for uint256;
  using FixedPointMathLib for uint256;

  /////////////////////////////////////////////
  //                Constants                //
  /////////////////////////////////////////////

  /// @notice Timeout after which a stuck withdrawal can be cancelled.
  uint256 public constant WITHDRAWAL_TIMEOUT = 5 minutes;

  /// @notice Slippage tolerance for reduce-only IOC orders placed during withdrawal.
  uint64 private constant _ORDER_SLIPPAGE = 0.01e18; // 1%

  /// @notice CoreWriter encodes all order prices and sizes as 8-decimal fixed point.
  uint256 private constant _CORE_ORDER_DECIMALS = 8;

  /// @notice HyperCore caps order prices at 5 significant figures (integer prices always allowed).
  uint256 private constant _MAX_PRICE_SIG_FIGS = 5;

  /// @notice HyperCore's price decimal-place cap is `MAX_DECIMALS - szDecimals`, where MAX_DECIMALS
  ///         is 6 for perps and 8 for spot. See tick-and-lot-size in the Hyperliquid API docs.
  uint256 private constant _PERP_MAX_PRICE_DECIMALS = 6;
  uint256 private constant _SPOT_MAX_PRICE_DECIMALS = 8;

  /// @notice Safety margin added to bridge amount to account for market-to-market movement
  ///         between bridge and settle (typically 1 block apart).
  uint256 private constant _BRIDGE_SAFETY_MARGIN_BPS = 100; // 1%

  uint256 private constant _BPS_DENOMINATOR = 10_000;

  /// @notice Max shortfall tolerated when checking that the supplied perp ids cover all open perp
  ///         notional, in BPS of a dex's aggregate `ntlPos`. Absorbs the oracle-vs-mark price basis
  ///         (named legs are oracle-priced, `ntlPos` is mark-priced) and lot rounding; a fully
  ///         omitted position falls short by its whole notional, far exceeding it.
  uint256 private constant _PERP_COVERAGE_TOLERANCE_BPS = 300; // 3%

  /// @notice USDC left in the Core spot account to pay the spot->EVM bridge fee (~200k gas, in HYPE
  ///         or USDC). Without it CoreWriter silently drops the bridge while the EVM tx succeeds.
  uint256 private constant _BRIDGE_GAS_RESERVE = 1e5; // 0.1 USDC (6 decimals)

  /// @dev Transient storage slot used to signal the guard that this contract is the caller.
  bytes32 private constant _EXECUTING_SLOT = keccak256("HyperliquidWithdrawalManager.executing");

  /////////////////////////////////////////////
  //             Custom Errors               //
  /////////////////////////////////////////////

  error HyperliquidWithdrawalManager__ZeroAmount();
  error HyperliquidWithdrawalManager__WithdrawalAlreadyPending();
  error HyperliquidWithdrawalManager__InvalidPool();
  error HyperliquidWithdrawalManager__PoolHasNoHLIntegration();
  error HyperliquidWithdrawalManager__InvalidState(WithdrawalState current, WithdrawalState expected);
  error HyperliquidWithdrawalManager__NoPositionForAsset(uint32 asset);
  error HyperliquidWithdrawalManager__NoSpotBalanceForAsset(uint32 asset);
  error HyperliquidWithdrawalManager__SpotAssetNotSupported(uint32 asset);
  error HyperliquidWithdrawalManager__NoPendingWithdrawal();
  error HyperliquidWithdrawalManager__TimeoutNotReached();
  error HyperliquidWithdrawalManager__NothingToBridge();
  error HyperliquidWithdrawalManager__NoSpotUsdcFreed();
  error HyperliquidWithdrawalManager__TooEarly();
  error HyperliquidWithdrawalManager__FullWithdrawalNotSupported();
  error HyperliquidWithdrawalManager__UnreducedPerpPosition();
  error HyperliquidWithdrawalManager__NoBridgeNeeded();
  error HyperliquidWithdrawalManager__UnsortedAssetIds();

  /////////////////////////////////////////////
  //                  State                  //
  /////////////////////////////////////////////

  /// @notice The PoolFactory contract.
  IPoolFactory public factory;

  /// @notice The CoreWriterContractGuard reference.
  IHyperliquidCoreWriterContractGuard public coreWriterGuard;

  /// @notice Pending withdrawals keyed by (user, pool).
  mapping(address user => mapping(address pool => PendingWithdrawal)) private _pendingWithdrawals;

  /// @notice Total pending token amounts per pool (sum across all users).
  mapping(address pool => uint256) public totalPendingTokens;

  /// @notice USDC (6 decimals) reserved against each pool's shared Core free-USDC buffer by pending
  ///         withdrawals that skipped the reduce. A concurrent announce sees the buffer net of this,
  ///         so two skips can't both draw the same free equity and over-drain the shared perp.
  mapping(address pool => uint256) public reservedBridgeUsdc;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /////////////////////////////////////////////
  //              Initialization             //
  /////////////////////////////////////////////

  function initialize(address admin, address _factory, address _coreWriterGuard) external initializer {
    __Ownable_init(admin);

    factory = IPoolFactory(_factory);
    _setCoreWriterGuard(_coreWriterGuard);
  }

  /////////////////////////////////////////////
  //            External Functions           //
  /////////////////////////////////////////////

  /// @notice Step 1: Lock pool tokens and place reduce-only IOC orders for specified positions.
  /// @dev Caller supplies perp/spot asset ids to reduce. Omitting an asset frees less USDC and
  ///      may make `settle` revert — `cancel` and retry with correct ids. Portion is
  ///      `tokenAmount / totalSupply` (conservative vs PoolLogic's post-fee-mint portion).
  /// @param pool The pool address to withdraw from.
  /// @param tokenAmount The amount of pool tokens to withdraw.
  /// @param perpAssetIds The Hyperliquid asset IDs of perp positions to reduce. Must be strictly ascending (unique).
  /// @param spotAssetIds The Hyperliquid spot pair IDs (10000+) of spot positions to sell. Must be strictly ascending (unique).
  function announceAndReduce(
    address pool,
    uint256 tokenAmount,
    uint32[] calldata perpAssetIds,
    uint32[] calldata spotAssetIds
  ) external {
    if (tokenAmount == 0) revert HyperliquidWithdrawalManager__ZeroAmount();
    if (_pendingWithdrawals[msg.sender][pool].amount != 0)
      revert HyperliquidWithdrawalManager__WithdrawalAlreadyPending();
    if (!factory.isPool(pool)) revert HyperliquidWithdrawalManager__InvalidPool();

    address poolManagerLogic = IPoolLogic(pool).poolManagerLogic();
    if (!IHasSupportedAsset(poolManagerLogic).isSupportedAsset(_CORE_WRITER)) {
      revert HyperliquidWithdrawalManager__PoolHasNoHLIntegration();
    }

    // Reject duplicate ids: a repeat would queue a second full-size reduce/sell order (each sized off
    // the same stale pre-block position), stacking toward a full unwind from a small withdrawal.
    _requireStrictlyAscending(perpAssetIds);
    _requireStrictlyAscending(spotAssetIds);

    uint256 portion = _getPortion(pool, tokenAmount);

    // USDC to bridge from Core (position value + spot settle demand), net of EVM USDC already idle.
    // If EVM already covers it, the reduce/bridge/settle cycle is a no-op — user can withdraw directly.
    uint256 bridgeAmount = _computeBridgeAmount(pool, portion, spotAssetIds);
    uint256 effectiveBridge = _getEffectiveBridgeAmount(pool, bridgeAmount, portion);
    if (effectiveBridge == 0) revert HyperliquidWithdrawalManager__NoBridgeNeeded();

    // Record withdrawal state.
    _pendingWithdrawals[msg.sender][pool] = PendingWithdrawal({
      amount: tokenAmount,
      announcedAt: block.timestamp,
      announcedBlock: block.number,
      bridgedBlock: 0,
      state: WithdrawalState.REDUCED,
      spotAssetIds: spotAssetIds,
      reservedBridge: 0
    });
    totalPendingTokens[pool] += tokenAmount;

    // Transfer pool tokens from user to this contract.
    // Reverts if exit cooldown hasn't expired (enforced by pool's _beforeTokenTransfer).
    IERC20(pool).safeTransferFrom(msg.sender, address(this), tokenAmount);

    // Skip the reduce only when the pool's free Core USDC — perp/HIP-3 margin-free equity plus idle
    // spot cash — net of what other pending skips already reserved, covers this bridge. Reserving it
    // (below) means a concurrent announce sees the buffer already spoken for and is forced onto the
    // reduce path instead of pulling the same shared perp margin a second time and over-draining it.
    uint256 freeUsdc = _getFreeCoreUsdc(pool);
    uint256 reserved = reservedBridgeUsdc[pool];
    uint256 availableUsdc = freeUsdc > reserved ? freeUsdc - reserved : 0;
    if (availableUsdc < effectiveBridge) {
      // The bridge pulls perp margin (action 7) regardless of reducing, shrinking the shared
      // cross-margin equity. Require the supplied perp ids to cover essentially all open perp
      // notional so an omitted position can't be left un-reduced and raise leverage for the holders
      // who remain after the withdrawal (this also rejects an empty array while a perp is open).
      _requirePerpIdsCoverOpenNotional(pool, perpAssetIds);

      // Reduce/sell proportionally to the withdrawal so the remaining vault keeps its composition.
      // Perps free USDC via an exact USD transfer at bridge time (action 7), not an order-book fill,
      // so the raw portion is exact; the reduce-only order's slippage only nudges realized PnL, which
      // the bridge's safety margin absorbs. Spot must be SOLD on the book to raise USDC, so the fill
      // slippage directly lowers the freed USDC; `_spotSellPortion` sells a touch extra so the
      // clamped pure-spot bridge can still cover the guard's oracle-priced settle demand. Orders are
      // reduce-only: any rounding only closes more, never flips, the position.
      _reducePositions(pool, portion, perpAssetIds);
      _sellSpotPositions(pool, _spotSellPortion(portion), spotAssetIds);
    } else {
      // Enough free buffer to bridge without reducing. Reserve this bridge against the shared buffer
      // so a concurrent withdrawal can't skip against the same equity; released at settle/cancel.
      reservedBridgeUsdc[pool] += effectiveBridge;
      _pendingWithdrawals[msg.sender][pool].reservedBridge = effectiveBridge;
    }

    emit WithdrawalAnnounced(msg.sender, pool, tokenAmount);
  }

  /// @notice Step 2: Transfer freed USDC from perp→spot and bridge spot→EVM.
  /// @dev Both actions (7 and 6) are queued in the same EVM transaction. CoreWriter processes
  ///      them in order on the Core side after the block. USDC arrives on EVM next block.
  /// @param pool The pool address.
  function bridge(address pool) external {
    PendingWithdrawal storage withdrawal = _pendingWithdrawals[msg.sender][pool];
    if (withdrawal.state != WithdrawalState.REDUCED) {
      revert HyperliquidWithdrawalManager__InvalidState(withdrawal.state, WithdrawalState.REDUCED);
    }
    if (block.number <= withdrawal.announcedBlock) revert HyperliquidWithdrawalManager__TooEarly();

    _bridgeUsdcToEvm(pool, withdrawal.amount, withdrawal.spotAssetIds);

    withdrawal.state = WithdrawalState.BRIDGED;
    withdrawal.bridgedBlock = block.number;

    emit WithdrawalBridged(msg.sender, pool);
  }

  /// @notice Step 3: Settle the withdrawal.
  /// @param pool The pool address.
  function settle(address pool) external {
    PendingWithdrawal storage withdrawal = _pendingWithdrawals[msg.sender][pool];
    if (withdrawal.state != WithdrawalState.BRIDGED) {
      revert HyperliquidWithdrawalManager__InvalidState(withdrawal.state, WithdrawalState.BRIDGED);
    }
    // Bridged USDC only lands on EVM in the block after `bridge`, so settling in the same block
    // would draw against stale liquidity. Require at least one block to pass.
    if (block.number <= withdrawal.bridgedBlock) revert HyperliquidWithdrawalManager__TooEarly();

    uint256 amount = withdrawal.amount;
    uint256 reserved = withdrawal.reservedBridge;

    // Clean up state before external call.
    totalPendingTokens[pool] -= amount;
    if (reserved != 0) reservedBridgeUsdc[pool] -= reserved;
    delete _pendingWithdrawals[msg.sender][pool];

    // Burns tokens from this contract, sends proportional assets to the user. Hyperliquid asset
    // guards don't require any complex withdraw data, so the no-data `withdrawTo` is sufficient.
    IPoolLogic(pool).withdrawTo(msg.sender, amount);

    emit WithdrawalSettled(msg.sender, pool, amount);
  }

  /// @notice Cancel a stuck withdrawal and return pool tokens to the user.
  /// @param pool The pool address.
  function cancel(address pool) external {
    PendingWithdrawal storage withdrawal = _pendingWithdrawals[msg.sender][pool];
    if (withdrawal.amount == 0) revert HyperliquidWithdrawalManager__NoPendingWithdrawal();
    // Cancel is the only recovery path when the flow can't complete (e.g. reduce/sell IOC orders
    // partially filled, so `settle`'s `withdrawTo` reverts on insufficient USDC). It must stay
    // available in BRIDGED state too. Bridged USDC remains the pool's own balance (Core->EVM move
    // doesn't change pool value), so cancelling loses nothing for the user.
    if (block.timestamp <= withdrawal.announcedAt + WITHDRAWAL_TIMEOUT) {
      revert HyperliquidWithdrawalManager__TimeoutNotReached();
    }

    uint256 amount = withdrawal.amount;
    uint256 reserved = withdrawal.reservedBridge;

    // Clean up state before external call.
    totalPendingTokens[pool] -= amount;
    if (reserved != 0) reservedBridgeUsdc[pool] -= reserved;
    delete _pendingWithdrawals[msg.sender][pool];

    IERC20(pool).safeTransfer(msg.sender, amount);

    emit WithdrawalCancelled(msg.sender, pool, amount);
  }

  /////////////////////////////////////////////
  //             View Functions              //
  /////////////////////////////////////////////

  function pendingWithdrawals(address user, address pool) external view returns (PendingWithdrawal memory) {
    return _pendingWithdrawals[user][pool];
  }

  /// @notice Returns true if there are pending withdrawal tokens for the pool.
  /// @dev Informational view of outstanding withdrawal tokens. The guard gates isPublic=true on
  ///      `isExecuting()` (the transient execution flag), not on this value.
  function hasPendingWithdrawal(address pool) external view returns (bool) {
    return totalPendingTokens[pool] > 0;
  }

  /// @notice Returns true if the WM is currently inside a pool.execTransaction call.
  /// @dev Read by the guard to gate isPublic=true exclusively to WM-initiated transactions.
  function isExecuting() external view returns (bool result) {
    bytes32 slot = _EXECUTING_SLOT;
    assembly {
      result := tload(slot)
    }
  }

  /////////////////////////////////////////////
  //                  Admin                  //
  /////////////////////////////////////////////

  /// @notice Update the CoreWriterContractGuard reference.
  function setCoreWriterGuard(address _coreWriterGuard) external onlyOwner {
    _setCoreWriterGuard(_coreWriterGuard);
  }

  /////////////////////////////////////////////
  //           Internal Functions            //
  /////////////////////////////////////////////

  function _setCoreWriterGuard(address _coreWriterGuard) internal {
    address previousGuard = address(coreWriterGuard);
    coreWriterGuard = IHyperliquidCoreWriterContractGuard(_coreWriterGuard);

    emit CoreWriterGuardUpdated(previousGuard, _coreWriterGuard);
  }

  function _getPortion(address pool, uint256 tokenAmount) internal view returns (uint256 portion) {
    portion = tokenAmount.divWadDown(IERC20(pool).totalSupply());
    if (portion >= 1e18) revert HyperliquidWithdrawalManager__FullWithdrawalNotSupported();
  }

  /// @notice Reverts unless `ids` is strictly ascending, which also guarantees uniqueness.
  /// @dev De-dup guard for the reduce/sell arrays. Enforces uniqueness in O(n) with no extra
  ///      storage; the stored `spotAssetIds` are then also unique for `bridge`'s re-valuation.
  function _requireStrictlyAscending(uint32[] calldata ids) internal pure {
    for (uint256 i = 1; i < ids.length; ++i) {
      if (ids[i] <= ids[i - 1]) revert HyperliquidWithdrawalManager__UnsortedAssetIds();
    }
  }

  /// @notice The spot sell portion: the raw withdrawal portion plus a small slippage buffer.
  /// @dev Defensive buffer for the pure-spot bridge, whose send is clamped to the USDC the sell
  ///      actually freed (no perp margin to top it up). A spot sell fills at oracle ± order slippage,
  ///      so selling exactly `portion` can free slightly less USDC than the guard's settle-time
  ///      `getBalance * portion / (1 - portion)` demand (the guard values the remaining token at
  ///      oracle). Selling a touch extra keeps the freed USDC at/above that demand under adverse
  ///      fills. Capped just below 100%; orders are reduce-only so any rounding can only close, never
  ///      flip, the position.
  /// @param portion The raw withdrawal portion in WAD.
  /// @return sellPortion The buffered sell portion in WAD.
  function _spotSellPortion(uint256 portion) internal pure returns (uint256 sellPortion) {
    sellPortion = portion + (portion * _BRIDGE_SAFETY_MARGIN_BPS) / _BPS_DENOMINATOR;
    if (sellPortion >= 1e18) sellPortion = 1e18 - 1;
  }

  /// @notice Reverts unless the supplied perp ids cover essentially all of the pool's open perp
  ///         notional on every perp dex it trades.
  /// @dev The bridge's action-7 margin pull (in `_bridgeUsdcToEvm`) shrinks a dex's shared
  ///      cross-margin equity whether or not a position is reduced, so an open perp omitted from
  ///      `perpAssetIds` keeps its full notional while equity drops, raising leverage for the holders
  ///      who remain. HyperCore exposes no "list my positions" read, so completeness is checked per
  ///      dex against the account's own aggregate `ntlPos`: the named legs are priced at oracle px
  ///      (6-dec USD, matching `ntlPos`) and their sum must reach `ntlPos` net of
  ///      `_PERP_COVERAGE_TOLERANCE_BPS`. This subsumes the empty-array case (namedNtl == 0 reverts
  ///      whenever any dex has open notional).
  /// @param pool The pool address (whose HyperCore account holds the positions).
  /// @param perpAssetIds The perp asset IDs supplied by the caller.
  function _requirePerpIdsCoverOpenNotional(address pool, uint32[] calldata perpAssetIds) internal view {
    uint256[] memory dexIds = coreWriterGuard.getApprovedDexIds();
    for (uint256 d; d < dexIds.length; ++d) {
      uint256 dexId = dexIds[d];
      if (dexId == _DEX_ID_CORE_SPOT) continue;

      uint256 dexNtlPos = accountMarginSummary(pool, dexId).ntlPos;
      if (dexNtlPos == 0) continue;

      // Oracle-priced notional of the named perps that belong to this dex (6-dec USD).
      uint256 namedNtl;
      for (uint256 i; i < perpAssetIds.length; ++i) {
        if (_getPerpDexId(perpAssetIds[i]) != dexId) continue;

        uint32 perpIndex = _getPerpIndex(perpAssetIds[i]);
        int64 szi = position(pool, perpIndex).szi;
        if (szi == 0) continue;

        uint64 absSz = szi > 0 ? uint64(szi) : uint64(-szi);
        // notional6 = |szi| * oraclePx: |szi| is in szDecimals and oraclePx is 10^(6 - szDecimals)-
        // scaled USD, so the product is 6-decimal USD (see PrecompileHelper.normalizedOraclePx).
        namedNtl += uint256(absSz) * oraclePx(perpIndex);
      }

      uint256 minCoverage = (dexNtlPos * (_BPS_DENOMINATOR - _PERP_COVERAGE_TOLERANCE_BPS)) / _BPS_DENOMINATOR;
      if (namedNtl < minCoverage) revert HyperliquidWithdrawalManager__UnreducedPerpPosition();
    }
  }

  /// @notice Reduce specified perp positions proportionally by placing reduce-only IOC orders.
  /// @param pool The pool address (whose HyperCore account holds the positions).
  /// @param portion The fraction to reduce (in WAD, e.g. 0.1e18 = 10%).
  /// @param perpAssetIds The asset IDs to reduce (caller-verified to have open positions).
  function _reducePositions(address pool, uint256 portion, uint32[] calldata perpAssetIds) internal {
    for (uint256 i; i < perpAssetIds.length; ++i) {
      _reducePosition(pool, perpAssetIds[i], portion);
    }
  }

  function _reducePosition(address pool, uint32 asset, uint256 portion) internal {
    uint32 perpIndex = _getPerpIndex(asset);
    // The position precompile is keyed by perp index, not the raw asset id. For core perps the
    // two coincide, but for HIP-3 perps (asset >= 100_000) they differ, so the index must be used.
    Position memory pos = position(pool, perpIndex);
    if (pos.szi == 0) revert HyperliquidWithdrawalManager__NoPositionForAsset(asset);

    uint64 absSz = pos.szi > 0 ? uint64(pos.szi) : uint64(-pos.szi);
    // `pos.szi` is in the perp's szDecimals; order sizes are always 8 decimals. Rescale before
    // taking the portion so assets with szDecimals != 8 are sized correctly, then floor onto the
    // lot grid (multiple of 10^(8 - szDecimals)).
    uint8 szDecimals = perpAssetInfo(perpIndex).szDecimals;
    uint64 reductionSz = _roundSizeToLot(_toOrderSize(absSz, szDecimals).mulWadDown(portion), szDecimals);
    if (reductionSz == 0) return;

    bool isBuy = pos.szi < 0;
    uint64 limitPrice = _getReduceLimitPrice(perpIndex, szDecimals, isBuy);

    bytes memory txData = abi.encodeWithSelector(
      ICoreWriter.sendRawAction.selector,
      abi.encodePacked(
        uint8(1),
        HyperliquidConstants.ACTION_LIMIT_ORDER,
        abi.encode(asset, isBuy, limitPrice, reductionSz, true, uint8(OrderType.IOC), uint128(0))
      )
    );
    _execTransaction(pool, txData);
  }

  /// @notice Reduce-only IOC limit price for a perp, snapped onto HyperCore's tick grid.
  /// @dev `oracle +/- slippage` at full precision almost always violates the <= 5 sig fig /
  ///      <= (6 - szDecimals) decimal tick rules and is then silently rejected on Core. Round toward
  ///      more slippage (ceil for buys, floor for sells) so the snapped price stays marketable for
  ///      the IOC fill.
  /// @param perpIndex The perp asset index.
  /// @param szDecimals The perp's szDecimals (governs the tick decimal cap).
  /// @param isBuy True when reducing a short (buy to close), false when reducing a long.
  /// @return The grid-aligned limit price in 8-decimal fixed point.
  function _getReduceLimitPrice(uint32 perpIndex, uint8 szDecimals, bool isBuy) internal view returns (uint64) {
    // normalizedOraclePx is 6 decimals; * 1e2 yields the 8-decimal limitPx format.
    uint256 price = normalizedOraclePx(perpIndex) * 1e2;
    uint256 slippageAmount = price.mulWadDown(_ORDER_SLIPPAGE);
    uint256 slipped = isBuy ? price + slippageAmount : price - slippageAmount;
    return _roundPriceToTick(slipped, szDecimals, _PERP_MAX_PRICE_DECIMALS, isBuy);
  }

  /// @notice Returns the perp index for core/HIP-3 perp asset IDs.
  /// @dev Core perp assets use the index directly (< 10_000). HIP-3 perps encode the index as
  ///      `assetId - 100_000`. Spot pair ids (10_000..99_999) are invalid here.
  function _getPerpIndex(uint32 assetId) internal pure returns (uint32 perpIndex) {
    if (assetId < 10_000) return assetId;
    if (assetId >= 100_000) return assetId - 100_000;
    revert HyperliquidWithdrawalManager__NoPositionForAsset(assetId);
  }

  /// @notice Returns the perp dex id an asset id trades on (core perp dex, or a HIP-3 dex).
  /// @dev Mirrors the guard's dex derivation: core perps (< 10_000) sit on `_DEX_ID_CORE_PERP`;
  ///      HIP-3 perps (>= 100_000) encode the dex as `(assetId - 100_000) / 10_000`. Spot pair ids
  ///      (10_000..99_999) are not perps and are rejected.
  function _getPerpDexId(uint32 assetId) internal pure returns (uint256 dexId) {
    if (assetId < 10_000) return _DEX_ID_CORE_PERP;
    if (assetId >= 100_000) return (uint256(assetId) - 100_000) / 10_000;
    revert HyperliquidWithdrawalManager__NoPositionForAsset(assetId);
  }

  /// @notice Rescale a base-asset amount from its native Core decimals to the 8-decimal order size.
  /// @dev In practice only the `decimals <= 8` branch runs (HL bounds szDecimals/weiDecimals <= 8).
  ///      The `decimals > 8` branch is defensive against an underflow in `10 ** (8 - decimals)`.
  /// @param amount The amount in the base asset's native decimals.
  /// @param decimals The base asset's native decimals (szDecimals for perps, weiDecimals for spot).
  /// @return The amount rescaled to 8 decimals.
  function _toOrderSize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
    if (decimals <= _CORE_ORDER_DECIMALS) {
      return amount * (10 ** (_CORE_ORDER_DECIMALS - decimals));
    }
    return amount / (10 ** (decimals - _CORE_ORDER_DECIMALS));
  }

  /// @notice Round an 8-decimal price onto HyperCore's tick grid, toward more slippage.
  /// @dev HyperCore caps prices at 5 significant figures and `maxPriceDecimals - szDecimals` decimal
  ///      places (maxPriceDecimals = 6 perp, 8 spot), and silently rejects off-grid prices (async,
  ///      post-block) - the order would reduce nothing and the withdrawal could not settle. Both caps
  ///      become a price step in the 8-dec order encoding; the binding (larger) step is applied.
  ///      Rounding up (ceil) on the buy side / down (floor) on the sell side only ever adds slippage,
  ///      keeping IOC orders marketable.
  /// @param price8 The unrounded price in 8-decimal fixed point.
  /// @param szDecimals The asset's szDecimals.
  /// @param maxPriceDecimals HyperCore's MAX_DECIMALS for the market (6 perp, 8 spot).
  /// @param roundUp True rounds up (buy side), false rounds down (sell side).
  /// @return The grid-aligned price in 8-decimal fixed point.
  function _roundPriceToTick(
    uint256 price8,
    uint8 szDecimals,
    uint256 maxPriceDecimals,
    bool roundUp
  ) internal pure returns (uint64) {
    if (price8 == 0) return 0;
    // Significant-figure step: smallest 10^k leaving <= _MAX_PRICE_SIG_FIGS significant digits.
    uint256 sigFigLimit = 10 ** _MAX_PRICE_SIG_FIGS;
    uint256 tick = 1;
    while (price8 / tick >= sigFigLimit) {
      tick *= 10;
    }
    // Decimal-place cap: <= (maxPriceDecimals - szDecimals) decimals, i.e. a multiple of
    // 10^(_CORE_ORDER_DECIMALS - maxPriceDecimals + szDecimals) in the 8-dec order encoding.
    uint256 decimalTick = 10 ** (_CORE_ORDER_DECIMALS - maxPriceDecimals + szDecimals);
    // Bind by the stricter (larger) of the sig-fig step and the decimal-place cap.
    if (decimalTick > tick) tick = decimalTick;
    uint256 rounded = roundUp ? ((price8 + tick - 1) / tick) * tick : (price8 / tick) * tick;
    return rounded.toUint64();
  }

  /// @notice Floor an 8-decimal order size onto HyperCore's lot grid (multiple of 10^(8 - szDecimals)).
  /// @dev HyperCore rounds sizes to the asset's szDecimals and silently rejects finer sizes. Flooring
  ///      keeps reduce/sell orders no larger than intended (reduce-only-safe); a dust size floors to 0,
  ///      which callers skip.
  /// @param size8 The order size in 8-decimal fixed point.
  /// @param szDecimals The asset's szDecimals.
  /// @return The lot-aligned size in 8-decimal fixed point.
  function _roundSizeToLot(uint256 size8, uint8 szDecimals) internal pure returns (uint64) {
    uint256 lot = szDecimals >= _CORE_ORDER_DECIMALS ? 1 : 10 ** (_CORE_ORDER_DECIMALS - uint256(szDecimals));
    return ((size8 / lot) * lot).toUint64();
  }

  /// @notice Sell specified spot positions proportionally by placing IOC sell orders.
  /// @param pool The pool address (whose HyperCore account holds the spot tokens).
  /// @param portion The fraction to sell (in WAD, e.g. 0.1e18 = 10%).
  /// @param spotAssetIds The spot pair IDs (10000+) to sell (caller-verified to have Core balance).
  function _sellSpotPositions(address pool, uint256 portion, uint32[] calldata spotAssetIds) internal {
    for (uint256 i; i < spotAssetIds.length; ++i) {
      _sellSpotPosition(pool, spotAssetIds[i], portion);
    }
  }

  function _sellSpotPosition(address pool, uint32 spotAssetId, uint256 portion) internal {
    uint64 spotIndex = _getSpotIndex(spotAssetId);
    uint64 baseTokenIndex = spotInfo(spotIndex).tokens[0];

    // Get Core balance in the base token's weiDecimals.
    uint64 balance = spotBalance(pool, baseTokenIndex).total;
    if (balance == 0) revert HyperliquidWithdrawalManager__NoSpotBalanceForAsset(spotAssetId);

    // CoreWriter order sizes are always 8 decimals: rescale the weiDecimals balance, take the
    // portion, then floor onto the lot grid (multiple of 10^(8 - szDecimals)).
    TokenInfo memory baseToken = tokenInfo(baseTokenIndex);
    uint64 sellSz = _roundSizeToLot(
      _toOrderSize(balance, baseToken.weiDecimals).mulWadDown(portion),
      baseToken.szDecimals
    );
    if (sellSz == 0) return;

    // Sell limit = spot price - slippage (pessimistic), floored onto the tick grid. Raw spotPx is on
    // grid, but subtracting slippage knocks it off, so re-round down (toward more slippage).
    uint256 price = normalizedSpotPx(spotIndex);
    uint256 slippageAmount = price.mulWadDown(_ORDER_SLIPPAGE);
    uint64 limitPrice = _roundPriceToTick(
      price - slippageAmount,
      baseToken.szDecimals,
      _SPOT_MAX_PRICE_DECIMALS,
      false
    );

    bytes memory txData = abi.encodeWithSelector(
      ICoreWriter.sendRawAction.selector,
      abi.encodePacked(
        uint8(1),
        HyperliquidConstants.ACTION_LIMIT_ORDER,
        abi.encode(spotAssetId, false, limitPrice, sellSz, true, uint8(OrderType.IOC), uint128(0))
      )
    );
    _execTransaction(pool, txData);
  }

  /// @notice Bridge USDC from HyperCore to EVM via pool.execTransaction.
  /// @dev For HIP-3 dexes, first consolidates USDC into core perp dex (action 13). Then transfers
  ///      only the deficit perp→spot (action 7, spot sells already landed in spot) and bridges
  ///      spot→EVM (action 6). CoreWriter processes actions in order; USDC lands on EVM next block.
  function _bridgeUsdcToEvm(address pool, uint256 withdrawalAmount, uint32[] memory spotAssetIds) internal {
    uint256 portion = _getPortion(pool, withdrawalAmount);
    uint256 bridgeAmount = _computeBridgeAmount(pool, portion, spotAssetIds);
    // No Hyperliquid value to withdraw at all (pool holds nothing on Core for this portion).
    if (bridgeAmount == 0) revert HyperliquidWithdrawalManager__NothingToBridge();

    // Credit EVM USDC already idle in the pool — only bridge the deficit from Core.
    uint256 effectiveBridge = _getEffectiveBridgeAmount(pool, bridgeAmount, portion);
    if (effectiveBridge == 0) return;

    // Consolidate USDC from HIP-3 dexes into core perp dex (dex 0) via sendAsset (action 13).
    // Proportional, matching the freed-and-bridged share; per-dex amount is capped by free margin.
    _consolidateHip3Dexes(pool, portion);

    // Read current Core spot USDC balance (includes proceeds from spot sells in announceAndReduce).
    // spotBalance is in weiDecimals (8 dec for USDC). Convert to 6 dec for comparison.
    uint256 spotUsdc6 = uint256(spotBalance(pool, _USDC_TOKEN_INDEX).total) / 1e2;

    // Keep `_BRIDGE_GAS_RESERVE` USDC in spot to pay the bridge fee; sending the whole balance would
    // leave nothing for it and CoreWriter would silently drop the bridge.
    uint256 sendAmount = effectiveBridge;
    uint256 requiredSpot = effectiveBridge + _BRIDGE_GAS_RESERVE;

    if (spotUsdc6 < requiredSpot) {
      if (_hasOpenPerpPosition(pool)) {
        // Action 7: top up the deficit plus the reserve from perp margin; bridged amount unchanged.
        uint64 perpToSpotAmount = (requiredSpot - spotUsdc6).toUint64();

        bytes memory transferAction = abi.encodePacked(
          uint8(1),
          HyperliquidConstants.ACTION_USD_CLASS_TRANSFER,
          abi.encode(perpToSpotAmount, false) // false = from perp to spot
        );
        bytes memory transferTxData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, transferAction);
        _execTransaction(pool, transferTxData);
      } else {
        // Spot-only: no perp margin, so bridge the freed USDC minus the reserve. The buffered sell
        // (`_spotSellPortion`) keeps the remainder above the settle demand.
        sendAmount = spotUsdc6 > _BRIDGE_GAS_RESERVE ? spotUsdc6 - _BRIDGE_GAS_RESERVE : 0;
      }
    }

    if (sendAmount == 0) revert HyperliquidWithdrawalManager__NoSpotUsdcFreed();

    // Action 6: Spot send to USDC system address (triggers bridge to EVM).
    // Spot send amount is in Core wei (8 decimals for USDC). Scale from 6 dec.
    bytes memory spotSendAction = abi.encodePacked(
      uint8(1),
      HyperliquidConstants.ACTION_SPOT_SEND,
      abi.encode(getSystemAddress(_USDC_TOKEN_INDEX), _USDC_TOKEN_INDEX, (sendAmount * 1e2).toUint64())
    );
    bytes memory spotSendTxData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, spotSendAction);
    _execTransaction(pool, spotSendTxData);
  }

  /// @notice Move freed USDC from HIP-3 dexes (dex 1+) to core perp dex (dex 0) via sendAsset.
  /// @dev No-op if the pool only uses core perp dex. Per-dex amount is the portion of accountValue,
  ///      capped by margin-free equity since an underfilled reduce can leave margin locked.
  /// @param pool The pool address.
  /// @param portion The withdrawal portion in WAD.
  function _consolidateHip3Dexes(address pool, uint256 portion) internal {
    uint256[] memory dexIds = coreWriterGuard.getApprovedDexIds();

    for (uint256 i; i < dexIds.length; ++i) {
      uint256 dexId = dexIds[i];
      if (dexId == _DEX_ID_CORE_PERP || dexId == _DEX_ID_CORE_SPOT) continue;

      AccountMarginSummary memory summary = accountMarginSummary(pool, dexId);
      if (summary.accountValue <= 0) continue;

      // Target share of this dex's equity to consolidate (6 decimals).
      uint256 perDexValue = uint256(uint64(summary.accountValue));
      uint256 perDexBridge = perDexValue.mulWadDown(portion);

      // Cap by margin-free equity: sendAsset can only move collateral not tied up as margin.
      uint256 freeUsdc = _dexFreeUsdc(summary);
      if (perDexBridge > freeUsdc) perDexBridge = freeUsdc;
      if (perDexBridge == 0) continue;

      // sendAsset amount is in Core wei (8 decimals for USDC). Scale from 6 dec.
      uint64 amountCoreWei = (perDexBridge * 1e2).toUint64();

      bytes memory sendAssetAction = abi.encodePacked(
        uint8(1),
        HyperliquidConstants.ACTION_SEND_ASSET,
        abi.encode(pool, address(0), uint32(dexId), _DEX_ID_CORE_PERP, _USDC_TOKEN_INDEX, amountCoreWei)
      );
      bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, sendAssetAction);
      _execTransaction(pool, txData);
    }
  }

  /// @notice Compute the USDC amount (6 decimals) that needs to be bridged from Core to EVM
  ///         for a withdrawal of the given portion.
  /// @param pool The pool address.
  /// @param portion The withdrawal portion in WAD.
  /// @param spotAssetIds The spot pair IDs (10000+) whose Core value the spot guard(s) demand in
  ///        USDC at settle. Excluded from the position guard's getBalance, so added explicitly here.
  /// @return bridgeAmount The amount to bridge in 6 decimals.
  function _computeBridgeAmount(
    address pool,
    uint256 portion,
    uint32[] memory spotAssetIds
  ) internal view returns (uint256 bridgeAmount) {
    // PositionGuard's getBalance matches withdrawProcessing: all dex account values + Core spot USDC
    // (incl. spot sell proceeds) + in-flight.
    address positionGuard = IHasGuardInfo(address(factory)).getAssetGuard(_CORE_WRITER);
    uint256 hlValue = IAssetGuard(positionGuard).getBalance(pool, address(0));

    // getBalance excludes non-USDC Core spot, but each spot guard demands USDC for it at settle.
    // No double count: if sold during announce, proceeds are in `hlValue` and held balance is ~0.
    hlValue += _getSpotCoreValue(pool, spotAssetIds);

    // Bridge `portion` of the total HL value. At settle each guard demands its remaining balance
    // grossed up by `portion / (1 - portion)`; moving `portion` of the value onto EVM shrinks that
    // balance in step, so the bridged USDC covers the demand exactly. Idle EVM USDC is credited at
    // `(1 - portion)` in `_getEffectiveBridgeAmount` (the user receives the other `portion` as the USDC token itself).
    bridgeAmount = hlValue.mulWadUp(portion);
    // Small extra margin for order slippage / mark-to-market drift between bridge and settle.
    bridgeAmount = bridgeAmount + (bridgeAmount * _BRIDGE_SAFETY_MARGIN_BPS) / _BPS_DENOMINATOR;
  }

  /// @notice Sum the 6-decimal USDC value of the pool's Core spot balances for the given spot ids.
  /// @dev Mirrors the spot guard's settle demand: each position's Core (+ in-flight) portion valued
  ///      via `normalizedSpotPx` (USDC-terms, same source as `HyperliquidSpotPriceAggregator`). A
  ///      different aggregator can diverge from the settle demand and under-bridge. The
  ///      EVM-held balance is excluded (sent directly as that token, not via bridged USDC). USDC/USD cancels, so
  ///      it's depeg-safe. Returns 0 when `spotAssetIds` is empty.
  /// @param pool The pool address.
  /// @param spotAssetIds The spot pair IDs (10000+) to value.
  /// @return value6 The total Core spot value in 6 decimals.
  function _getSpotCoreValue(address pool, uint32[] memory spotAssetIds) internal view returns (uint256 value6) {
    if (spotAssetIds.length == 0) return 0;

    address poolManagerLogic = IPoolLogic(pool).poolManagerLogic();
    for (uint256 i; i < spotAssetIds.length; ++i) {
      value6 += _getSingleSpotCoreValue(pool, poolManagerLogic, spotAssetIds[i]);
    }
  }

  /// @notice Value the Core (+ in-flight) portion of a single spot position in 6-decimal USDC.
  /// @dev System-address registration takes priority (values the FULL Core balance); the EVM-contract
  ///      branch subtracts the EVM balance sent directly as that token, matching how the spot guard sizes Core at settle.
  function _getSingleSpotCoreValue(
    address pool,
    address poolManagerLogic,
    uint32 spotAssetId
  ) internal view returns (uint256) {
    uint64 spotIndex = _getSpotIndex(spotAssetId);
    uint64 baseTokenIndex = spotInfo(spotIndex).tokens[0];

    address systemAddr = getSystemAddress(baseTokenIndex);
    address evmContract = tokenInfo(baseTokenIndex).evmContract;

    address asset;
    IAssetGuard spotGuard;
    uint256 coreBalance;
    if (IHasSupportedAsset(poolManagerLogic).isSupportedAsset(systemAddr)) {
      // System asset: the spot guard values the full Core balance returned by its getBalance.
      asset = systemAddr;
      spotGuard = IAssetGuard(IHasGuardInfo(address(factory)).getAssetGuard(asset));
      coreBalance = spotGuard.getBalance(pool, asset);
    } else if (IHasSupportedAsset(poolManagerLogic).isSupportedAsset(evmContract)) {
      // EVM-contract asset: the EVM balance is sent directly as that token, only the Core (+ in-flight) part is
      // settled in USDC. getBalance returns evm + core (+ in-flight), so subtract the EVM balance.
      asset = evmContract;
      spotGuard = IAssetGuard(IHasGuardInfo(address(factory)).getAssetGuard(asset));
      uint256 total = spotGuard.getBalance(pool, asset);
      uint256 evmBalance = IERC20(asset).balanceOf(pool);
      coreBalance = total > evmBalance ? total - evmBalance : 0;
    } else {
      revert HyperliquidWithdrawalManager__SpotAssetNotSupported(spotAssetId);
    }

    if (coreBalance == 0) return 0;

    uint256 assetDecimals = spotGuard.getDecimals(asset);
    return (coreBalance * normalizedSpotPx(spotIndex)) / (10 ** assetDecimals * 1e2);
  }

  /// @notice Returns the spot index for a Hyperliquid spot pair asset ID.
  /// @dev Spot pair ids encode the index as `spotAssetId - 10_000`. Core perp ids (< 10_000) are
  ///      invalid here and revert with `HyperliquidWithdrawalManager__SpotAssetNotSupported`.
  function _getSpotIndex(uint32 spotAssetId) internal pure returns (uint64 spotIndex) {
    if (spotAssetId < 10_000) revert HyperliquidWithdrawalManager__SpotAssetNotSupported(spotAssetId);
    return uint64(spotAssetId) - 10_000;
  }

  /// @notice Returns the effective amount that actually needs to be bridged from Core, after
  ///         crediting the USDC already idle on EVM in the pool.
  /// @dev The withdrawer is owed their `portion` of every asset, including this idle EVM USDC, so
  ///      `portion` of it is already promised to them. Only the remaining `(1 - portion)` stays in the
  ///      pool to help pay the Hyperliquid position at settle, so we credit just that much against the
  ///      bridge. Crediting the full balance bridges too little whenever a reducible position is also
  ///      present, and settle reverts with "not enough available balance_1".
  /// @param pool The pool address.
  /// @param bridgeAmount The full bridge amount (from `_computeBridgeAmount`).
  /// @param portion The withdrawal portion in WAD.
  /// @return effectiveBridge The deficit that must come from Core (6 decimals). Zero if EVM has enough.
  function _getEffectiveBridgeAmount(
    address pool,
    uint256 bridgeAmount,
    uint256 portion
  ) internal view returns (uint256 effectiveBridge) {
    uint256 usableEvmUsdc = IERC20(_USDC_ADDRESS).balanceOf(pool).mulWadDown(1e18 - portion);
    if (bridgeAmount > usableEvmUsdc) {
      effectiveBridge = bridgeAmount - usableEvmUsdc;
    }
  }

  /// @notice Total free USDC on Core that a bridge can move without reducing any position (6 dec).
  /// @dev Sums margin-free equity (`equity - ntlPos`) across the core perp dex and HIP-3 dexes plus
  ///      idle USDC in the spot account. This is the buffer a skipped reduce draws against; the
  ///      per-pool `reservedBridgeUsdc` keeps concurrent skips from double-counting it and
  ///      over-draining the shared perp margin.
  /// @param pool The pool address.
  /// @return freeUsdc The available USDC in 6 decimals.
  function _getFreeCoreUsdc(address pool) internal view returns (uint256 freeUsdc) {
    // Margin-free equity on the core perp account and HIP-3 dexes (what can be bridged as-is).
    uint256[] memory dexIds = coreWriterGuard.getApprovedDexIds();
    for (uint256 i; i < dexIds.length; ++i) {
      uint256 dexId = dexIds[i];
      if (dexId == _DEX_ID_CORE_SPOT) continue;

      freeUsdc += _dexFreeUsdc(accountMarginSummary(pool, dexId));
    }

    // USDC already sitting in the Core spot account (e.g., from previous spot sells).
    // spotBalance is in weiDecimals (8 dec for USDC), convert to 6 dec.
    freeUsdc += uint256(spotBalance(pool, _USDC_TOKEN_INDEX).total) / 1e2;
  }

  /// @notice Equity on a perp dex that isn't backing any open position notional.
  /// @dev `accountValue - ntlPos`. For a pure long this equals `rawUsd`; unlike `rawUsd` (which a
  ///      short inflates by adding its notional), this is symmetric, so an open short forces a
  ///      proportional reduce just like a long instead of being mistaken for idle USDC.
  function _dexFreeUsdc(AccountMarginSummary memory summary) internal pure returns (uint256) {
    if (summary.accountValue <= 0) return 0;
    uint256 equity = uint256(uint64(summary.accountValue));
    return equity > summary.ntlPos ? equity - summary.ntlPos : 0;
  }

  /// @notice Returns true if the pool has any open perp position across the approved perp dexes.
  /// @dev A non-zero notional (`ntlPos`) on any non-spot dex indicates an open perp. Used at bridge
  ///      time to decide whether to top up the spot account from perp margin before bridging.
  /// @param pool The pool address.
  function _hasOpenPerpPosition(address pool) internal view returns (bool) {
    uint256[] memory dexIds = coreWriterGuard.getApprovedDexIds();
    for (uint256 i; i < dexIds.length; ++i) {
      if (dexIds[i] == _DEX_ID_CORE_SPOT) continue;
      if (accountMarginSummary(pool, dexIds[i]).ntlPos > 0) return true;
    }
    return false;
  }

  /// @dev Wraps pool.execTransaction with transient flag so the guard returns isPublic=true.
  function _execTransaction(address pool, bytes memory txData) internal {
    bytes32 slot = _EXECUTING_SLOT;
    assembly {
      tstore(slot, 1)
    }
    IPoolLogic(pool).execTransaction(_CORE_WRITER, txData);
    assembly {
      tstore(slot, 0)
    }
  }
}
