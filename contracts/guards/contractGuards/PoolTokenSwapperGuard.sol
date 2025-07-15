// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGuard} from "../../interfaces/guards/IGuard.sol";
import {ITransactionTypes} from "../../interfaces/ITransactionTypes.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";
import {IPoolManagerLogic} from "../../interfaces/IPoolManagerLogic.sol";
import {PoolTokenSwapper} from "../../swappers/poolTokenSwapper/PoolTokenSwapper.sol";
import {SlippageAccumulator, SlippageAccumulatorUser} from "../../utils/SlippageAccumulatorUser.sol";

/// @title Transaction guard for dHEDGE PoolTokenSwapper contract
contract PoolTokenSwapperGuard is TxDataUtils, IGuard, ITransactionTypes, SlippageAccumulatorUser {
  constructor(address _slippageAccumulator) SlippageAccumulatorUser(_slippageAccumulator) {}

  /// @notice Allows dHEDGE pool managers to use swap to rebalance their portfolio
  /// @dev PoolTokenSwapper whitelists pools that can call swap
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address,
    bytes calldata _data
  ) external override returns (uint16 txType, bool isPublic) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);

    if (method == PoolTokenSwapper.swap.selector) {
      (address tokenIn, address tokenOut) = abi.decode(getParams(_data), (address, address));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenOut), "unsupported destination asset");

      intermediateSwapData = SlippageAccumulator.SwapData({
        srcAsset: tokenIn,
        dstAsset: tokenOut,
        srcAmount: _getBalance(tokenIn, poolLogic),
        dstAmount: _getBalance(tokenOut, poolLogic)
      });

      txType = uint16(TransactionType.Exchange);
      isPublic = false;
    }

    return (txType, isPublic);
  }
}
