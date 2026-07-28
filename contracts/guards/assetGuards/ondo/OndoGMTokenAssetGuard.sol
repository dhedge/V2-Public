// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {ERC20Guard} from "../ERC20Guard.sol";
import {IAddAssetCheckGuard} from "../../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IAssetGuard} from "../../../interfaces/guards/IAssetGuard.sol";
import {IComplexAssetGuard} from "../../../interfaces/guards/IComplexAssetGuard.sol";
import {IERC20Extended} from "../../../interfaces/IERC20Extended.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IGMTokenManager} from "../../../interfaces/ondo/IGMTokenManager.sol";
import {IOndoGMSwap} from "../../../interfaces/ondo/IOndoGMSwap.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {AutomationBase} from "../../../utils/chainlink/AutomationBase.sol";
import {WithdrawalHelperLib} from "../../../utils/WithdrawalHelperLib.sol";

/// @title Ondo GM Token asset guard
/// @dev Asset type = 41
/// @notice Redeems the depositor's portion of GM to USDC atomically inside
///         `PoolLogic._withdrawProcessing` via `OndoGMSwap.swapExactInWithAttestation`.
/// @dev    Inherits `ERC20Guard` for `getBalance` / `getDecimals` / `removeAssetCheck`. The
///         5-arg `IComplexAssetGuard` overload does the redeem and requires a signed Ondo
///         attestation in `withdrawData`; raw GM is never delivered. The 4-arg overload
///         (empty `withdrawData`) reverts — unless the depositor's GM portion is sub-$1 dust
///         that Ondo can't swap, in which case it skips the redeem and leaves the dust behind.
contract OndoGMTokenAssetGuard is ERC20Guard, IComplexAssetGuard, AutomationBase, IAddAssetCheckGuard {
  using SafeMath for uint256;

  /// @notice Frontend-supplied per-withdrawal payload, embedded into `ComplexAsset.withdrawData`.
  /// @dev    `tokenIn` is `_asset` (PoolLogic-supplied), `tokenOut` is the immutable `usdc`,
  ///         and `amountIn` is `quote.quantity` — none of those are passed by the frontend so
  ///         calldata cannot redirect the swap. `amountOutMinimum` lets the frontend tighten
  ///         the USDC floor above the on-chain 1% cap; it cannot loosen it.
  struct OndoWithdrawData {
    bytes attestationSignature;
    IGMTokenManager.Quote quote;
    uint256 amountOutMinimum;
  }

  // solhint-disable-next-line const-name-snakecase
  bool public constant override isAddAssetCheckGuard = true;

  uint256 internal constant BPS_DENOMINATOR = 10_000;

  /// @dev Maximum allowed shortfall of `amountOutMinimum` vs. the deterministic USDon
  ///      redemption value (= quote.quantity × quote.price / 1e18). Bounds how aggressively
  ///      a frontend can understate the USDC floor so PoolLogic's net-slippage check can't
  ///      be sidestepped by pairing a large slippageTolerance with a near-zero amountOutMinimum.
  uint256 internal constant MAX_AMOUNT_OUT_MIN_DISCOUNT_BPS = 100; // 1%

  address public immutable ondoGMSwap;

  address public immutable usdc;

  /// @notice One-sided tolerance (bps) for `quote.quantity` undershoot vs on-chain portion.
  ///         Absorbs sim→exec drift; quote.quantity must NEVER exceed portionAmount.
  uint256 public immutable mismatchDeltaNumerator;

  /// @notice Minimum USD value (1e18-scaled) of a GM portion for a redeem to be attempted.
  ///         Below this the portion is left in the pool as dust — Ondo rejects sub-$1 swaps.
  ///         Set above $1 to absorb oracle-vs-attestation price drift.
  uint256 public immutable minRedeemValue;

  constructor(address _ondoGMSwap, uint256 _mismatchDeltaNumerator, uint256 _minRedeemValue) {
    require(_ondoGMSwap != address(0), "invalid ondoGMSwap");
    require(_mismatchDeltaNumerator <= MAX_AMOUNT_OUT_MIN_DISCOUNT_BPS, "invalid mismatch delta");
    require(_minRedeemValue >= 1e18, "invalid minRedeemValue");

    ondoGMSwap = _ondoGMSwap;
    usdc = IOndoGMSwap(_ondoGMSwap).usdc();
    mismatchDeltaNumerator = _mismatchDeltaNumerator;
    minRedeemValue = _minRedeemValue;
  }

  /// @notice Runs when `withdrawData` is empty. Reverts — a redeem needs a signed Ondo
  ///         attestation via the 5-arg overload — unless the GM portion is worth less than
  ///         `minRedeemValue`: Ondo can't swap sub-$1 dust, so it is left in the pool.
  /// @dev    Returns `address(0)` so PoolLogic skips the dh26 net-slippage check entirely;
  ///         nothing is transferred to the investor for this asset, dust is left in the pool.
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address /* _to */
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, IAssetGuard.MultiTransaction[] memory transactions)
  {
    uint256 portionAmount = _portionAmount(_pool, _asset, _withdrawPortion);
    require(_isBelowMinRedeemValue(_pool, _asset, portionAmount), "withdrawData required");
    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @inheritdoc IComplexAssetGuard
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _withdrawPortion,
    address /* _to */,
    bytes memory _withdrawData
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, IAssetGuard.MultiTransaction[] memory transactions)
  {
    OndoWithdrawData memory data = abi.decode(_withdrawData, (OndoWithdrawData));

    // The per-user GM share is deterministic (balance × portion / 1e18). The frontend
    // calls `previewGmTokenAmount` via `callStatic` to obtain the exact amount and then
    // requests an Ondo attestation quote sized for that result.
    // ONE-SIDED tolerance: quote.quantity must NEVER exceed portionAmount (otherwise the pool
    // would redeem more GM than the user is entitled to and the user extracts value from
    // other LPs — PoolLogic's slippage check is a lower bound on USDC received, not an upper
    // bound on GM consumed). A small undershoot is allowed for sim→exec drift; any leftover
    // GM stays in the pool.
    uint256 portionAmount = _portionAmount(_pool, _asset, _withdrawPortion);
    _assertQuoteQuantityWithinDelta(data.quote.quantity, portionAmount, mismatchDeltaNumerator);

    // USDon is swapped to USDC by USDonManager — the only leg with price variance, with
    // `amountOutMinimum` as its floor. Bound that floor here so it can't be set unreasonably low.
    // Comparison assumes 1 USDon ≈ 1 USDC (Ondo's USDonManager redeems USDon for USDC at par).
    {
      uint256 amountOutMinD18 = data.amountOutMinimum.mul(1e18).div(10 ** IERC20Extended(usdc).decimals());
      require(
        amountOutMinD18.mul(BPS_DENOMINATOR) >=
          _redemptionUSDonValueD18(data.quote).mul(BPS_DENOMINATOR.sub(MAX_AMOUNT_OUT_MIN_DISCOUNT_BPS)),
        "amountOutMinimum too low"
      );
    }

    transactions = _buildRedeemTransactions(
      _asset,
      data.quote.quantity,
      data.amountOutMinimum,
      data.attestationSignature,
      data.quote
    );

    withdrawAsset = usdc;
    // Note that `withdrawBalance` is 0 because PoolLogic will handle the withdrawn portion from Ondo GM redemption
    return (withdrawAsset, withdrawBalance, transactions);
  }

  /// @notice GM token amount a withdrawer gets for a pool token amount; sizes `quote.quantity`
  ///         for the Ondo attestation.
  /// @dev    State mutating (mints manager fee for an accurate totalSupply) — call via `callStatic`.
  ///         Output is shaved 0.01% to stay at or below the on-chain `portionAmount` if fees
  ///         accrue between simulation and execution.
  /// @param _pool            The pool logic address
  /// @param _asset           The Ondo GM token address
  /// @param _poolTokenAmount The amount of pool tokens to be withdrawn
  /// @return gmTokenAmount   The GM token amount to be withdrawn (rounded down)
  function previewGmTokenAmount(
    address _pool,
    address _asset,
    uint256 _poolTokenAmount
  ) external cannotExecute returns (uint256 gmTokenAmount) {
    (uint256 portion, ) = WithdrawalHelperLib.calculateWithdrawalPortion(_pool, _poolTokenAmount);
    uint256 portionAmount = _portionAmount(_pool, _asset, portion);
    // Mirrors the 4-arg `withdrawProcessing` dust guard: when the portion is worth less than
    // `minRedeemValue` (including zero-balance) no attestation is needed, so signal that to
    // the frontend by returning 0.
    if (_isBelowMinRedeemValue(_pool, _asset, portionAmount)) return 0;
    // `_portionAmount` does getBalance × portion / 1e18 — division rounds down.
    // Shave 0.01% so quoted amount stays at or below the on-chain `portionAmount` despite fee accrual.
    gmTokenAmount = WithdrawalHelperLib.applyPortionShrinkBuffer(portionAmount);
  }

  function addAssetCheck(address, IHasSupportedAsset.Asset calldata _asset) external pure override {
    require(!_asset.isDeposit, "deposit not supported");
  }

  function _portionAmount(address _pool, address _asset, uint256 _portion) internal view returns (uint256) {
    return getBalance(_pool, _asset).mul(_portion).div(1e18);
  }

  /// @dev True when `_amount` of `_asset` is worth less than `minRedeemValue` per the pool's
  ///      oracle. Valued on-chain so the skip decision can't be manipulated via calldata.
  function _isBelowMinRedeemValue(address _pool, address _asset, uint256 _amount) internal view returns (bool) {
    address poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();
    return IPoolManagerLogic(poolManagerLogic).assetValue(_asset, _amount) < minRedeemValue;
  }

  /// @dev One-sided cross-check: `_quoteQuantity` MUST NOT exceed `_reference`, and any
  ///      undershoot must fall within the mismatch-delta band.
  function _assertQuoteQuantityWithinDelta(
    uint256 _quoteQuantity,
    uint256 _reference,
    uint256 _mismatchDelta
  ) internal pure {
    require(_quoteQuantity <= _reference, "quote quantity > reference");
    require(
      _reference.sub(_quoteQuantity) <= _reference.mul(_mismatchDelta).div(BPS_DENOMINATOR),
      "quote quantity mismatch"
    );
  }

  /// @dev Deterministic on-chain redemption value of the quote in USDon (D18 fixed-point):
  ///      `quote.quantity × quote.price / 1e18`. Matches GMTokenManager's redemption math.
  function _redemptionUSDonValueD18(IGMTokenManager.Quote memory _quote) internal pure returns (uint256) {
    return _quote.quantity.mul(_quote.price).div(1e18);
  }

  /// @dev Approve + swap calldata for an Ondo GM redemption. Returns 2 txs — the receiver of
  ///      the swap output is `msg.sender` of the swap call, which is the pool when executed by
  ///      PoolLogic via `withdrawProcessing`.
  function _buildRedeemTransactions(
    address _gmAsset,
    uint256 _amountIn,
    uint256 _amountOutMinimum,
    bytes memory _attestationSignature,
    IGMTokenManager.Quote memory _quote
  ) internal view returns (IAssetGuard.MultiTransaction[] memory transactions) {
    transactions = new IAssetGuard.MultiTransaction[](2);
    transactions[0].to = _gmAsset;
    transactions[0].txData = abi.encodeWithSelector(IERC20Extended.approve.selector, ondoGMSwap, _amountIn);
    transactions[1].to = ondoGMSwap;
    transactions[1].txData = abi.encodeWithSelector(
      IOndoGMSwap.swapExactInWithAttestation.selector,
      _gmAsset,
      _amountIn,
      usdc,
      _amountOutMinimum,
      _attestationSignature,
      _quote
    );
  }
}
