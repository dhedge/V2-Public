// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/velodrome/IVelodromePair.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/ITransactionTypes.sol";

contract VelodromePairContractGuard is TxDataUtils, IGuard, ITransactionTypes {
  /// @notice Transaction guard for Velodrome V1 or V2 Pair
  /// @dev It supports claiming fees
  /// @param _poolManagerLogic the pool manager logic
  /// @param _to the liquidity pair address
  /// @param _data the transaction data
  /// @return txType the transaction type of a given transaction data
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes calldata _data
  ) external override returns (uint16 txType, bool isPublic) {
    bytes4 method = getMethod(_data);

    if (method == IVelodromePair.claimFees.selector) {
      emit Claim(IPoolManagerLogic(_poolManagerLogic).poolLogic(), _to, block.timestamp);

      txType = uint16(TransactionType.Claim);
      isPublic = true;
    }

    return (txType, isPublic);
  }
}
