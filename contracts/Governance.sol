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
pragma experimental ABIEncoderV2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGovernance} from "./interfaces/IGovernance.sol";

/// @title Governance
/// @dev A contract with storage managed by governance
contract Governance is IGovernance, Ownable {
  event ContractGuardSet(address extContract, address guardAddress);
  event AssetGuardSet(uint16 assetType, address guardAddress);

  // Transaction Guards
  mapping(address => address) public override contractGuards;
  mapping(uint16 => address) public override assetGuards;

  /* ========== RESTRICTED FUNCTIONS ========== */

  // Transaction Guards

  /// @notice Maps an exernal contract to a guard which enables managers to use the contract
  /// @param extContract The third party contract to integrate
  /// @param guardAddress The protections for manager third party contract interaction
  function setContractGuard(address extContract, address guardAddress) external onlyOwner {
    _setContractGuard(extContract, guardAddress);
  }

  /// @notice Set contract guard internal call
  /// @param extContract The third party contract to integrate
  /// @param guardAddress The protections for manager third party contract interaction
  function _setContractGuard(address extContract, address guardAddress) internal {
    require(extContract != address(0), "Invalid extContract address");
    require(guardAddress != address(0), "Invalid guardAddress");

    contractGuards[extContract] = guardAddress;

    emit ContractGuardSet(extContract, guardAddress);
  }

  /// @notice Maps an asset type to an asset guard which allows managers to enable the asset
  /// @dev Asset types are defined in AssetHandler.sol
  /// @param assetType Asset type as defined in Asset Handler
  /// @param guardAddress The asset guard address that allows manager interaction
  function setAssetGuard(uint16 assetType, address guardAddress) external onlyOwner {
    _setAssetGuard(assetType, guardAddress);
  }

  /// @notice Set asset guard internal call
  /// @param assetType Asset type as defined in Asset Handler
  /// @param guardAddress The asset guard address that allows manager interaction
  function _setAssetGuard(uint16 assetType, address guardAddress) internal {
    require(guardAddress != address(0), "Invalid guardAddress");

    assetGuards[assetType] = guardAddress;

    emit AssetGuardSet(assetType, guardAddress);
  }
}
