// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DhedgeNftTrackerStorage} from "../tracker/DhedgeNftTrackerStorage.sol";
import {IGmxDataStore} from "../../interfaces/gmx/IGmxDataStore.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
/**
 * @dev Library for adding, removing and getting claimable collateral time keys
 * use nftTracker to manage storage of claimable collateral time keys
 */
library GmxClaimableCollateralTrackerLib {
  using SafeMath for uint256;
  bytes32 public constant CLAIMABLE_COLLATERAL_AMOUNT = keccak256(abi.encode("CLAIMABLE_COLLATERAL_AMOUNT"));
  bytes32 public constant CLAIMED_COLLATERAL_AMOUNT = keccak256(abi.encode("CLAIMED_COLLATERAL_AMOUNT"));
  bytes32 public constant CLAIMABLE_COLLATERAL_FACTOR = keccak256(abi.encode("CLAIMABLE_COLLATERAL_FACTOR"));
  uint256 public constant FLOAT_PRECISION = 10 ** 30;
  /// @dev Hardcoded limit of claimable collateral time keys
  uint256 public constant MAX_KEY_LIMIT = 1000;

  struct ClaimableCollateralParams {
    address market;
    address token;
    uint256 timeKey;
    address account;
  }

  struct ClaimableCollateralInfo {
    address market;
    address token;
    address account;
  }

  // @dev key for claimable collateral factor for a timeKey
  function claimableCollateralFactorKey(address market, address token, uint256 timeKey) public pure returns (bytes32) {
    return keccak256(abi.encode(CLAIMABLE_COLLATERAL_FACTOR, market, token, timeKey));
  }

  // @dev key for claimable collateral factor for a timeKey for an account
  function claimableCollateralFactorKey(
    address market,
    address token,
    uint256 timeKey,
    address account
  ) public pure returns (bytes32) {
    return keccak256(abi.encode(CLAIMABLE_COLLATERAL_FACTOR, market, token, timeKey, account));
  }

  // use [CLAIMABLE_COLLATERAL_AMOUNT, market, token] as key in the tracker to store the timeKey
  function claimableCollateralAmountKey(address market, address token) public pure returns (bytes32) {
    return keccak256(abi.encode(CLAIMABLE_COLLATERAL_AMOUNT, market, token));
  }

  // key to retrieve claimable collateral amount
  function claimableCollateralAmountKey(ClaimableCollateralParams memory params) public pure returns (bytes32) {
    return
      keccak256(abi.encode(CLAIMABLE_COLLATERAL_AMOUNT, params.market, params.token, params.timeKey, params.account));
  }

  // key to retrieve claimed collateral amount
  function claimedCollateralAmountKey(ClaimableCollateralParams memory params) public pure returns (bytes32) {
    return
      keccak256(abi.encode(CLAIMED_COLLATERAL_AMOUNT, params.market, params.token, params.timeKey, params.account));
  }

  function isExistingClaimableCollateralTimeKey(
    address nftTracker,
    address pool,
    address market,
    address token,
    uint256 timeKey
  ) public view returns (bool) {
    bytes32 nftType = claimableCollateralAmountKey(market, token);
    uint256[] memory allTimekeys = DhedgeNftTrackerStorage(nftTracker).getAllUintIds(nftType, pool);
    uint256 i;
    for (i = 0; i < allTimekeys.length; i++) {
      if (timeKey == allTimekeys[i]) {
        return true;
      }
    }
    return false;
  }

  // to store claimable collateral time key
  function addClaimableCollateralTimeKey(
    address nftTracker,
    address guardedContract,
    address pool,
    address market,
    address token,
    uint256 timeKey
  ) external {
    bytes32 nftType = claimableCollateralAmountKey(market, token);
    bool isKeyAdded = isExistingClaimableCollateralTimeKey(nftTracker, pool, market, token, timeKey);
    if (!isKeyAdded) {
      DhedgeNftTrackerStorage(nftTracker).addUintId({
        _guardedContract: guardedContract,
        _nftType: nftType, // key, hash of [CLAIMABLE_COLLATERAL_AMOUNT, market, token]
        _pool: pool, // for the poolLogic
        _nftID: timeKey, // value, timeKey
        _maxPositions: MAX_KEY_LIMIT
      });
    }
  }

  // to remove claimable collateral time key
  function removeClaimableCollateralTimeKey(
    address nftTracker,
    address guardedContract,
    ClaimableCollateralParams memory params
  ) internal {
    bytes32 nftType = claimableCollateralAmountKey(params.market, params.token);
    bool isKeyExisting = isExistingClaimableCollateralTimeKey(
      nftTracker,
      params.account,
      params.market,
      params.token,
      params.timeKey
    );
    if (isKeyExisting) {
      DhedgeNftTrackerStorage(nftTracker).removeUintId(guardedContract, nftType, params.account, params.timeKey);
    }
  }

  /// all the claimableAmount will be claimed eventually
  /// toBeClaimedAmount claimed by claimCollateral function is different from calculated claimable amount
  /// depending on the claimableCollateralFactorKey, which is 0 to start with, as it can not be claimed at the beginning
  function getCalculatedClaimableAmountByTimeKey(
    address dataStore,
    ClaimableCollateralParams memory params
  ) public view returns (uint256) {
    uint256 claimableAmount = IGmxDataStore(dataStore).getUint(claimableCollateralAmountKey(params));
    uint256 claimedAmount = IGmxDataStore(dataStore).getUint(claimedCollateralAmountKey(params));

    if (claimableAmount >= claimedAmount) {
      return claimableAmount.sub(claimedAmount);
    }
    return 0;
  }

  function getAllClaimableCollateralTimeKeys(
    address nftTracker,
    ClaimableCollateralInfo memory params
  ) public view returns (uint256[] memory) {
    bytes32 nftType = claimableCollateralAmountKey(params.market, params.token);
    return DhedgeNftTrackerStorage(nftTracker).getAllUintIds(nftType, params.account);
  }

  function getTotalClaimableAmount(
    address nftTracker,
    address dataStore,
    ClaimableCollateralInfo memory params
  ) external view returns (uint256 totalClaimableAmount) {
    uint256[] memory timeKeys = getAllClaimableCollateralTimeKeys(nftTracker, params);
    for (uint256 i = 0; i < timeKeys.length; i++) {
      totalClaimableAmount = totalClaimableAmount.add(
        getCalculatedClaimableAmountByTimeKey(
          dataStore,
          ClaimableCollateralParams({
            market: params.market,
            token: params.token,
            timeKey: timeKeys[i],
            account: params.account
          })
        )
      );
    }
  }

  function cleanUpClaimableCollateralTimeKey(
    address nftTracker,
    address dataStore,
    address guardedContract,
    ClaimableCollateralParams memory params
  ) external {
    uint256 claimAmount = getCalculatedClaimableAmountByTimeKey(dataStore, params);
    if (claimAmount == 0) {
      removeClaimableCollateralTimeKey(nftTracker, guardedContract, params);
    }
  }
}
