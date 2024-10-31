// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {HasLogic} from "../../upgradability/HasLogic.sol";
import {InitializableUpgradeabilityProxy} from "../../upgradability/InitializableUpgradeabilityProxy.sol";

contract VaultProxyFactory is OwnableUpgradeable, HasLogic {
  address private vaultLogic;

  event ProxyCreated(address proxy);

  /// @param _vaultLogic WithdrawalVault address
  // solhint-disable-next-line func-name-mixedcase
  function __VaultProxyFactory_init(address _vaultLogic) internal {
    __Ownable_init();

    require(_vaultLogic != address(0), "invalid address");

    vaultLogic = _vaultLogic;
  }

  /// @notice Setting logic address for WithdrawalVault
  /// @param _vaultLogic WithdrawalVault address
  function setLogic(address _vaultLogic) external onlyOwner {
    require(_vaultLogic != address(0), "invalid address");

    vaultLogic = _vaultLogic;
  }

  /// @notice Return logic address of WithdrawalVault
  /// @return Address of WithdrawalVault
  function getLogic(uint8) public view override returns (address) {
    return vaultLogic;
  }

  /// @notice Init proxy contract
  /// @param _data Initialization data
  /// @return Address of the new proxy
  function _deploy(bytes memory _data) internal returns (address) {
    InitializableUpgradeabilityProxy proxy = _createProxy();

    emit ProxyCreated(address(proxy));

    proxy.initialize(address(this), _data, 1);

    return address(proxy);
  }

  /// @notice Deploy proxy contract
  /// @return Address of the new proxy
  function _createProxy() internal returns (InitializableUpgradeabilityProxy) {
    address payable addr;
    bytes memory code = type(InitializableUpgradeabilityProxy).creationCode;

    assembly {
      addr := create(0, add(code, 0x20), mload(code))
      if iszero(extcodesize(addr)) {
        revert(0, 0)
      }
    }

    return InitializableUpgradeabilityProxy(addr);
  }

  uint256[49] private __gap;
}
