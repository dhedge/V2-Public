// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/maticx/IMaticXPool.sol";
import "../interfaces/IHasAssetInfo.sol";

/**
 * @title MaticX price aggregator.
 * @notice You can use this contract for MaticX token pricing oracle.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract MaticXPriceAggregator is IAggregatorV3Interface {
  using SafeMathUpgradeable for uint256;

  address public matic;
  address public maticX;
  address public maticXPool;
  address public factory;

  constructor(
    address _matic,
    address _maticX,
    address _maticXPool,
    address _factory
  ) {
    require(_matic != address(0), "_matic address cannot be 0");
    require(_maticX != address(0), "_maticX address cannot be 0");
    require(_maticXPool != address(0), "_maticXPool address cannot be 0");
    require(_factory != address(0), "_factory address cannot be 0");

    matic = _matic;
    maticX = _maticX;
    maticXPool = _maticXPool;
    factory = _factory;
  }

  /* ========== VIEWS ========== */

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of matic token (price decimal: 8)
   * @return startedAt Timestamp of when the round started.
   * @return updatedAt Timestamp of when the round was updated.
   * @return answeredInRound The round ID of the round in which the answer was computed.
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
    uint256 maticPrice = _getMaticPrice(); // decimals = 18

    uint256 maticXRatio = IMaticXPool(maticXPool).convertMaticXToMatic(10**18); // decimals = 18

    uint256 answer = maticPrice.mul(maticXRatio).div(10**28); // decimals = 8

    // we don't need roundId, startedAt and answeredInRound
    return (0, int256(answer), 0, block.timestamp, 0);
  }

  /* ========== INTERNAL ========== */

  function _getMaticPrice() internal view returns (uint256) {
    return IHasAssetInfo(factory).getAssetPrice(matic);
  }
}
