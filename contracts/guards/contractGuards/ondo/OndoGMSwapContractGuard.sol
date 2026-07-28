// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IGMTokenManager} from "../../../interfaces/ondo/IGMTokenManager.sol";
import {IOndoAttestationOracle} from "../../../interfaces/ondo/IOndoAttestationOracle.sol";
import {IOndoGMSwap} from "../../../interfaces/ondo/IOndoGMSwap.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

/// @title OndoGMSwapContractGuard
/// @notice Contract guard for OndoGMSwap, validates swap parameters and applies fixed per-swap slippage.
contract OndoGMSwapContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  using SafeMath for uint256;

  uint256 public constant MAX_BPS = 10_000;

  /// @notice Fixed slippage charged per swap (replaces measured-delta accumulation, which would
  ///         track on-chain oracle lag rather than real execution cost).
  uint256 public constant FIXED_SLIPPAGE_PER_SWAP_BPS = 10; // 0.1%

  uint256 public immutable maxSlippagePerSwapBps;

  /// @notice Optional oracle for opportunistic price updates on BUY swaps. Set to address(0) to disable.
  IOndoAttestationOracle public immutable attestationOracle;

  constructor(
    address _slippageAccumulator,
    uint256 _maxSlippagePerSwapBps,
    IOndoAttestationOracle _attestationOracle
  ) SlippageAccumulatorUser(_slippageAccumulator) {
    require(_maxSlippagePerSwapBps <= MAX_BPS, "invalid slippage bps");

    maxSlippagePerSwapBps = _maxSlippagePerSwapBps;
    attestationOracle = _attestationOracle;
  }

  /// @notice Pre-transaction validation for OndoGMSwap.swapExactInWithAttestation.
  /// @param _poolManagerLogic Pool manager logic address.
  /// @param _data Transaction data.
  /// @return txType Transaction type.
  /// @return isPublic Whether the transaction is public.
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external view override returns (uint16 txType, bool) {
    bytes4 method = getMethod(_data);

    if (method == IOndoGMSwap.swapExactInWithAttestation.selector) {
      (
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMinimum,
        ,
        IGMTokenManager.Quote memory quote
      ) = abi.decode(getParams(_data), (address, uint256, address, uint256, bytes, IGMTokenManager.Quote));

      // Check if the Ondo GM token is paused for this operation
      IGMTokenManager manager = IOndoGMSwap(_to).gmTokenManager();
      if (quote.side == uint8(IGMTokenManager.QuoteSide.BUY)) {
        require(!manager.gmTokenMintingPaused(quote.asset), "Ondo minting paused");
      } else if (quote.side == uint8(IGMTokenManager.QuoteSide.SELL)) {
        require(!manager.gmTokenRedemptionsPaused(quote.asset), "Ondo redemptions paused");
      } else {
        revert("invalid quote side");
      }

      // Source and destination tokens must be supported by the vault
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenOut), "unsupported destination asset");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenIn), "unsupported source asset");

      // Oracle-based slippage check: amountOutMinimum value must be within allowed slippage of amountIn value
      uint256 srcValue = slippageAccumulator.assetValue(tokenIn, amountIn);
      uint256 dstValue = slippageAccumulator.assetValue(tokenOut, amountOutMinimum);
      require(dstValue >= srcValue.mul(MAX_BPS.sub(maxSlippagePerSwapBps)).div(MAX_BPS), "slippage too high");

      txType = uint16(TransactionType.Exchange);
    }

    return (txType, false);
  }

  /// @notice Post-transaction: opportunistic oracle update and fixed slippage accumulation.
  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    _accessControl(_poolManagerLogic);

    bytes4 method = getMethod(_data);

    if (method == IOndoGMSwap.swapExactInWithAttestation.selector) {
      (
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        ,
        bytes memory attestationSignature,
        IGMTokenManager.Quote memory quote
      ) = abi.decode(getParams(_data), (address, uint256, address, uint256, bytes, IGMTokenManager.Quote));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenOut), "unsupported destination asset");
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenIn), "unsupported source asset");

      // Opportunistic oracle update: piggyback on BUY swaps to refresh the attestation oracle price.
      // Wrapped in try/catch so failures (stale quote, config mismatch, etc.) never block the swap.
      if (address(attestationOracle) != address(0) && quote.side == uint8(IGMTokenManager.QuoteSide.BUY)) {
        IGMTokenManager.Quote[] memory quotes = new IGMTokenManager.Quote[](1);
        quotes[0] = quote;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = attestationSignature;
        // solhint-disable-next-line no-empty-blocks
        try attestationOracle.updatePrices(quotes, signatures) {} catch {}
      }

      // Charge a fixed per-swap slippage against the accumulator using tokenIn on both legs to avoid oracle-lag noise.
      slippageAccumulator.updateSlippageImpact(
        _poolManagerLogic,
        _to,
        SlippageAccumulator.SwapData({
          srcAsset: tokenIn,
          dstAsset: tokenIn,
          srcAmount: amountIn,
          dstAmount: amountIn.mul(MAX_BPS.sub(FIXED_SLIPPAGE_PER_SWAP_BPS)).div(MAX_BPS)
        })
      );
    }
  }
}
