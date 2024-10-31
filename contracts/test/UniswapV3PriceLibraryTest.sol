// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {UniswapV3PriceLibrary} from "../utils/uniswap/UniswapV3PriceLibrary.sol";
import {CLPriceLibrary} from "../utils/commonCL/CLPriceLibrary.sol";

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

  function calculateSqrtPrice(
    uint256 token0Price,
    uint256 token1Price,
    uint8 token0Decimals,
    uint8 token1Decimals
  ) public pure returns (uint160 sqrtPriceX96) {
    sqrtPriceX96 = CLPriceLibrary.calculateSqrtPrice(token0Price, token1Price, token0Decimals, token1Decimals);
  }
}
