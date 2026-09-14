// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {ChainlinkPythPriceAggregator} from "contracts/priceAggregators/ChainlinkPythPriceAggregator.sol";
import {ChainlinkPythPriceLib} from "contracts/utils/chainlinkPyth/ChainlinkPythPriceLib.sol";
import {PythPriceLib} from "contracts/utils/pyth/PythPriceLib.sol";
import {IAggregatorV3Interface as IChainlinkAggregatorV3} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IPyth} from "contracts/interfaces/pyth/IPyth.sol";
import {IGmxPrice} from "contracts/interfaces/gmx/IGmxPrice.sol";

/// @notice `ChainlinkPythPriceAggregator` reports the Chainlink price while using Pyth to bracket
/// it with a min/max band (which GMX integrations price against). The Chainlink answer is the
/// critical one, so a stale answer has to revert rather than degrade to the Pyth price.
abstract contract ChainlinkPythPriceAggregatorTestSetup is Test {
  address internal immutable token;
  address internal immutable pyth;
  address internal immutable chainlinkOracle;
  uint32 internal immutable chainlinkMaxAge;
  bytes32 internal immutable pythPriceId;

  ChainlinkPythPriceAggregator internal aggregator;

  constructor(address _token, address _pyth, address _chainlinkOracle, uint32 _chainlinkMaxAge, bytes32 _pythPriceId) {
    token = _token;
    pyth = _pyth;
    chainlinkOracle = _chainlinkOracle;
    chainlinkMaxAge = _chainlinkMaxAge;
    pythPriceId = _pythPriceId;
  }

  function setUp() public virtual {
    aggregator = new ChainlinkPythPriceAggregator(
      token,
      IPyth(pyth),
      ChainlinkPythPriceLib.OracleData({
        onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
          oracleContract: IChainlinkAggregatorV3(chainlinkOracle),
          maxAge: chainlinkMaxAge
        }),
        offchainOracle: PythPriceLib.OffchainOracle({priceId: pythPriceId, maxAge: 86_400, minConfidenceRatio: 1})
      })
    );
  }

  function test_aggregator_reports_eight_decimals() public view {
    assertEq(uint256(aggregator.decimals()), 8);
  }

  function test_price_tracks_the_chainlink_answer() public view {
    (, int256 chainlinkPrice, , , ) = IChainlinkAggregatorV3(chainlinkOracle).latestRoundData();
    (, int256 price, , , ) = aggregator.latestRoundData();

    assertGt(price, 0);
    // Pyth and Chainlink are independent feeds, so they agree only to within a few percent.
    assertApproxEqRel(uint256(price), uint256(chainlinkPrice), 0.05e18);
  }

  function test_min_max_band_brackets_the_reported_price() public view {
    IGmxPrice.Price memory band = aggregator.getTokenMinMaxPrice(true);
    (, int256 price, , , ) = aggregator.latestRoundData();

    // The band collapses onto the Chainlink price when Pyth has nothing fresher on chain, so it
    // brackets the price without necessarily widening it.
    assertLe(band.min, uint256(price));
    assertGe(band.max, uint256(price));
    // It is a confidence interval rather than an arbitrary spread, so it stays within ~5%.
    assertGe((band.min * 105) / 100, uint256(price));
    assertLe((band.max * 100) / 105, uint256(price));
  }

  function test_revert_when_the_chainlink_answer_is_stale() public {
    vm.warp(block.timestamp + chainlinkMaxAge + 1);

    vm.expectRevert("Onchain oracle price is stale");
    aggregator.latestRoundData();
  }
}
