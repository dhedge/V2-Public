//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {InitializableUpgradeabilityProxy} from "./InitializableUpgradeabilityProxy.sol";
import {HasLogic} from "./HasLogic.sol";

/// @notice This contract is used to deploy the proxy contract.
contract ProxyFactory is OwnableUpgradeable, HasLogic {
  event ProxyCreated(address proxy);

  address private poolLogic;

  address private poolManagerLogic;

  /// @notice initialise poolLogic and poolManagerLogic
  /// @param _poolLogic address of the pool logic
  /// @param _poolManagerLogic address of the pool manager logic
  // solhint-disable-next-line func-name-mixedcase
  function __ProxyFactory_init(address _poolLogic, address _poolManagerLogic) internal {
    __Ownable_init();

    require(_poolLogic != address(0), "Invalid poolLogic");
    require(_poolManagerLogic != address(0), "Invalid poolManagerLogic");

    poolLogic = _poolLogic;
    poolManagerLogic = _poolManagerLogic;
  }

  /// @notice Setting logic address for both poolLogic and poolManagerLogic
  /// @param _poolLogic address of the pool logic
  /// @param _poolManagerLogic address of the pool manager logic
  function setLogic(address _poolLogic, address _poolManagerLogic) external onlyOwner {
    require(_poolLogic != address(0), "Invalid poolLogic");
    require(_poolManagerLogic != address(0), "Invalid poolManagerLogic");

    poolLogic = _poolLogic;
    poolManagerLogic = _poolManagerLogic;
  }

  /// @notice Return logic address of the pool or the pool manager logic
  /// @param _proxyType type of the proxy, 1 for pool manager, 2 for pool
  /// @return address of the logic contract
  function getLogic(uint8 _proxyType) external view override returns (address) {
    if (_proxyType == 1) {
      return poolManagerLogic;
    } else {
      return poolLogic;
    }
  }

  /// @notice Deploy proxy contract external call
  /// @param _data initialization data for the proxy contract
  /// @param _proxyType type of the proxy, 1 for pool manager, 2 for pool
  /// @return address of the deployed proxy contract
  function deploy(bytes memory _data, uint8 _proxyType) public returns (address) {
    return _deployProxy(_data, _proxyType);
  }

  function _deployProxy(bytes memory _data, uint8 _proxyType) internal returns (address) {
    InitializableUpgradeabilityProxy proxy = _createProxy();
    emit ProxyCreated(address(proxy));
    proxy.initialize(address(this), _data, _proxyType);
    return address(proxy);
  }

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

  uint256[50] private __gap;
}
