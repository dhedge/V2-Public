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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IGovernance.sol";

/// @title Governance
/// @dev A contract with storage managed by governance
contract Governance is IGovernance, Ownable {
  event ContractGuardSet(address extContract, address guardAddress);
  event AssetGuardSet(uint8 assetType, address guardAddress);
  event AddressSet(bytes32 name, address destination);

  // Transaction Guards
  mapping(address => address) public override contractGuards;
  mapping(uint8 => address) public override assetGuards;

  // Addresses
  mapping(bytes32 => address) public nameToDestination;

  /* ========== RESTRICTED FUNCTIONS ========== */

  // Transaction Guards

  function setContractGuard(address extContract, address guardAddress) external onlyOwner {
    _setContractGuard(extContract, guardAddress);
  }

  function _setContractGuard(address extContract, address guardAddress) internal {
    require(extContract != address(0), "Invalid extContract address");
    require(guardAddress != address(0), "Invalid guardAddress");

    contractGuards[extContract] = guardAddress;

    emit ContractGuardSet(extContract, guardAddress);
  }

  function setAssetGuard(uint8 assetType, address guardAddress) external onlyOwner {
    _setAssetGuard(assetType, guardAddress);
  }

  function _setAssetGuard(uint8 assetType, address guardAddress) internal {
    require(guardAddress != address(0), "Invalid guardAddress");

    assetGuards[assetType] = guardAddress;

    emit AssetGuardSet(assetType, guardAddress);
  }

  // Addresses

  function setAddresses(bytes32[] calldata names, address[] calldata destinations) external onlyOwner {
    require(names.length == destinations.length, "input lengths must match");

    for (uint256 i = 0; i < names.length; i++) {
      bytes32 name = names[i];
      address destination = destinations[i];
      nameToDestination[name] = destination;
      emit AddressSet(name, destination);
    }
  }

  /* ========== VIEWS ========== */

  function areAddressesSet(bytes32[] calldata names, address[] calldata destinations) external view returns (bool) {
    require(names.length == destinations.length, "input lengths must match");

    for (uint256 i = 0; i < names.length; i++) {
      if (nameToDestination[names[i]] != destinations[i]) {
        return false;
      }
    }
    return true;
  }

  function getAddress(bytes32 name) external view override returns (address destination) {
    destination = nameToDestination[name];
    require(destination != address(0), "governance: invalid name");
  }
}
