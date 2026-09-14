// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "contracts/swappers/swapper/SwapperStructs.sol" as SwapperStructs;
import {TokenTransferMethods} from "contracts/swappers/swapper/TokenTransferMethods.sol";
import {SwapperTestsHelper} from "./SwapperTestsHelper.sol";
import {Token} from "./SwapperTestSetup.sol";
import {TokenArrayBuilder} from "./TokenArrayBuilder.sol";

abstract contract SwapperNativeETHSwapIntegrationTest is SwapperTestsHelper {
  using TokenArrayBuilder for *;

  function test_integration_swap_single_in_single_out_native_eth_swap() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, WETH);
    Token memory destToken = rETH;

    runAllAggregatorTests({
      srcTokens: srcTokens,
      destToken: destToken,
      transferMethod: SwapperStructs.TransferMethod.NATIVE
    });
  }

  function test_integration_swap_multi_in_single_out_with_different_transfer_methods() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, USDC).push(DAI).push(WETH);
    Token memory destToken = rETH;

    Aggregator[] memory aggregators = new Aggregator[](srcTokens.length);
    int8[TRANSFER_METHODS] memory transferMethodsIndices = [int8(0), int8(1), int8(2)];

    for (uint8 i; i < TOTAL_AGGREGATORS; ++i) {
      for (uint256 j; j < srcTokens.length; ++j) {
        aggregators[j] = Aggregator(i);
      }

      testBuilder(address(swapperProxy), srcTokens, destToken, transferMethodsIndices, aggregators);
    }
  }

  function test_integration_revert_invalid_ETH_srcTokenSwapDetails_encoding_duplicate_WETH_swapdata() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(2, WETH);
    Token memory destToken = rETH;

    Aggregator[] memory aggregators = new Aggregator[](srcTokens.length);
    int8[TRANSFER_METHODS] memory transferMethodsIndices = [int8(-1), -1, 1];

    for (uint8 i; i < TOTAL_AGGREGATORS; ++i) {
      for (uint256 j; j < srcTokens.length; ++j) {
        aggregators[j] = Aggregator(i);
      }

      (SwapperStructs.InOutData memory swapStruct, , ) = getSwapStruct(
        address(swapperProxy),
        srcTokens,
        destToken,
        transferMethodsIndices,
        aggregators
      );

      vm.startPrank(alice);

      uint256 defaultAmount = getDefaultAmountInToken(WETH);

      vm.expectRevert(TokenTransferMethods.InvalidNativeTokenTransferEncoding.selector);

      swapperProxy.swap{value: defaultAmount}(swapStruct);
    }
  }

  function test_integration_revert_invalid_ETH_srcTokenSwapDetails_encoding_invalid_srcToken() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, USDC);
    Token memory destToken = rETH;

    Aggregator[] memory aggregators = new Aggregator[](srcTokens.length);
    int8[TRANSFER_METHODS] memory transferMethodsIndices = [int8(-1), -1, 0];

    for (uint8 i; i < TOTAL_AGGREGATORS; ++i) {
      for (uint256 j; j < srcTokens.length; ++j) {
        aggregators[j] = Aggregator(i);
      }

      (SwapperStructs.InOutData memory swapStruct, , ) = getSwapStruct(
        address(swapperProxy),
        srcTokens,
        destToken,
        transferMethodsIndices,
        aggregators
      );

      vm.startPrank(alice);

      vm.expectRevert(TokenTransferMethods.InvalidNativeTokenTransferEncoding.selector);

      swapperProxy.swap{value: 1e18}(swapStruct);
    }
  }

  /// @dev Checks that when you send ETH without actually intending to swap ETH, the swap is reverted.
  function test_integration_revert_ETH_sent_wrongly_without_ETH_transfer_data() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, USDC);
    Token memory destToken = rETH;
    SwapperStructs.TransferMethod transferMethod = SwapperStructs.TransferMethod.PERMIT2;

    Aggregator[] memory aggregators = new Aggregator[](srcTokens.length);
    int8[TRANSFER_METHODS] memory transferMethodsIndices;

    for (uint8 i; i < TRANSFER_METHODS; ++i) {
      if (i == uint8(transferMethod)) transferMethodsIndices[i] = int8(uint8(srcTokens.length - 1));
      else transferMethodsIndices[i] = -1;
    }

    for (uint8 i; i < TOTAL_AGGREGATORS; ++i) {
      for (uint256 j; j < srcTokens.length; ++j) {
        aggregators[j] = Aggregator(i);
      }

      (SwapperStructs.InOutData memory swapStruct, , ) = getSwapStruct(
        address(swapperProxy),
        srcTokens,
        destToken,
        transferMethodsIndices,
        aggregators
      );

      vm.startPrank(alice);

      uint256 defaultAmount = getDefaultAmountInToken(WETH);

      vm.expectRevert(TokenTransferMethods.NativeTokenSentWithoutNativeSwap.selector);

      swapperProxy.swap{value: defaultAmount}(swapStruct);
    }
  }

  /// @dev The Swapper contract allows for simple collateralAsset swaps. If ETH is sent without a native asset swap intention then the swap should
  ///      be reverted.
  function test_integration_revert_when_swapping_WETH_without_ETH_native_swap_included_and_ETH_is_sent() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, WETH);
    Token memory destToken = rETH;
    SwapperStructs.TransferMethod transferMethod = SwapperStructs.TransferMethod.PERMIT2;

    Aggregator[] memory aggregators = new Aggregator[](srcTokens.length);
    int8[TRANSFER_METHODS] memory transferMethodsIndices;

    for (uint8 i; i < TRANSFER_METHODS; ++i) {
      if (i == uint8(transferMethod)) transferMethodsIndices[i] = int8(uint8(srcTokens.length - 1));
      else transferMethodsIndices[i] = -1;
    }

    for (uint8 i; i < TOTAL_AGGREGATORS; ++i) {
      for (uint256 j; j < srcTokens.length; ++j) {
        aggregators[j] = Aggregator(i);
      }

      (SwapperStructs.InOutData memory swapStruct, , ) = getSwapStruct(
        address(swapperProxy),
        srcTokens,
        destToken,
        transferMethodsIndices,
        aggregators
      );

      vm.startPrank(alice);

      uint256 defaultAmount = getDefaultAmountInToken(WETH);

      vm.expectRevert(TokenTransferMethods.NativeTokenSentWithoutNativeSwap.selector);

      swapperProxy.swap{value: defaultAmount}(swapStruct);
    }
  }

  function test_integration_revert_when_not_enough_ETH_sent() public {
    Token[] memory srcTokens = TokenArrayBuilder.fill(1, WETH);
    Token memory destToken = rETH;

    Aggregator[] memory aggregators = new Aggregator[](srcTokens.length);
    int8[TRANSFER_METHODS] memory transferMethodsIndices = [int8(-1), -1, 0];

    for (uint8 i; i < TOTAL_AGGREGATORS; ++i) {
      for (uint256 j; j < srcTokens.length; ++j) {
        aggregators[j] = Aggregator(i);
      }

      (SwapperStructs.InOutData memory swapStruct, , ) = getSwapStruct(
        address(swapperProxy),
        srcTokens,
        destToken,
        transferMethodsIndices,
        aggregators
      );

      vm.startPrank(alice);

      uint256 defaultAmount = getDefaultAmountInToken(WETH);

      vm.expectRevert(
        abi.encodeWithSelector(
          TokenTransferMethods.NotEnoughNativeTokenSent.selector,
          defaultAmount,
          (defaultAmount / 2)
        )
      );

      swapperProxy.swap{value: (defaultAmount / 2)}(swapStruct);
    }
  }
}
