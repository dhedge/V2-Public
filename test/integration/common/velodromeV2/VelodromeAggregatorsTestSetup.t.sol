// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {VelodromeStableLPAggregator} from "contracts/priceAggregators/VelodromeStableLPAggregator.sol";
import {VelodromeVariableLPAggregator} from "contracts/priceAggregators/VelodromeVariableLPAggregator.sol";
import {VelodromeV2TWAPAggregator} from "contracts/priceAggregators/VelodromeV2TWAPAggregator.sol";
import {IVelodromeV2Router} from "contracts/interfaces/velodrome/IVelodromeV2Router.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IVelodromeV2Pair} from "contracts/interfaces/velodrome/IVelodromeV2Pair.sol";

/// @notice The three Velodrome price feeds dHEDGE relies on, and the single property that makes
/// them safe to price vault assets with: a trader moving the pool must not move the reported
/// price. LP aggregators derive value from reserves and the underlyings' oracles rather than from
/// the spot ratio, and the TWAP aggregator averages over time.
/// @dev The original TWAP test compared against the live CoinGecko API. That is an external
/// dependency and says nothing about manipulation, so it is replaced by the property above.
abstract contract VelodromeAggregatorsTestSetup is Test {
  /// @dev Aggregators report in 8 decimals like Chainlink.
  uint256 internal constant PRICE_DECIMALS = 8;
  /// @dev A price feed may drift this much across a multi-million dollar swap.
  uint256 internal constant MAX_DRIFT = 0.0001e18; // 0.01%

  struct TestParams {
    address router;
    address factory; // Velodrome pool factory, used to route swaps
    address dhedgeFactory; // dHEDGE PoolFactory - the LP aggregators price underlyings through it
    address stablePool; // USDC/DAI
    address variablePool; // WETH/USDC
    address usdc;
    address dai;
    address weth;
    address usdcOracle;
  }

  TestParams internal params;

  VelodromeStableLPAggregator internal stableLpAggregator;
  VelodromeVariableLPAggregator internal variableLpAggregator;
  VelodromeV2TWAPAggregator internal wethTwapAggregator;

  address internal whale = makeAddr("whale");

  constructor(TestParams memory _params) {
    params = _params;
  }

  function setUp() public virtual {
    stableLpAggregator = new VelodromeStableLPAggregator(params.stablePool, params.dhedgeFactory);
    variableLpAggregator = new VelodromeVariableLPAggregator(params.variablePool, params.dhedgeFactory);
    // WETH priced through its pool against USDC, with USDC's Chainlink feed as the anchor.
    wethTwapAggregator = new VelodromeV2TWAPAggregator(
      params.variablePool,
      params.weth,
      params.usdc,
      IAggregatorV3Interface(params.usdcOracle)
    );
  }

  /* ========== SANITY ========== */

  function test_aggregators_report_eight_decimals() public view {
    assertEq(uint256(stableLpAggregator.decimals()), PRICE_DECIMALS);
    assertEq(uint256(variableLpAggregator.decimals()), PRICE_DECIMALS);
    assertEq(uint256(wethTwapAggregator.decimals()), PRICE_DECIMALS);
  }

  function test_aggregators_report_a_positive_price() public view {
    assertGt(_price(address(stableLpAggregator)), 0);
    assertGt(_price(address(variableLpAggregator)), 0);
    assertGt(_price(address(wethTwapAggregator)), 0);
  }

  function test_revert_constructing_a_twap_for_tokens_outside_the_pool() public {
    vm.expectRevert("invalid tokens");
    new VelodromeV2TWAPAggregator(
      params.variablePool,
      params.dai, // not a token of the WETH/USDC pool
      params.usdc,
      IAggregatorV3Interface(params.usdcOracle)
    );
  }

  /* ========== MANIPULATION RESISTANCE ========== */

  function test_stable_lp_price_survives_a_two_hundred_thousand_dollar_swap() public {
    _assertLpPriceHoldsThroughSwap(address(stableLpAggregator), params.usdc, params.dai, true, 200_000e6);
  }

  function test_stable_lp_price_survives_a_one_million_dollar_swap() public {
    _assertLpPriceHoldsThroughSwap(address(stableLpAggregator), params.usdc, params.dai, true, 1_000_000e6);
  }

  function test_variable_lp_price_survives_a_two_hundred_thousand_dollar_swap() public {
    _assertLpPriceHoldsThroughSwap(address(variableLpAggregator), params.usdc, params.weth, false, 200_000e6);
  }

  function test_variable_lp_price_survives_a_four_million_dollar_swap() public {
    _assertLpPriceHoldsThroughSwap(address(variableLpAggregator), params.usdc, params.weth, false, 4_000_000e6);
  }

  /// @dev The reported price is averaged from stored 30 minute observations, never read from
  /// current reserves, so a swap inside the live period cannot reach it however large it is.
  /// Assert the pool really did move: otherwise "the price held" would also pass for a swap
  /// that never landed, which is what makes a same-block check on its own worthless.
  function test_twap_price_ignores_a_four_million_dollar_swap_within_one_period() public {
    uint256 reportedBefore = _price(address(wethTwapAggregator));
    uint256 spotBefore = _spotWethPrice();

    assertGt(_swap(params.usdc, params.weth, false, 4_000_000e6), 0, "swap did not execute");

    assertGt(_spotWethPrice(), spotBefore * 10, "swap did not move the pool price");
    assertEq(_price(address(wethTwapAggregator)), reportedBefore, "same-block swap moved the twap");

    // Still inside the period, so an update writes no new observation and the price stays put.
    // An averaging window shorter than this would already have followed the pool.
    skip(10 minutes);
    _swap(params.usdc, params.weth, false, 1e6);
    assertEq(_price(address(wethTwapAggregator)), reportedBefore, "twap moved inside one period");
  }

  /// @dev The resistance above is time-bounded, not absolute: once a whole period of manipulated
  /// price has been recorded, the average does follow it. Pinned so that widening the pool's
  /// period or changing the aggregator's granularity fails here instead of silently shifting how
  /// long an attacker must hold a position to move a feed that prices live vault assets.
  function test_twap_price_follows_a_swap_held_past_one_period() public {
    uint256 reportedBefore = _price(address(wethTwapAggregator));

    _swap(params.usdc, params.weth, false, 4_000_000e6);

    // Past the period, so this small swap records an observation covering the manipulated stretch.
    skip(31 minutes);
    _swap(params.usdc, params.weth, false, 1e6);

    uint256 reportedAfter = _price(address(wethTwapAggregator));
    assertGt(reportedAfter, reportedBefore * 5, "a period-long manipulation should reach the twap");
    // Averaging still lags: the feed sits well below the manipulated pool price. The aggregator
    // reports 8 decimals and the pool quotes USDC's 6, so drop two to compare them.
    assertLt(reportedAfter / 100, _spotWethPrice(), "twap should lag spot, not track it");
  }

  function _assertLpPriceHoldsThroughSwap(
    address _aggregator,
    address _tokenIn,
    address _tokenOut,
    bool _stable,
    uint256 _amountIn
  ) internal {
    uint256 priceBefore = _price(_aggregator);

    uint256 receivedOut = _swap(_tokenIn, _tokenOut, _stable, _amountIn);
    assertGt(receivedOut, 0, "swap did not execute");

    assertApproxEqRel(_price(_aggregator), priceBefore, MAX_DRIFT);
  }

  function _swap(
    address _tokenIn,
    address _tokenOut,
    bool _stable,
    uint256 _amountIn
  ) internal returns (uint256 amountOut) {
    deal(_tokenIn, whale, _amountIn);

    IVelodromeV2Router.Route[] memory routes = new IVelodromeV2Router.Route[](1);
    routes[0] = IVelodromeV2Router.Route({from: _tokenIn, to: _tokenOut, stable: _stable, factory: params.factory});

    vm.startPrank(whale);
    IERC20(_tokenIn).approve(params.router, _amountIn);
    IVelodromeV2Router(params.router).swapExactTokensForTokens(_amountIn, 0, routes, whale, type(uint256).max);
    vm.stopPrank();

    amountOut = IERC20(_tokenOut).balanceOf(whale);
  }

  /// @dev The pool's own price for one WETH, in USDC, read straight from current reserves.
  function _spotWethPrice() internal view returns (uint256 usdcPerWeth) {
    usdcPerWeth = IVelodromeV2Pair(params.variablePool).getAmountOut(1e18, params.weth);
  }

  function _price(address _aggregator) internal view returns (uint256 price) {
    (, int256 answer, , , ) = IAggregatorV3Interface(_aggregator).latestRoundData();
    price = uint256(answer);
  }
}
