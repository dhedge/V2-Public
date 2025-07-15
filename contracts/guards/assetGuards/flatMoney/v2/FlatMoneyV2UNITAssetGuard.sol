// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {FlatMoneyBasisContractGuard} from "../../../contractGuards/flatMoney/shared/FlatMoneyBasisContractGuard.sol";
import {IAddAssetCheckGuard} from "../../../../interfaces/guards/IAddAssetCheckGuard.sol";
import {IStableModule} from "../../../../interfaces/flatMoney/IStableModule.sol";
import {IHasGuardInfo} from "../../../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../../../interfaces/IPoolLogic.sol";
import {FlatcoinModuleKeys} from "../../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {ERC20Guard} from "../../ERC20Guard.sol";
import {FlatMoneyV2OrderHelperGuard} from "./FlatMoneyV2OrderHelperGuard.sol";

/// @notice AssetType - 35
/// @dev `removeAssetCheck` from inherited contract will also revert in case of pending order, because
/// @dev `getBalance` from derived contract overrides the one from ERC20Guard.
/// @dev This will prevent the scenario when deposit/withdraw order is announced and manager can disable corresponding asset.
contract FlatMoneyV2UNITAssetGuard is FlatMoneyV2OrderHelperGuard, ERC20Guard, IAddAssetCheckGuard {
  bool public override isAddAssetCheckGuard = true;

  /// @notice Returns the balance of the UNIT asset in the vault.
  /// @dev Logic is the same as for regular ERC20 tokens, but reverts in case there is a pending order.
  /// @dev Revert is required because once order is opened, value of the vault is transferred out,
  /// @dev but there is always a delay before order is executed and the value is received back.
  /// @dev During order execution deposits as well as withdrawals at lower tokenPrice are possible, thus revert is required.
  /// @param _pool Vault address
  /// @param _asset UNIT asset address
  /// @return balance Balance of the UNIT asset in the vault
  function getBalance(address _pool, address _asset) public view override returns (uint256 balance) {
    require(_hasNoBlockingOrder(_pool, _asset), "order in progress");

    return super.getBalance(_pool, _asset);
  }

  function addAssetCheck(address _poolLogic, IHasSupportedAsset.Asset calldata _supportedAsset) external view override {
    address orderAnnouncementModule = IStableModule(_supportedAsset.asset).vault().moduleAddress(
      FlatcoinModuleKeys._ORDER_ANNOUNCEMENT_MODULE_KEY
    );
    FlatMoneyBasisContractGuard contractGuard = FlatMoneyBasisContractGuard(
      IHasGuardInfo(IPoolLogic(_poolLogic).factory()).getContractGuard(orderAnnouncementModule)
    );
    (address poolLogic, ) = contractGuard.dHedgePoolsWhitelist(_poolLogic);
    require(poolLogic == _poolLogic, "not whitelisted");
  }
}
