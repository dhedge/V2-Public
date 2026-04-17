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

import {PrecompileHelper} from "./PrecompileHelper.sol";

/// @dev Thanks to Cain O'Sullivan from Hyperdrive for the inflight tracking logic.
///      <https://discord.com/channels/1029781241702129716/1262879465503981672/1438415636006174781>
abstract contract InFlightTracker is PrecompileHelper {
  /////////////////////////////////////////////
  //                Structs                  //
  /////////////////////////////////////////////

  /// @param inFlightCompositeBlockNumber The composition of EVM block number and HyperCore block number
  ///        when the tokens were bridged to HyperCore.
  /// @param amount The amount of tokens in flight.
  struct InFlightTrackingData {
    uint256 inFlightCompositeBlockNumber;
    uint256 amount;
  }

  /////////////////////////////////////////////
  //                 State                   //
  /////////////////////////////////////////////

  /// @notice Mapping to track in-flight tokens per pool and asset between HyperEVM and HyperCore.
  /// @dev pool => asset => InFlightTrackingData
  mapping(address => mapping(address => InFlightTrackingData)) public inFlightData;

  /////////////////////////////////////////////
  //                Functions                //
  /////////////////////////////////////////////

  /// @notice Updates the in-flight tracking data when tokens are bridged to HyperCore.
  /// @param pool The address of the pool.
  /// @param asset The system address of the spot asset on HyperCore.
  /// @param amount The amount of tokens bridged to HyperCore.
  function trackInFlightToCore(address pool, address asset, uint256 amount) internal {
    InFlightTrackingData storage trackingData = inFlightData[pool][asset];
    uint256 currentCompositeBlockNumber = _composeBlockNumber();

    if (trackingData.inFlightCompositeBlockNumber != currentCompositeBlockNumber) {
      trackingData.inFlightCompositeBlockNumber = currentCompositeBlockNumber;
      trackingData.amount = amount;
    } else {
      trackingData.amount = trackingData.amount + amount;
    }
  }

  /// @notice Retrieves the amount of tokens currently in flight for a given pool and asset.
  /// @param pool The address of the pool.
  /// @param asset The system address of the spot asset on HyperCore.
  /// @return amount The amount of tokens in flight.
  function getInFlightAmount(address pool, address asset) internal view returns (uint256 amount) {
    InFlightTrackingData memory trackingData = inFlightData[pool][asset];

    return (_composeBlockNumber() == trackingData.inFlightCompositeBlockNumber) ? trackingData.amount : 0;
  }

  function _composeBlockNumber() private view returns (uint256 compositeBlockNumber) {
    compositeBlockNumber = (uint256(l1BlockNumber()) << 128) | uint128(block.number);
  }
}
