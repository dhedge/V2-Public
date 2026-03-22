// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {ChainlinkTWAPAggregator} from "contracts/priceAggregators/ChainlinkTWAPAggregator.sol";
import {UniV3TWAPAggregator} from "contracts/priceAggregators/UniV3TWAPAggregator.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {DhedgeMath} from "contracts/utils/DhedgeMath.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

import {Test} from "forge-std/Test.sol";

contract ChainlinkTWAPAggregatorXAUtTest is Test {
  using Math for uint256;
  using SafeCast for *;
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using DhedgeMath for *;

  IUniswapV3Pool public WBTC_XAUt_POOL = IUniswapV3Pool(0x6546055f46e866a4B9a4A13e81273e3152BAE5dA);
  address public XAUt = 0x68749665FF8D2d112Fa859AA293F07A622782F38;
  uint32 public updateInterval = 1800; // For 30 minutes TWAP
  IAggregatorV3Interface public XAU_CHAINLINK_ORACLE =
    IAggregatorV3Interface(0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6);
  uint256 public maxDifferencePercent = 2e16; // 2%

  UniV3TWAPAggregator public uniV3TWAPAggregator;
  ChainlinkTWAPAggregator public chainlinkTWAPAggregator;

  function setUp() public virtual {
    // Always start from a fresh fork
    vm.createSelectFork("ethereum");

    uniV3TWAPAggregator = new UniV3TWAPAggregator(
      WBTC_XAUt_POOL,
      XAUt,
      IAggregatorV3Interface(EthereumConfig.USDT_CHAINLINK_ORACLE),
      updateInterval
    );

    chainlinkTWAPAggregator = new ChainlinkTWAPAggregator(
      XAU_CHAINLINK_ORACLE,
      IAggregatorV3Interface(address(uniV3TWAPAggregator)),
      maxDifferencePercent,
      ChainlinkTWAPAggregator.ResultingPrice.MAX
    );
  }

  function test_chainlink_twap_aggregator_returns_price() public view {
    (, int256 price, , , ) = chainlinkTWAPAggregator.latestRoundData();

    (, int256 chainlinkPriceD8, , , ) = XAU_CHAINLINK_ORACLE.latestRoundData();
    (, int256 twapD18, , , ) = uniV3TWAPAggregator.latestRoundData();

    assertEq(price, (chainlinkPriceD8.toUint256().max(twapD18.toUint256())).toInt256());
  }

  function test_price_diff_between_chainlink_and_twap_is_within_limit() public view {
    (, int256 chainlinkPriceD8, , , ) = XAU_CHAINLINK_ORACLE.latestRoundData();
    (, int256 twapD18, , , ) = uniV3TWAPAggregator.latestRoundData();

    uint256 priceDifference = chainlinkPriceD8.sub(twapD18).abs();
    uint256 minPrice = chainlinkPriceD8.toUint256().min(twapD18.toUint256());
    uint256 differencePercent = priceDifference.mul(1e18).div(minPrice);

    assertLe(differencePercent, maxDifferencePercent);
  }
}
