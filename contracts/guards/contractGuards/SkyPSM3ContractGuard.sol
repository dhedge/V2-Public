// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IPSM3} from "../../interfaces/sky/IPSM3.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../utils/SlippageAccumulatorUser.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

/// @notice Contract guard contract for Sky PDM3
/// @dev As this contract inherits `SlippageAccumulatorUser`, it also inherits the `ITxTrackingGuard` interface.
contract SkyPSM3ContractGuard is TxDataUtils, ITransactionTypes, SlippageAccumulatorUser {
  constructor(address _slippageAccumulator) SlippageAccumulatorUser(_slippageAccumulator) {}

  /// @param _poolManagerLogic Pool manager logic address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes memory _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);

    if (method == IPSM3.swapExactIn.selector || method == IPSM3.swapExactOut.selector) {
      (address assetIn, address assetOut, , , address receiver, ) = abi.decode(
        getParams(_data),
        (address, address, uint256, uint256, address, uint256)
      );

      require(receiver == poolLogic, "recipient is not pool");

      txType = _verifySwap(
        SlippageAccumulator.SwapData({
          srcAsset: assetIn,
          dstAsset: assetOut,
          srcAmount: _getBalance(assetIn, poolLogic),
          dstAmount: _getBalance(assetOut, poolLogic)
        }),
        _poolManagerLogic
      );
    }

    return (txType, false);
  }

  /// @notice This function is called after the transaction is executed
  /// @dev Handles the slippage accumulator update
  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) public override {
    SlippageAccumulatorUser.afterTxGuard(_poolManagerLogic, _to, _data);
  }

  function _verifySwap(
    SlippageAccumulator.SwapData memory _swapData,
    address _poolManagerLogic
  ) internal returns (uint16 txType) {
    require(
      IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_swapData.dstAsset),
      "unsupported destination asset"
    );

    intermediateSwapData = _swapData;

    txType = uint16(TransactionType.Exchange);
  }
}
