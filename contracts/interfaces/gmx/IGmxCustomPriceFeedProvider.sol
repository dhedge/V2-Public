// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;
import {IGmxPrice} from "./IGmxPrice.sol";

interface IGmxCustomPriceFeedProvider {
  function asset() external view returns (address);

  /// @notice Get the min and max USD price of the asset.
  /// @dev Prices are in the same decimals as provided by the on-chain oracle (Chainlink), typically 8 decimals.
  /// @dev Used for GMX market integration
  function getTokenMinMaxPrice(bool useMinMax) external view returns (IGmxPrice.Price memory priceMinMax);
}
