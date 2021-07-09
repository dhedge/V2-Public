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
  event SetContractGuard(address extContract, address guardAddress);

  event SetAssetGuard(uint16 assetType, address guardAddress);

  // Transaction Guards

  mapping(address => address) public override contractGuards;
  mapping(uint16 => address) public override assetGuards;

  // Transaction Guards

  function setContractGuard(address extContract, address guardAddress) external onlyOwner {
    _setContractGuard(extContract, guardAddress);
  }

  function _setContractGuard(address extContract, address guardAddress) internal {
    require(extContract != address(0), "Invalid extContract address");
    require(guardAddress != address(0), "Invalid guardAddress");

    contractGuards[extContract] = guardAddress;

    emit SetContractGuard(extContract, guardAddress);
  }

  function setAssetGuard(uint16 assetType, address guardAddress) external onlyOwner {
    _setAssetGuard(assetType, guardAddress);
  }

  function _setAssetGuard(uint16 assetType, address guardAddress) internal {
    require(guardAddress != address(0), "Invalid guardAddress");

    assetGuards[assetType] = guardAddress;

    emit SetAssetGuard(assetType, guardAddress);
  }
}
