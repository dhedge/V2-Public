// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {IMigrationHelper} from "../../../interfaces/aave/IMigrationHelper.sol";
import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

contract AaveMigrationHelperGuard is IGuard, ITransactionTypes, TxDataUtils {
  address public immutable aaveLendingPoolV3;

  mapping(address => bool) public dHedgeVaultsWhitelist;

  constructor(address[] memory _whitelistedVaults, address _aaveLendingPoolV3) {
    require(_aaveLendingPoolV3 != address(0), "invalid aaveLendingPoolV3");

    for (uint256 i = 0; i < _whitelistedVaults.length; i++) {
      require(_whitelistedVaults[i] != address(0), "invalid vault address");

      dHedgeVaultsWhitelist[_whitelistedVaults[i]] = true;
    }

    aaveLendingPoolV3 = _aaveLendingPoolV3;
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

    require(dHedgeVaultsWhitelist[poolLogic], "only whitelisted vaults");

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);

    if (method == IMigrationHelper.migrate.selector) {
      require(
        IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(aaveLendingPoolV3),
        "unsupported destination asset"
      );

      txType = uint16(TransactionType.AaveMigrateToV3);
    }

    return (txType, false);
  }
}
