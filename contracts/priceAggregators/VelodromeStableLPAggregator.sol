// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/velodrome/IVelodromePair.sol";
import "../interfaces/IERC20Extended.sol"; // includes decimals()
import "../interfaces/IHasAssetInfo.sol";
import "../utils/DhedgeMath.sol";

/**
 * @title Velodrome Stable LP aggregator. For dHEDGE LP Price Feeds.
 * @notice You can use this contract for Velodrome lp token pricing oracle.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract VelodromeStableLPAggregator is IAggregatorV3Interface {
  using SafeMathUpgradeable for uint256;

  address public pair;
  address public token0;
  address public token1;
  address public factory;

  constructor(address _pair, address _factory) {
    require(_pair != address(0), "_pair address cannot be 0");
    require(_factory != address(0), "_factory address cannot be 0");
    pair = _pair;
    token0 = IVelodromePair(pair).token0();
    token1 = IVelodromePair(pair).token1();
    factory = _factory;
  }

  /* ========== VIEWS ========== */

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  function _calculateFairReserves(
    uint256 x,
    uint256 y,
    uint256 px,
    uint256 py
  ) private pure returns (uint256 fairX, uint256 fairY) {
    // NOTE:
    // x = reserve0 (18 decimals), y = reserve1 (18 decimals), px = token0 price (18 decimals), py = token1 price (18 decimals)
    // constant product = x^3 * y + x * y^3
    // constraints:
    // - fairX^3 * fairY + fairX * fairY^3 = constant product
    // - fairX * px = fairY * py
    // Solving equations:
    // --> fairY = fairX * px / py
    // --> fairX^4 * px / py + fairX^4 * (px / py)^3 = constant product
    // --> ratio = px / py
    // --> fairX^4 * (ratio + ratio^3) = x * y * (x^2 + y^2)
    // --> fairX^2 = sqrt(x * y) * sqrt(x^2 + y^2) / (sqrt(ratio) * sqrt(1 + ratio^2))
    // --> fairX = sqrt(sqrt(x * y) * sqrt(x^2 + y^2)) / sqrt(sqrt(ratio) * sqrt(1 + ratio^2))

    // r0 = sqrt(x * y)
    uint256 r0 = DhedgeMath.sqrt(x.mul(y)); // decimal = 18
    // r1 = sqrt(x^2 + y^2)
    uint256 r1 = DhedgeMath.sqrt(x.mul(x) + y.mul(y)); // decimal = 18
    // r = sqrt(sqrt(x * y) * sqrt(x^2 + y^2))
    uint256 r = DhedgeMath.sqrt(r0.mul(r1)); // decimal = 18

    // ratio = px / py
    uint256 ratio = px.mul(10**18).div(py); // decimal = 18
    // p0 = sqrt(ratio)
    uint256 p0 = DhedgeMath.sqrt(ratio.mul(10**18)); // decimal = 18
    // p1 = sqrt(1 + ratio^2)
    uint256 p1 = DhedgeMath.sqrt(10**36 + ratio.mul(ratio)); // decimal = 18
    // p = sqrt(sqrt(ratio) * sqrt(1 + ratio^2))
    uint256 p = DhedgeMath.sqrt(p0.mul(p1)); // decimal = 18

    // fairX = sqrt(sqrt(x * y) * sqrt(x^2 + y^2)) / sqrt(sqrt(ratio) * sqrt(1 + ratio^2))
    fairX = r.mul(10**18).div(p);
    fairY = fairX.mul(px).div(py);
  }

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of a given velodrome lp token (price decimal: 8)
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
    (uint256 answer0, uint256 answer1) = _getTokenPrices();
    uint256 totalSupply = IVelodromePair(pair).totalSupply();
    (uint256 r0, uint256 r1, ) = IVelodromePair(pair).getReserves();
    uint256 decimal0 = IERC20Extended(token0).decimals();
    uint256 decimal1 = IERC20Extended(token1).decimals();

    r0 = r0.mul(10**18).div(10**decimal0); // decimal = 18
    r1 = r1.mul(10**18).div(10**decimal1); // decimal = 18

    (uint256 fairX, uint256 fairY) = _calculateFairReserves(r0, r1, answer0, answer1);

    uint256 answer = fairX.mul(answer0).add(fairY.mul(answer1)).div(totalSupply); // decimal = 18

    // we don't need roundId, startedAt and answeredInRound
    return (0, int256(answer.div(10**10)), 0, block.timestamp, 0);
  }

  /* ========== INTERNAL ========== */

  function _getTokenPrices() internal view returns (uint256, uint256) {
    return (IHasAssetInfo(factory).getAssetPrice(token0), IHasAssetInfo(factory).getAssetPrice(token1));
  }
}
