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
// Copyright (c) dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/v5/contracts/access/Ownable.sol";
import {AutomationCompatible} from "../utils/chainlink/AutomationCompatible.sol";
import {FluidDexObservationAggregator} from "./FluidDexObservationAggregator.sol";

/// @title Fluid DEX Observation Automation
/// @notice Chainlink Automation compatible contract for multiple FluidDexObservationAggregators
/// @dev Implements custom logic trigger: records observations when price deviates
///      beyond threshold OR when time since last observation exceeds maximum.
///      Aggregator configs are passed via checkData at upkeep registration.
///      This contract's address must be authorized in each aggregator's authorizedKeepers.
contract FluidDexObservationAutomation is Ownable, AutomationCompatible {
  /// @notice Configuration for each aggregator to monitor
  struct AggregatorConfig {
    address aggregator;
    uint256 deviationThresholdBps;
    uint256 maxTimeSinceLastObservation;
  }

  /// @notice Chainlink Automation forwarder address (unique per upkeep)
  address public forwarder;

  error NotForwarder();

  event ForwarderSet(address indexed forwarder);
  event ObservationFailed(address aggregator, bytes reason);

  constructor(address _owner) Ownable(_owner) {}

  /* ========== ADMIN FUNCTIONS ========== */

  /// @notice Set the Chainlink Automation forwarder address
  /// @dev Must be called after upkeep registration with the forwarder address from Chainlink UI
  /// @param _forwarder The forwarder address for this upkeep
  function setForwarder(address _forwarder) external onlyOwner {
    forwarder = _forwarder;
    emit ForwarderSet(_forwarder);
  }

  /* ========== CHAINLINK AUTOMATION ========== */

  /// @notice Check if upkeep is needed for any configured aggregators
  /// @dev checkData = abi.encode(AggregatorConfig[])
  ///      Returns true if any aggregator needs an observation recorded.
  ///      Uses `cannotExecute` modifier to ensure this function is only used for
  ///      off-chain simulation by Chainlink Automation nodes, never executed on-chain.
  /// @param checkData Encoded array of AggregatorConfig structs
  /// @return upkeepNeeded True if at least one aggregator needs update
  /// @return performData Encoded array of aggregator addresses that need updates
  function checkUpkeep(
    bytes calldata checkData
  ) external override cannotExecute returns (bool upkeepNeeded, bytes memory performData) {
    AggregatorConfig[] memory configs = abi.decode(checkData, (AggregatorConfig[]));

    // Allocate max possible size, will trim later
    address[] memory aggregatorsToUpdate = new address[](configs.length);
    uint256 count;

    for (uint256 i; i < configs.length; ++i) {
      if (_needsObservation(configs[i])) {
        aggregatorsToUpdate[count++] = configs[i].aggregator;
      }
    }

    if (count == 0) {
      return (false, "");
    }

    // Trim array to actual size
    assembly {
      mstore(aggregatorsToUpdate, count)
    }

    return (true, abi.encode(aggregatorsToUpdate));
  }

  /// @notice Perform the upkeep for specified aggregators
  /// @dev Only callable by the registered forwarder.
  ///      Each aggregator.recordObservation() has its own protections.
  /// @param performData Encoded array of aggregator addresses to update
  function performUpkeep(bytes calldata performData) external override {
    if (msg.sender != forwarder) revert NotForwarder();

    address[] memory aggregators = abi.decode(performData, (address[]));

    for (uint256 i; i < aggregators.length; ++i) {
      // Use try/catch to prevent one failing aggregator from blocking others
      // Failures are logged and will be retried on next upkeep
      // solhint-disable-next-line no-empty-blocks
      try FluidDexObservationAggregator(aggregators[i]).recordObservation() {} catch (bytes memory reason) {
        emit ObservationFailed(aggregators[i], reason);
      }
    }
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /// @notice Check if a specific aggregator needs an observation recorded
  /// @param config The aggregator configuration
  /// @return needsUpdate True if observation should be recorded
  function _needsObservation(AggregatorConfig memory config) internal returns (bool needsUpdate) {
    // Get latest stored observation
    (uint64 lastTimestamp, uint192 lastPrice) = FluidDexObservationAggregator(config.aggregator).getLatestObservation();

    // If no observations yet, we need to record one
    if (lastTimestamp == 0) {
      return true;
    }

    uint256 timeSinceLast = block.timestamp - lastTimestamp;

    // Don't trigger if minObservationInterval hasn't passed (would revert with ObservationTooSoon)
    if (timeSinceLast < FluidDexObservationAggregator(config.aggregator).minObservationInterval()) {
      return false;
    }

    // Check time-based trigger
    if (timeSinceLast >= config.maxTimeSinceLastObservation) {
      return true;
    }

    // Check deviation-based trigger
    try FluidDexObservationAggregator(config.aggregator).getCurrentPrice() returns (uint256 currentPrice) {
      uint256 priceDiff;
      if (currentPrice > lastPrice) {
        priceDiff = ((currentPrice - lastPrice) * 10000) / lastPrice;
      } else {
        priceDiff = ((lastPrice - currentPrice) * 10000) / lastPrice;
      }

      if (priceDiff >= config.deviationThresholdBps) {
        return true;
      }
      // solhint-disable-next-line no-empty-blocks
    } catch {
      // If getCurrentPrice fails, don't trigger upkeep for this aggregator
    }

    return false;
  }
}
