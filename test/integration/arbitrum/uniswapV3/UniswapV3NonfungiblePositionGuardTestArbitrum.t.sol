// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

// solhint-disable-next-line max-line-length
import {UniswapV3NonfungiblePositionGuardTestSetup} from "test/integration/common/uniswapV3/UniswapV3NonfungiblePositionGuardTestSetup.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

/// @notice Runs the UniswapV3NonfungiblePositionGuard suite against an Arbitrum fork. This suite
/// starts with the position NFT not yet enabled on the vault, so it needs its own vault and cannot
/// share the one the asset guard suite builds.
contract UniswapV3NonfungiblePositionGuardTestArbitrum is UniswapV3NonfungiblePositionGuardTestSetup, ArbitrumSetup {
  constructor()
    UniswapV3NonfungiblePositionGuardTestSetup(
      ArbitrumConfig.UNISWAP_V3_NFT_MANAGER,
      ArbitrumConfig.UNISWAP_V3_FACTORY,
      500
    )
    ArbitrumSetup(489036888)
  {}

  function setUp() public override(UniswapV3NonfungiblePositionGuardTestSetup, ArbitrumSetup) {
    super.setUp();
  }
}
