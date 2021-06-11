// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IERC20Extended.sol"; // includes decimals()
import "../utils/DhedgeMath.sol";

/**
 * @title Sushi LP aggregator. For dHEDGE LP Price Feeds.
 * @notice You can use this contract for lp token pricing oracle.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract SushiLPAggregator is IAggregatorV3Interface {
  using SafeMathUpgradeable for uint256;

  address public pair;
  address public token0;
  address public token1;
  address public aggregator0;
  address public aggregator1;

  constructor(
    address _pair,
    address _aggregator0,
    address _aggregator1
  ) {
    pair = _pair;
    token0 = IUniswapV2Pair(pair).token0();
    token1 = IUniswapV2Pair(pair).token1();
    aggregator0 = _aggregator0;
    aggregator1 = _aggregator1;
  }

  /* ========== VIEWS ========== */

  /**
   * @dev Get the latest round data. Should be the same format as chainlink aggregator.
   * @return Returns the latest round data of a given sushi lp token (price decimal: 8)
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
    (uint256 answer0, uint256 answer1, uint256 updatedAt) = _getTokenPrices();

    // calculate lp price
    // referenced from
    // https://github.com/sushiswap/kashi-lending/blob/master/contracts/oracles/LPChainlinkOracle.sol
    // https://github.com/AlphaFinanceLab/homora-v2/blob/master/contracts/oracle/UniswapV2Oracle.sol

    uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
    (uint256 r0, uint256 r1, ) = IUniswapV2Pair(pair).getReserves();
    uint256 decimal0 = IERC20Extended(token0).decimals();
    uint256 decimal1 = IERC20Extended(token1).decimals();

    r0 = r0.mul(10**18).div(10**decimal0); // decimal = 18
    r1 = r1.mul(10**18).div(10**decimal1); // decimal = 18

    uint256 r = DhedgeMath.sqrt(r0.mul(r1)); // decimal = 18

    uint256 p = DhedgeMath.sqrt(answer0.mul(answer1)); // decimal = 8

    uint256 answer = r.mul(p).mul(2).div(totalSupply); // decimal = 8

    // we don't need roundId, startedAt and answeredInRound
    return (0, int256(answer), 0, updatedAt, 0);
  }

  /* ========== INTERNAL ========== */

  function _getTokenPrices()
    internal
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    (int256 answer0, uint256 updatedAt0) = _getTokenPrice(aggregator0);
    (int256 answer1, uint256 updatedAt1) = _getTokenPrice(aggregator1);

    // calculate updatedAt
    uint256 updatedAt = updatedAt0;
    if (updatedAt0 > updatedAt1) {
      updatedAt = updatedAt1;
    }

    return (uint256(answer0), uint256(answer1), updatedAt);
  }

  function _getTokenPrice(address aggregator) internal view returns (int256 answer, uint256 updatedAt) {
    try IAggregatorV3Interface(aggregator).latestRoundData() returns (
      uint80,
      int256 _answer,
      uint256,
      uint256 _updatedAt,
      uint80
    ) {
      return (_answer, _updatedAt);
    } catch {
      revert("Price get failed");
    }
  }
}
