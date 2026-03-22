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

pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/v5/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IManaged} from "../interfaces/IManaged.sol";
import {IPoolLogic} from "../interfaces/IPoolLogic.sol";
import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IReferralManager} from "../interfaces/IReferralManager.sol";

/// @title ReferralManager
/// @author dHEDGE team
/// @notice Manages referral fee share percentages for vaults and managers
/// @dev Singleton contract - one instance is set in PoolFactory.
///      The referrer wallet is not stored here - it is passed directly by the depositor
///      when calling deposit functions. Any address can receive referral fees if the
///      manager has enabled a non-zero share percentage.
contract ReferralManager is Initializable, IReferralManager {
  // ========== CONSTANTS ==========

  /// @notice Maximum allowed share (100% = 10_000 basis points)
  uint256 public constant MAX_SHARE = 10_000;

  // ========== STATE ==========

  /// @notice PoolFactory address for access control (vault ownership verification)
  IPoolFactory public poolFactory;

  /// @notice Referral share for a specific vault (vault => shareNumerator)
  mapping(address vault => uint256 shareNumerator) public vaultReferralShare;

  /// @notice Default referral share for all vaults managed by a manager (manager => shareNumerator)
  mapping(address manager => uint256 shareNumerator) public managerReferralShare;

  // ========== EVENTS ==========

  /// @notice Emitted when a vault-level referral share is set
  /// @param vault The vault (PoolLogic) address
  /// @param shareNumerator The share numerator in basis points
  event VaultReferralShareSet(address indexed vault, uint256 shareNumerator);

  /// @notice Emitted when a manager-level global referral share is set
  /// @param manager The manager address
  /// @param shareNumerator The share numerator in basis points
  event ManagerReferralShareSet(address indexed manager, uint256 shareNumerator);

  // ========== ERRORS ==========

  error NotValidVault(address vault);
  error NotVaultManager(address caller, address vault);
  error InvalidFactory();
  error ShareTooHigh(uint256 provided, uint256 max);

  // ========== MODIFIERS ==========

  /// @dev Ensures msg.sender is the manager of the given vault
  modifier onlyVaultManager(address _vault) {
    _checkVaultManager(_vault);
    _;
  }

  // ========== INITIALIZATION ==========

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the ReferralManager with the PoolFactory address
  /// @param _poolFactory The PoolFactory contract used for vault validation
  function initialize(IPoolFactory _poolFactory) external initializer {
    if (address(_poolFactory) == address(0)) revert InvalidFactory();
    poolFactory = _poolFactory;
  }

  // ========== SETTERS ==========

  /// @notice Set the referral share for a specific vault
  /// @dev Only callable by the vault's manager
  /// @param _vault The vault (PoolLogic) address
  /// @param _shareNumerator The share numerator in basis points (0 to disable, max MAX_SHARE)
  function setVaultReferralShare(address _vault, uint256 _shareNumerator) external onlyVaultManager(_vault) {
    _validateShare(_shareNumerator);
    vaultReferralShare[_vault] = _shareNumerator;
    emit VaultReferralShareSet(_vault, _shareNumerator);
  }

  /// @notice Set a global default referral share for all vaults managed by the caller
  /// @dev This is used as a fallback when no vault-specific share is set
  /// @param _shareNumerator The share numerator in basis points (0 to disable, max MAX_SHARE)
  function setManagerReferralShare(uint256 _shareNumerator) external {
    _validateShare(_shareNumerator);
    managerReferralShare[msg.sender] = _shareNumerator;
    emit ManagerReferralShareSet(msg.sender, _shareNumerator);
  }

  // ========== GETTERS ==========

  /// @notice Get the referral share for a vault
  /// @dev Resolution: vault-specific share takes priority, then manager's global default, then 0
  /// @param _vault The vault (PoolLogic) address
  /// @param _manager The manager address (used for fallback to manager's global share)
  /// @return shareNumerator The share numerator in basis points
  function getReferralShare(address _vault, address _manager) external view override returns (uint256 shareNumerator) {
    // Check vault-specific share first
    shareNumerator = vaultReferralShare[_vault];
    if (shareNumerator > 0) {
      return shareNumerator;
    }

    // Fall back to manager's global default
    shareNumerator = managerReferralShare[_manager];
  }

  // ========== INTERNAL ==========

  /// @dev Validates share is within bounds
  function _validateShare(uint256 _shareNumerator) internal pure {
    if (_shareNumerator > MAX_SHARE) revert ShareTooHigh(_shareNumerator, MAX_SHARE);
  }

  /// @dev Validates that the vault is registered in PoolFactory and caller is its manager
  /// @param _vault The vault (PoolLogic) address to check
  function _checkVaultManager(address _vault) internal view {
    if (!poolFactory.isPool(_vault)) revert NotValidVault(_vault);
    address poolManagerLogic = IPoolLogic(_vault).poolManagerLogic();
    if (msg.sender != IManaged(poolManagerLogic).manager()) revert NotVaultManager(msg.sender, _vault);
  }
}
