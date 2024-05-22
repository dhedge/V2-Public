// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ICreditDelegationToken} from "./ICreditDelegationToken.sol";

/**
 * @title IMigrationHelper
 * @author BGD Labs
 * @notice Defines the interface for the contract to migrate positions from Aave v2 to Aave v3 pool
 **/
interface IMigrationHelper {
  struct PermitInput {
    address aToken; // should be IERC20WithPermit
    uint256 value;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  struct CreditDelegationInput {
    ICreditDelegationToken debtToken;
    uint256 value;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  struct RepaySimpleInput {
    address asset;
    uint256 rateMode;
  }

  /**
   * @notice Method to do migration of any types of positions. Migrating whole amount of specified assets
   * @param assetsToMigrate - list of assets to migrate
   * @param positionsToRepay - list of assets to be repayed
   * @param permits - list of EIP712 permits, can be empty, if approvals provided in advance
   * @param creditDelegationPermits - list of EIP712 signatures (credit delegations) for v3 variable debt token
   * @dev check more details about permit at PermitInput and /solidity-utils/contracts/oz-common/interfaces/draft-IERC20Permit.sol
   **/
  function migrate(
    address[] memory assetsToMigrate,
    RepaySimpleInput[] memory positionsToRepay,
    PermitInput[] memory permits,
    CreditDelegationInput[] memory creditDelegationPermits
  ) external;
}
