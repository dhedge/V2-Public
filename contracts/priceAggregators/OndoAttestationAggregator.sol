// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IAggregatorV3Interface} from "../interfaces/IAggregatorV3Interface.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IOracleHeartbeat} from "../interfaces/IOracleHeartbeat.sol";
import {IGMTokenManager} from "../interfaces/ondo/IGMTokenManager.sol";
import {IOndoAttestationOracle} from "../interfaces/ondo/IOndoAttestationOracle.sol";

/// @title Ondo asset price aggregator using attestation-based oracle
/// @notice Per-token wrapper that reads from OndoAttestationOracle and exposes IAggregatorV3Interface.
contract OndoAttestationAggregator is IAggregatorV3Interface, IOracleHeartbeat, ICommonErrors {
  error OndoMintingPaused();
  error OndoRedemptionsPaused();

  IOndoAttestationOracle public immutable oracle;
  address public immutable ondoAsset;

  uint8 private constant PRICE_DECIMALS = 8;
  uint256 private constant DECIMALS_ADJUSTMENT_FACTOR = 10 ** (18 - PRICE_DECIMALS);
  uint256 private constant ORACLE_HEARTBEAT = 49 hours;

  constructor(IOndoAttestationOracle _oracle, address _ondoAsset) {
    if (address(_oracle) == address(0)) revert ZeroAddress("_oracle");
    if (_ondoAsset == address(0)) revert ZeroAddress("_ondoAsset");

    oracle = _oracle;
    ondoAsset = _ondoAsset;
  }

  function decimals() external pure override returns (uint8) {
    return PRICE_DECIMALS;
  }

  /// @notice Maximum acceptable age for the underlying oracle's price update.
  /// @dev Read by AssetHandler to override its default chainlinkTimeout for this aggregator.
  ///      Ondo's attestation oracle updates roughly every 2 days, so 49h gives one cycle of buffer.
  function oracleHeartbeat() external pure override returns (uint256) {
    return ORACLE_HEARTBEAT;
  }

  /// @notice Get the latest round data
  /// @return roundId Always 0
  /// @return answer The price in 8 decimals
  /// @return startedAt Always 0
  /// @return updatedAt Timestamp of the price
  /// @return answeredInRound Always 0
  function latestRoundData()
    external
    view
    override
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    IGMTokenManager gmTokenManager = oracle.gmTokenManager();
    if (gmTokenManager.gmTokenMintingPaused(ondoAsset)) revert OndoMintingPaused();
    if (gmTokenManager.gmTokenRedemptionsPaused(ondoAsset)) revert OndoRedemptionsPaused();

    (uint256 price, uint256 priceUpdatedAt) = oracle.getPrice(ondoAsset);

    answer = int256(price / DECIMALS_ADJUSTMENT_FACTOR);
    updatedAt = priceUpdatedAt;

    return (0, answer, 0, updatedAt, 0);
  }
}
