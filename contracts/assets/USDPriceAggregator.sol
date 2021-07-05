// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IERC20Extended.sol"; // includes decimals()
import "../utils/DhedgeMath.sol";

/**
 * @title USD price aggregator. For dHEDGE LP Price Feeds.
 * @notice You can use this contract for usd price = $1.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract USDPriceAggregator is IAggregatorV3Interface {
  /**
   * @dev Get the latest round data. Should be the same format as chainlink aggregator.
   * @return Returns the latest round data of usd (price decimal: 8)
   */
  function latestRoundData()
    external
    view
    override
    returns (
      uint80,
      int256,
      uint256,
      uint256,
      uint80
    )
  {
    return (0, 10**8, 0, block.timestamp, 0);
  }
}
