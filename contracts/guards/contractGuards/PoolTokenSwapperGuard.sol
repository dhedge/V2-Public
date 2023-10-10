// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/ITransactionTypes.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../utils/TxDataUtils.sol";

/// @title Transaction guard for dHEDGE PoolTokenSwapper contract
contract PoolTokenSwapperGuard is TxDataUtils, IGuard, ITransactionTypes {
  /// @notice Allows dHEDGE pool managers to use swap to rebalance their portfolio
  /// @dev PoolTokenSwapper whitelists pools that can call swap
  /// @dev TODO: Once opened for anyone, add a slippage check
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address,
    bytes calldata _data
  ) external override returns (uint16 txType, bool) {
    bytes4 method = getMethod(_data);

    if (method == bytes4(keccak256("swap(address,address,uint256,uint256)"))) {
      (address tokenIn, address tokenOut, uint256 amountIn) = abi.decode(getParams(_data), (address, address, uint256));

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(tokenOut), "unsupported destination asset");

      txType = uint16(TransactionType.Exchange);

      emit ExchangeFrom(IPoolManagerLogic(_poolManagerLogic).poolLogic(), tokenIn, amountIn, tokenOut, block.timestamp);
    }

    return (txType, false);
  }
}
