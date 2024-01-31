// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/ramses/IXRam.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/ITransactionTypes.sol";

contract RamsesXRamContractGuard is TxDataUtils, IGuard, ITransactionTypes {
  event CreateVest(address poolLogic, address vestAddress, uint256 amount, uint256 time);
  event ExitVest(address poolLogic, address vestAddress, uint256 vestID, uint256 time);

  /// @notice Transaction guard for xRAM
  /// @notice It supports createVest and exitVest functionalities
  /// @dev Nothing is enforced, manager can either cancel vesting if < 14 days or exit earlier than 90 days
  /// @param _poolManagerLogic the pool manager logic
  /// @param _to the XRam address
  /// @param _data the transaction data
  /// @return txType the transaction type of a given transaction data
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes calldata _data
  ) external override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == IXRam.createVest.selector) {
      uint256 amount = abi.decode(params, (uint256));

      txType = uint16(TransactionType.XRamCreateVest);

      emit CreateVest(poolLogic, _to, amount, block.timestamp);
    } else if (method == IXRam.exitVest.selector) {
      (uint256 vestID, bool ve) = abi.decode(params, (uint256, bool));

      // https://docs.ramses.exchange/ram-tokenomics/xoram/how-is-xoram-used
      require(!ve, "exit to veRAM is not allowed");

      txType = uint16(TransactionType.XRamExitVest);

      emit ExitVest(poolLogic, _to, vestID, block.timestamp);
    }

    return (txType, false);
  }
}
