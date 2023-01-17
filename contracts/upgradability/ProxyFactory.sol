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
// Copyright (c) 2021 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "./InitializableUpgradeabilityProxy.sol";
import "./HasLogic.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

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
  function setLogic(address _poolLogic, address _poolManagerLogic) public onlyOwner {
    require(_poolLogic != address(0), "Invalid poolLogic");
    require(_poolManagerLogic != address(0), "Invalid poolManagerLogic");

    poolLogic = _poolLogic;
    poolManagerLogic = _poolManagerLogic;
  }

  /// @notice Return logic address of the pool or the pool manager logic
  function getLogic(uint8 _proxyType) public view override returns (address) {
    if (_proxyType == 1) {
      return poolManagerLogic;
    } else {
      return poolLogic;
    }
  }

  /// @notice Deploy proxy contract external call
  function deploy(bytes memory _data, uint8 _proxyType) public returns (address) {
    return _deployProxy(_data, _proxyType);
  }

  /// @notice Deploy and initialize proxy contract internal call
  function _deployProxy(bytes memory _data, uint8 _proxyType) internal returns (address) {
    InitializableUpgradeabilityProxy proxy = _createProxy();
    emit ProxyCreated(address(proxy));
    proxy.initialize(address(this), _data, _proxyType);
    return address(proxy);
  }

  /// @notice Deploy proxy contract
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
