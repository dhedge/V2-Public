// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {IUniswapV2Factory} from "contracts/interfaces/uniswapV2/IUniswapV2Factory.sol";
import {OneInchV6GuardTestSetup} from "test/integration/common/oneInch/OneInchV6GuardTestSetup.t.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";
import {PolygonSetup} from "test/integration/utils/foundry/chains/PolygonSetup.t.sol";

/// @notice Polygon is the only chain whose guard is deployed with a QuickSwap factory, so it is the
/// only place the QuickSwap branch of the Uniswap V2 pool check can be exercised.
contract OneInchV6GuardTestPolygon is OneInchV6GuardTestSetup, PolygonSetup {
  address internal constant QUICKSWAP_V2_FACTORY = 0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32;
  address internal constant SUSHISWAP_V2_FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;

  constructor()
    OneInchV6GuardTestSetup(
      IUniswapV2Factory(PolygonConfig.UNISWAP_V2_FACTORY),
      IUniswapV3Factory(PolygonConfig.UNISWAP_V3_FACTORY),
      QUICKSWAP_V2_FACTORY
    )
    PolygonSetup(93443000)
  {}

  function setUp() public override(OneInchV6GuardTestSetup, PolygonSetup) {
    super.setUp();
  }

  function test_unoswap_through_quickswap_pair() public {
    _assertUnoswapThroughV2Pair(IUniswapV2Factory(quickswapV2Factory).getPair(wethData.asset, usdcData.asset));
  }

  function test_revert_unoswap_when_v2_pair_is_from_another_factory() public {
    // A genuine SushiSwap pair: a real V2 pool, but neither Uniswap nor QuickSwap deployed it.
    address sushiPair = IUniswapV2Factory(SUSHISWAP_V2_FACTORY).getPair(wethData.asset, usdcData.asset);
    require(sushiPair != address(0), "sushi pair missing on fork");

    bytes memory unoswapData = _encodeUnoswap(
      wethData.asset,
      1,
      1,
      _dexWord(sushiPair, wethData.asset, PROTOCOL_UNISWAP_V2) | UNISWAP_V2_FEE_NUMERATOR
    );

    vm.prank(manager);
    vm.expectRevert("uniV2 pool invalid");
    testPool.execTransaction(address(router), unoswapData);
  }
}
