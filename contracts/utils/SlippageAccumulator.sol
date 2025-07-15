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
pragma abicoder v2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";

import {IERC20Extended} from "../interfaces/IERC20Extended.sol";
import {IHasAssetInfo} from "../interfaces/IHasAssetInfo.sol";
import {IHasGuardInfo} from "../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../interfaces/IHasSupportedAsset.sol";

/// @notice Contract to check for accumulated slippage impact for a pool manager.
/// @author dHEDGE
contract SlippageAccumulator is Ownable {
  using SafeMath for *;
  using Math for *;
  using SafeCast for *;

  /// @dev Struct for passing swap related data to the slippage accumulator function.
  /// @param srcAsset Source asset (asset to be exchanged).
  /// @param dstAsset Destination asset (asset being exchanged for).
  /// @param srcAmount Source asset amount.
  /// @param dstAmount Destination asset amount.
  struct SwapData {
    address srcAsset;
    address dstAsset;
    uint256 srcAmount;
    uint256 dstAmount;
  }

  /// @dev Struct to track the slippage data for a poolManager.
  /// @param lastTradeTimestamp Last successful trade's timestamp.
  /// @param accumulatedSlippage The accumulated slippage impact of a poolManager.
  struct ManagerSlippageData {
    uint64 lastTradeTimestamp;
    uint128 accumulatedSlippage;
  }

  event DecayTimeChanged(uint64 oldDecayTime, uint64 newDecayTime);
  event MaxCumulativeSlippageChanged(uint128 oldMaxCumulativeSlippage, uint128 newMaxCumulativeSlippage);

  /// @dev Constant used to multiply the slippage loss percentage with 4 decimal precision.
  uint128 private constant SCALING_FACTOR = 1e6;

  /// @dev dHEDGE poolFactory address.
  address private immutable poolFactory;

  /// @notice Maximum acceptable cumulative trade slippage impact within a period of time (upto 4 decimal precision).
  /// @dev Eg. 5% = 5e4
  uint128 public maxCumulativeSlippage;

  /// @notice Price accumulator decay time.
  /// @dev Eg 6 hours = 21600.
  uint64 public decayTime;

  /// @notice Tracks the last trade timestamp and accumulated slippage for each poolManager.
  mapping(address => ManagerSlippageData) public managerData;

  /// @dev Modifier to make sure caller is a contract guard.
  modifier onlyContractGuard(address to) {
    address contractGuard = IHasGuardInfo(poolFactory).getContractGuard(to);

    require(contractGuard == msg.sender, "Not authorised guard");
    _;
  }

  constructor(address _poolFactory, uint64 _decayTime, uint128 _maxCumulativeSlippage) {
    require(_poolFactory != address(0), "Null address");

    poolFactory = _poolFactory;
    decayTime = _decayTime;
    maxCumulativeSlippage = _maxCumulativeSlippage;
  }

  /// @notice Updates the cumulative slippage impact and reverts if it's beyond limit.
  /// @dev NOTE: It's important that the calling guard checks if the msg.sender in it's scope is authorised.
  /// @dev If the caller is not checked for in the guard, anyone can trigger the `txGuard` transaction and update slippage impact.
  /// @param poolManagerLogic Address of the poolManager whose cumulative impact is stored.
  /// @param router Address of the router contract used for swapping.
  /// @param swapData Common swap data for all guards.
  function updateSlippageImpact(
    address poolManagerLogic,
    address router,
    SwapData calldata swapData
  ) external onlyContractGuard(router) {
    if (IHasSupportedAsset(poolManagerLogic).isSupportedAsset(swapData.srcAsset)) {
      uint256 srcValue = assetValue(swapData.srcAsset, swapData.srcAmount);
      uint256 dstValue = assetValue(swapData.dstAsset, swapData.dstAmount);

      // Only update the cumulative slippage in case the amount received is lesser than amount sent/traded.
      if (dstValue < srcValue) {
        uint128 newSlippage = srcValue.sub(dstValue).mul(SCALING_FACTOR).div(srcValue).toUint128();

        uint128 newCumulativeSlippage = (uint256(newSlippage).add(getCumulativeSlippageImpact(poolManagerLogic)))
          .toUint128();

        require(newCumulativeSlippage < maxCumulativeSlippage, "slippage impact exceeded");

        // Update the last traded timestamp.
        managerData[poolManagerLogic].lastTradeTimestamp = (block.timestamp).toUint64();

        // Update the accumulated slippage impact for the poolManager.
        managerData[poolManagerLogic].accumulatedSlippage = newCumulativeSlippage;
      }
    }
  }

  /// Function to calculate an asset amount's value in usd.
  /// @param asset The asset whose price oracle exists.
  /// @param amount The amount of the `asset`.
  function assetValue(address asset, uint256 amount) public view returns (uint256 value) {
    value = amount.mul(IHasAssetInfo(poolFactory).getAssetPrice(asset)).div(10 ** IERC20Extended(asset).decimals()); // to USD amount
  }

  /// @notice Function to get the cumulative slippage adjusted using decayTime (current cumulative slippage impact).
  /// @param poolManagerLogic Address of the poolManager whose cumulative impact is stored.
  function getCumulativeSlippageImpact(address poolManagerLogic) public view returns (uint128 cumulativeSlippage) {
    ManagerSlippageData memory managerSlippageData = managerData[poolManagerLogic];

    return
      (
        uint256(managerSlippageData.accumulatedSlippage)
          .mul(decayTime.sub(decayTime.min(block.timestamp.sub(managerSlippageData.lastTradeTimestamp))))
          .div(decayTime)
      ).toUint128();
  }

  /**********************************************
   *             Owner Functions                *
   *********************************************/

  /// @notice Function to change decay time for calculating price impact.
  /// @param newDecayTime The new decay time (in seconds).
  function setDecayTime(uint64 newDecayTime) external onlyOwner {
    uint64 oldDecayTime = decayTime;

    decayTime = newDecayTime;

    emit DecayTimeChanged(oldDecayTime, newDecayTime);
  }

  /// @notice Function to change the max acceptable cumulative slippage impact.
  /// @param newMaxCumulativeSlippage The new max acceptable cumulative slippage impact.
  function setMaxCumulativeSlippage(uint128 newMaxCumulativeSlippage) external onlyOwner {
    uint128 oldMaxCumulativeSlippage = maxCumulativeSlippage;

    maxCumulativeSlippage = newMaxCumulativeSlippage;

    emit MaxCumulativeSlippageChanged(oldMaxCumulativeSlippage, newMaxCumulativeSlippage);
  }
}
