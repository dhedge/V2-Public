// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {IUniswapV2Factory} from "contracts/interfaces/uniswapV2/IUniswapV2Factory.sol";
import {OneInchV6GuardTestSetup} from "test/integration/common/oneInch/OneInchV6GuardTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract OneInchV6GuardTestArbitrum is OneInchV6GuardTestSetup, ArbitrumSetup {
  /// @dev Only this suite needs Arbitrum's UniswapV2 factory, so it stays scoped here.
  address private constant UNISWAP_V2_FACTORY = 0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9;

  constructor()
    OneInchV6GuardTestSetup(
      IUniswapV2Factory(UNISWAP_V2_FACTORY),
      IUniswapV3Factory(ArbitrumConfig.UNISWAP_V3_FACTORY),
      address(0)
    )
    ArbitrumSetup(489036888)
  {}

  function setUp() public override(OneInchV6GuardTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
