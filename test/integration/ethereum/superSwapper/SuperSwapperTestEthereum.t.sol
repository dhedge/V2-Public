// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {SuperSwapperTest} from "test/integration/common/superSwapper/SuperSwapperTest.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract SuperSwapperTestEthereum is SuperSwapperTest {
  constructor()
    SuperSwapperTest(
      "ethereum",
      EthereumConfig.UNISWAP_V3_FACTORY,
      EthereumConfig.UNISWAP_V3_ROUTER,
      _getV2Routers(),
      EthereumConfig.WBTC, // tokenIn
      1e8, // amountIn
      EthereumConfig.USDC // tokenOut
    )
  {}

  function setUp() public override {
    super.setUp();
  }

  function _getV2Routers() internal pure returns (address[] memory v2Routers) {
    v2Routers = new address[](2);
    v2Routers[0] = EthereumConfig.UNISWAP_V2_ROUTER;
    v2Routers[1] = EthereumConfig.SUSHISWAP_ROUTER;
  }
}
