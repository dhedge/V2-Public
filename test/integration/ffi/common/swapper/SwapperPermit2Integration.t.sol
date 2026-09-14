// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "contracts/swappers/swapper/SwapperStructs.sol" as SwapperStructs;
import {SwapperTestsHelper} from "./SwapperTestsHelper.sol";
import {Token} from "./SwapperTestSetup.sol";
import {TokenArrayBuilder} from "./TokenArrayBuilder.sol";

abstract contract SwapperPermit2IntegrationTest is SwapperTestsHelper {
  using TokenArrayBuilder for *;

  function test_integration_swap_single_in_single_out_permit2() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, USDC);
    Token memory destToken = rETH;

    runAllAggregatorTests({
      srcTokens: srcTokens,
      destToken: destToken,
      transferMethod: SwapperStructs.TransferMethod.PERMIT2
    });
  }

  function test_integration_swap_multi_in_single_out_permit2() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, USDC).push(DAI);
    Token memory destToken = rETH;

    runAllAggregatorTests({
      srcTokens: srcTokens,
      destToken: destToken,
      transferMethod: SwapperStructs.TransferMethod.PERMIT2
    });
  }
}
