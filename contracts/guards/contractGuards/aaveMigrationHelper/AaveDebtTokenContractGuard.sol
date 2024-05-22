// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {ICreditDelegationToken} from "../../../interfaces/aave/ICreditDelegationToken.sol";
import {IAaveMigrationHelperGuard} from "../../../interfaces/aave/IAaveMigrationHelperGuard.sol";
import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

contract AaveDebtTokenContractGuard is IGuard, ITransactionTypes, TxDataUtils {
  address public immutable migrationHelper;

  constructor(address _migrationHelper) {
    require(_migrationHelper != address(0), "invalid migrationHelper");

    migrationHelper = _migrationHelper;
  }

  /// @param _poolManagerLogic Address of the PoolManagerLogic contract
  /// @param _data Transaction data payload
  /// @return txType The transaction type of a given transaction data
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes memory _data
  ) external view override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    IAaveMigrationHelperGuard coreContractGuard = IAaveMigrationHelperGuard(
      IHasGuardInfo(IPoolLogic(poolLogic).factory()).getContractGuard(migrationHelper)
    );

    require(coreContractGuard.dHedgeVaultsWhitelist(poolLogic), "only whitelisted vaults");

    bytes4 method = getMethod(_data);

    if (method == ICreditDelegationToken.approveDelegation.selector) {
      bytes memory params = getParams(_data);

      address delegatee = abi.decode(params, (address));

      require(delegatee == migrationHelper, "invalid delegatee");

      txType = uint16(TransactionType.Approve);
    }

    return (txType, false);
  }
}
