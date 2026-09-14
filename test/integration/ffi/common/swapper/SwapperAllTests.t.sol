// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "contracts/swappers/swapper/SwapperStructs.sol" as SwapperStructs;
import {MockGenerousRouter} from "./MockGenerousRouter.sol";
import {SwapperNativeETHSwapIntegrationTest} from "./SwapperNativeETHSwaps.t.sol";
import {SwapperPermit2IntegrationTest} from "./SwapperPermit2Integration.t.sol";
import {SwapperSimpleAllowanceIntegrationTest} from "./SwapperSimpleAllowanceIntegration.t.sol";
import {SwapperTestsHelper} from "./SwapperTestsHelper.sol";
import {Token} from "./SwapperTestSetup.sol";
import {TokenArrayBuilder} from "./TokenArrayBuilder.sol";

abstract contract SwapperAllTests is
  SwapperNativeETHSwapIntegrationTest,
  SwapperPermit2IntegrationTest,
  SwapperSimpleAllowanceIntegrationTest
{
  using TokenArrayBuilder for *;

  function setUp() public virtual override {
    SwapperTestsHelper.setUp();
  }

  /// @dev Test to check if some portion of the source token amount remains in the swapper after a swap,
  ///      then the remaining source token amount should be returned to the caller.
  /// @dev Note: This test needn't be replicated for PERMIT2 and NATIVE transfer methods as the underlying logic is the same.
  function test_integration_return_single_source_token_amount_to_caller_if_unused() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, USDC);
    Token memory destToken = rETH;

    _sourceAmountReturnTest(srcTokens, destToken);
  }

  /// @dev Test to check if some portion of the source token amount (multiple source tokens) remains in the swapper after a swap,
  ///      then the remaining source token amount should be returned to the caller.
  /// @dev Note: This test needn't be replicated for PERMIT2 and NATIVE transfer methods as the underlying logic is the same.
  function test_integration_return_multiple_source_token_amounts_to_caller_if_unused() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, USDC).push(DAI);
    Token memory destToken = rETH;

    _sourceAmountReturnTest(srcTokens, destToken);
  }

  function test_integration_unlimited_approval_to_router_once_exhausted() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, DAI);
    Token memory destToken = rETH;

    address mockRouter = address(new MockGenerousRouter(1e18));

    // Add the mock router to the Swapper contract.
    vm.startPrank(admin);
    swapperProxy.addRouter(ONE_INCH_V6_ROUTER_KEY, mockRouter);

    // uint256 destBalanceBefore = destToken.token.balanceOf(alice);
    int8[TRANSFER_METHODS] memory transferMethodsIndices = [int8(uint8(srcTokens.length - 1)), -1, -1];
    Aggregator[] memory aggregators = new Aggregator[](srcTokens.length);

    for (uint256 i; i < srcTokens.length; i++) {
      aggregators[i] = Aggregator.ONE_INCH_V6;
    }

    (SwapperStructs.InOutData memory swapStruct, , ) = getSwapStruct(
      address(swapperProxy),
      srcTokens,
      destToken,
      transferMethodsIndices,
      aggregators
    );

    uint256 destAmount = swapStruct.destData.minDestAmount;

    vm.startPrank(alice);

    for (uint256 i; i < srcTokens.length; ++i) {
      // srcAmounts[i] = swapStruct.srcData[0].srcTokenSwapDetails[i].amount;
      swapStruct.srcData[0].srcTokenSwapDetails[i].amount = type(uint256).max / 2;

      deal(address(srcTokens[i].token), alice, type(uint256).max);

      // Unlimited approve the source token to the swapper.
      srcTokens[i].token.approve(address(swapperProxy), type(uint256).max);
    }

    // Send enough destination token to the router.
    deal(address(rETH.token), mockRouter, 2 * destAmount);

    for (uint256 i; i < srcTokens.length; i++) {
      // If the source token is the first token, then the minDestAmount will be the destination amount.
      // If the source token is not the first token, then the minDestAmount will be 0.
      swapStruct.srcData[0].srcTokenSwapDetails[i].aggregatorData.swapData = abi.encodeCall(
        MockGenerousRouter.swap,
        (
          swapStruct.srcData[0].srcTokenSwapDetails[i],
          SwapperStructs.DestData(destToken.token, (i == 0) ? destAmount : 0)
        )
      );
    }

    // Swap the source token to the destination token.
    swapperProxy.swap(swapStruct);

    // This swap shouldn't revert due to overflow when calling `safeIncreaseAllowance` in `_approveAndCallRouter`.
    swapperProxy.swap(swapStruct);
  }

  function _sourceAmountReturnTest(Token[] memory srcTokens, Token memory destToken) internal {
    address mockRouter = address(new MockGenerousRouter(0.5e18));

    // Add the mock router to the Swapper contract.
    vm.startPrank(admin);
    swapperProxy.addRouter(ONE_INCH_V6_ROUTER_KEY, mockRouter);

    uint256[] memory srcBalancesBefore = new uint256[](srcTokens.length);
    uint256 destBalanceBefore = destToken.token.balanceOf(alice);
    int8[TRANSFER_METHODS] memory transferMethodsIndices = [int8(uint8(srcTokens.length - 1)), -1, -1];
    Aggregator[] memory aggregators = new Aggregator[](srcTokens.length);

    for (uint256 i; i < srcTokens.length; i++) {
      srcBalancesBefore[i] = srcTokens[i].token.balanceOf(alice);
      aggregators[i] = Aggregator.ONE_INCH_V6;
    }

    (SwapperStructs.InOutData memory swapStruct, , ) = getSwapStruct(
      address(swapperProxy),
      srcTokens,
      destToken,
      transferMethodsIndices,
      aggregators
    );

    uint256 destAmount = swapStruct.destData.minDestAmount;
    uint256[] memory srcAmounts = new uint256[](srcTokens.length);

    vm.startPrank(alice);

    for (uint256 i; i < srcTokens.length; ++i) {
      srcAmounts[i] = swapStruct.srcData[0].srcTokenSwapDetails[i].amount;

      // Approve the source token to the swapper.
      srcTokens[i].token.approve(address(swapperProxy), srcAmounts[i]);
    }

    // Send enough destination token to the router.
    deal(address(rETH.token), mockRouter, destAmount);

    for (uint256 i; i < srcTokens.length; i++) {
      // If the source token is the first token, then the minDestAmount will be the destination amount.
      // If the source token is not the first token, then the minDestAmount will be 0.
      swapStruct.srcData[0].srcTokenSwapDetails[i].aggregatorData.swapData = abi.encodeCall(
        MockGenerousRouter.swap,
        (
          swapStruct.srcData[0].srcTokenSwapDetails[i],
          SwapperStructs.DestData(destToken.token, (i == 0) ? destAmount : 0)
        )
      );
    }

    // Swap the source token to the destination token.
    swapperProxy.swap(swapStruct);

    for (uint256 i; i < srcTokens.length; ++i) {
      // Check that the remaining source token amount is returned to the caller.
      assertEq(
        srcTokens[i].token.balanceOf(alice),
        srcBalancesBefore[i] - (srcAmounts[i] * MockGenerousRouter(mockRouter).generousPercent()) / 1e18,
        "Alice didn't receive the remaining source token amount"
      );

      // Check that the remaining source and destination token amounts are 0.
      assertEq(srcTokens[i].token.balanceOf(address(swapperProxy)), 0, "Remaining source token amount should be 0");
    }

    assertEq(
      destToken.token.balanceOf(alice),
      destBalanceBefore + destAmount,
      "Alice didn't receive enough destination token amount"
    );
    assertEq(destToken.token.balanceOf(address(swapperProxy)), 0, "Destination token amount should be 0");
  }
}
