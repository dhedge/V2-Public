// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/IPoolLogic.sol";
import "../interfaces/IERC20Extended.sol"; // includes decimals()

/**
 * @title DHEDGE pool aggregator.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract DHedgePoolAggregator is IAggregatorV3Interface {
  using SafeMathUpgradeable for uint256;

  address public poolLogic;

  constructor(address _poolLogic) {
    require(_poolLogic != address(0), "_poolLogic address cannot be 0");
    poolLogic = _poolLogic;
  }

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /* ========== VIEWS ========== */

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of a given DHEDGE pool (price decimal: 8)
   * @return startedAt Timestamp of when the round started.
   * @return updatedAt Timestamp of when the round was updated.
   * @return answeredInRound The round ID of the round in which the answer was computed.
   */
  function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
    uint256 tokenPrice = IPoolLogic(poolLogic).tokenPrice();
    // adjust decimals -> 8
    int256 answer = tokenPrice == 0 ? 0 : int256(tokenPrice.div(10 ** 10));
    // we don't need roundId, startedAt and answeredInRound
    return (0, answer, 0, block.timestamp, 0);
  }
}
