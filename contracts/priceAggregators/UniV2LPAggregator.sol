// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/uniswapV2/IUniswapV2Pair.sol";
import "../interfaces/IERC20Extended.sol"; // includes decimals()
import "../interfaces/IHasAssetInfo.sol";
import "../utils/DhedgeMath.sol";

/**
 * @title Uni-v2 LP aggregator. For dHEDGE LP Price Feeds.
 * @notice You can use this contract for lp token pricing oracle.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract UniV2LPAggregator is IAggregatorV3Interface {
  using SafeMathUpgradeable for uint256;

  address public pair;
  address public token0;
  address public token1;
  address public factory;

  constructor(address _pair, address _factory) {
    require(_pair != address(0), "_pair address cannot be 0");
    require(_factory != address(0), "_factory address cannot be 0");
    pair = _pair;
    token0 = IUniswapV2Pair(pair).token0();
    token1 = IUniswapV2Pair(pair).token1();
    factory = _factory;
  }

  /* ========== VIEWS ========== */

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of a given uni-v2 lp token (price decimal: 8)
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

    uint256 p = DhedgeMath.sqrt(answer0.mul(answer1)); // decimal = 18

    uint256 answer = r.mul(p).mul(2).div(totalSupply).div(10**10); // decimal = 8

    // we don't need roundId, startedAt and answeredInRound
    return (0, int256(answer), 0, block.timestamp, 0);
  }

  /* ========== INTERNAL ========== */

  function _getTokenPrices() internal view returns (uint256, uint256) {
    return (IHasAssetInfo(factory).getAssetPrice(token0), IHasAssetInfo(factory).getAssetPrice(token1));
  }
}
