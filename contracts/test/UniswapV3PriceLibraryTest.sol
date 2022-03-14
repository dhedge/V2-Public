// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "../utils/uniswap/UniswapV3PriceLibrary.sol";

contract UniswapV3PriceLibraryTest {
  function assertFairPrice(
    address dhedgeFactory,
    address uniswapV3Factory,
    address token0,
    address token1,
    uint24 fee
  ) public view {
    UniswapV3PriceLibrary.assertFairPrice(dhedgeFactory, uniswapV3Factory, token0, token1, fee);
  }
}
