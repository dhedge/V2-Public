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
// import {console} from "forge-std/console.sol";

contract ChainlinkTWAPAggregatorUSDeTest is Test {
  using Math for uint256;
  using SafeCast for *;
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  using DhedgeMath for *;

  IUniswapV3Pool public USDC_USDe_POOL = IUniswapV3Pool(0xE6D7EbB9f1a9519dc06D557e03C522d53520e76A);
  uint32 public updateInterval = 900; // For 15 minutes TWAP
  uint256 public maxDifferencePercent = 5e15; // 0.5%

  UniV3TWAPAggregator public uniV3TWAPAggregator;
  ChainlinkTWAPAggregator public chainlinkTWAPAggregator;

  function setUp() public virtual {
    // Always start from a fresh fork
    vm.createSelectFork("ethereum");

    uniV3TWAPAggregator = new UniV3TWAPAggregator(
      USDC_USDe_POOL,
      EthereumConfig.USDe,
      IAggregatorV3Interface(EthereumConfig.USDC_CHAINLINK_ORACLE),
      updateInterval
    );

    chainlinkTWAPAggregator = new ChainlinkTWAPAggregator(
      IAggregatorV3Interface(EthereumConfig.USDC_CHAINLINK_ORACLE),
      IAggregatorV3Interface(address(uniV3TWAPAggregator)),
      maxDifferencePercent,
      ChainlinkTWAPAggregator.ResultingPrice.MAX
    );
  }

  function test_chainlink_twap_aggregator_returns_price() public view {
    (, int256 price, , , ) = chainlinkTWAPAggregator.latestRoundData();

    (, int256 chainlinkPriceD8, , , ) = IAggregatorV3Interface(EthereumConfig.USDC_CHAINLINK_ORACLE).latestRoundData();
    (, int256 twapD18, , , ) = uniV3TWAPAggregator.latestRoundData();

    assertEq(price, (chainlinkPriceD8.toUint256().max(twapD18.toUint256())).toInt256());
  }

  function test_price_diff_between_chainlink_and_twap_is_within_limit() public view {
    (, int256 chainlinkPriceD8, , , ) = IAggregatorV3Interface(EthereumConfig.USDC_CHAINLINK_ORACLE).latestRoundData();
    (, int256 twapD18, , , ) = uniV3TWAPAggregator.latestRoundData();
    // console.log("chainlinkPriceD8", chainlinkPriceD8);
    // console.log("twapD18", twapD18);

    uint256 priceDifference = chainlinkPriceD8.sub(twapD18).abs();
    uint256 minPrice = chainlinkPriceD8.toUint256().min(twapD18.toUint256());
    uint256 differencePercent = priceDifference.mul(1e18).div(minPrice);
    // console.log("differencePercent", differencePercent);

    assertLe(differencePercent, maxDifferencePercent);
  }
}
