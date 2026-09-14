// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/v5/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {ISignatureTransfer} from "contracts/interfaces/permit2/ISignatureTransfer.sol";
import "contracts/swappers/swapper/SwapperStructs.sol" as SwapperStructs;
import {AggregatorsAPIHelper} from "./AggregatorsAPIHelper.sol";
import {Permit2Helpers} from "./Permit2Helpers.sol";
import {SwapperTestSetup, Token} from "./SwapperTestSetup.sol";

abstract contract SwapperTestsHelper is SwapperTestSetup, AggregatorsAPIHelper, Permit2Helpers {
  using SafeERC20 for IERC20;

  struct SwapStructArrays {
    Token[] srcTokens;
    uint256[] srcAmounts;
    uint256[] priorSrcBalances;
    Token destToken;
    uint256 minDestAmount;
    uint256 priorDestBalance;
    bytes32[] routerKeys;
    bytes[] swapDatas;
  }

  uint256 internal nonce;

  function setUp() public virtual override {
    SwapperTestSetup.setUp();

    __AggregatorsAPIHelper_init(true);
  }

  function runAllAggregatorTests(
    Token[] memory srcTokens,
    Token memory destToken,
    SwapperStructs.TransferMethod transferMethod
  ) internal {
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

      testBuilder(address(swapperProxy), srcTokens, destToken, transferMethodsIndices, aggregators);
    }
  }

  /// @dev `transferTo` depends on which test suite is being run.
  ///       if it's that of `FlatZapper` then we pass the zapperProxy address.
  ///       if it's that of `Swapper` then we pass the swapperProxy address.
  function testBuilder(
    address transferTo,
    Token[] memory srcTokens,
    Token memory destToken,
    int8[TRANSFER_METHODS] memory transferMethodIndices,
    Aggregator[] memory aggregators
  ) internal {
    (
      SwapperStructs.InOutData memory swapStruct,
      SwapperStructs.SrcData[] memory srcDatas,
      SwapStructArrays memory swapStructArrays
    ) = getSwapStruct(transferTo, srcTokens, destToken, transferMethodIndices, aggregators);

    vm.startPrank(alice);

    // If the test uses simple allowance for source token transfers then approve the
    // swapperProxy to transfer the source tokens.
    for (uint8 i; i < srcDatas.length; ++i) {
      if (srcDatas[i].transferMethodData.method == SwapperStructs.TransferMethod.ALLOWANCE) {
        for (uint256 j; j < srcDatas[i].srcTokenSwapDetails.length; ++j) {
          srcDatas[i].srcTokenSwapDetails[j].token.safeIncreaseAllowance(
            address(swapperProxy),
            srcDatas[i].srcTokenSwapDetails[j].amount
          );
        }
      }
    }

    bool nativeSwapIncluded = transferMethodIndices[uint8(SwapperStructs.TransferMethod.NATIVE)] != -1;

    // If native swap is included in the transfer methods, then send the required amount of ETH to the swapperProxy.
    if (nativeSwapIncluded) {
      // Get the amount of ETH to be sent along with calling the `swap` function.
      uint256 ethAmount = srcDatas[uint256(int256(transferMethodIndices[uint8(SwapperStructs.TransferMethod.NATIVE)]))]
        .srcTokenSwapDetails[0]
        .amount;

      uint256 ethBalanceBefore = alice.balance;

      swapperProxy.swap{value: ethAmount}(swapStruct);

      // Check that the ETH balance of the caller has decreased by the amount sent.
      assertEq(alice.balance, ethBalanceBefore - ethAmount, "Alice's ETH balance incorrect");

      // Check that the ETH balance of the swapperProxy is 0 after swap.
      assertTrue(address(swapperProxy).balance == 0, "Swapper's ETH balance should be 0");
    } else {
      swapperProxy.swap(swapStruct);
    }

    // srcTokens balance check.
    for (uint8 i; i < srcTokens.length; ++i) {
      // If native swap is included and the source token is WETH, then skip the balance check.
      // Note: The balance check for WETH should be done somewhere upstream in case the multi swap is done with WETH as one of the source tokens.
      if (nativeSwapIncluded && address(srcTokens[i].token) == address(WETH.token)) {
        continue;
      }

      assertEq(
        swapStructArrays.srcTokens[i].token.balanceOf(alice),
        swapStructArrays.priorSrcBalances[i] - swapStructArrays.srcAmounts[i],
        "Alice's src balance incorrect"
      );
      assertTrue(
        swapStructArrays.srcTokens[i].token.balanceOf(address(swapperProxy)) == 0,
        "Swapper's src balance should be 0"
      );
    }

    // destToken balance check.
    assertGe(
      swapStructArrays.destToken.token.balanceOf(alice),
      swapStructArrays.priorDestBalance + swapStructArrays.minDestAmount,
      "Alice's dest balance incorrect"
    );
    assertTrue(
      swapStructArrays.destToken.token.balanceOf(address(swapperProxy)) == 0,
      "Swapper's dest balance should be 0"
    );
  }

  //////////////////////////
  //    Helper functions  //
  //////////////////////////

  function getSwapStruct(
    address to,
    Token[] memory srcTokens,
    Token memory destToken,
    int8[TRANSFER_METHODS] memory transferMethodIndices,
    Aggregator[] memory aggregators
  )
    internal
    returns (
      SwapperStructs.InOutData memory swapStruct,
      SwapperStructs.SrcData[] memory srcDatas,
      SwapStructArrays memory swapStructArrays
    )
  {
    swapStructArrays.srcAmounts = new uint256[](srcTokens.length);
    swapStructArrays.routerKeys = new bytes32[](srcTokens.length);
    swapStructArrays.swapDatas = new bytes[](srcTokens.length);
    swapStructArrays.priorSrcBalances = new uint256[](srcTokens.length);

    swapStructArrays.srcTokens = srcTokens;
    swapStructArrays.destToken = destToken;
    swapStructArrays.priorDestBalance = destToken.token.balanceOf(alice);

    for (uint256 i; i < srcTokens.length; ++i) {
      swapStructArrays.priorSrcBalances[i] = srcTokens[i].token.balanceOf(alice);
      swapStructArrays.srcAmounts[i] = getDefaultAmountInToken(srcTokens[i]);

      uint256 minDestAmount;

      (swapStructArrays.routerKeys[i], minDestAmount, swapStructArrays.swapDatas[i]) = _getDataFromAggregator(
        alice,
        srcTokens[i].token,
        destToken.token,
        swapStructArrays.srcAmounts[i],
        aggregators[i]
      );

      swapStructArrays.minDestAmount += minDestAmount;
    }

    srcDatas = getSrcDatas(
      to,
      swapStructArrays.srcTokens,
      swapStructArrays.srcAmounts,
      swapStructArrays.routerKeys,
      swapStructArrays.swapDatas,
      transferMethodIndices
    );
    SwapperStructs.DestData memory destData = SwapperStructs.DestData({
      destToken: destToken.token,
      minDestAmount: swapStructArrays.minDestAmount
    });

    swapStruct = SwapperStructs.InOutData({srcData: srcDatas, destData: destData});
  }

  /// @dev Specify the end index of the `srcTokens` array in the `transferMethodsIndices` array to use a specific
  ///      transfer method for all elements in the `srcTokens` upto that index.
  ///      The order of the transfer methods in the `transferMethodsIndices` array matches the order in the SwapperStructs.TransferMethod enum.
  ///      If you want to skip a `TransferMethod` then mention the end index of the same as -1.
  ///      For example:
  ///         (1) if you want to use `ALLOWANCE` for the first 2 `srcTokens` and `PERMIT` for the next 3 `srcTokens`, then
  ///             `transferMethodsIndices` should be [1, 4, -1].
  ///         (2) if you want to use `ALLOWANCE` for the first 2 `srcTokens` and `PERMIT2` for the next 2 `srcTokens`, then
  ///             `transferMethodsIndices` should be [1, -1, 3].
  function getSrcDatas(
    address to,
    Token[] memory srcTokens,
    uint256[] memory srcAmounts,
    bytes32[] memory routerKeys,
    bytes[] memory swapDatas,
    int8[TRANSFER_METHODS] memory transferMethodsIndices
  ) internal returns (SwapperStructs.SrcData[] memory srcDatas) {
    uint8 numSrcDatas; // Number of transfer methods used in the swap.
    for (uint8 i; i < TRANSFER_METHODS; ++i) {
      if (transferMethodsIndices[i] != -1) ++numSrcDatas;
    }

    srcDatas = new SwapperStructs.SrcData[](numSrcDatas);

    uint8 startIndex;
    uint8 srcDataIndex;
    for (uint8 i; i < TRANSFER_METHODS; ++i) {
      if (transferMethodsIndices[i] == -1) continue;

      uint8 endIndex = uint8(transferMethodsIndices[i]);
      SwapperStructs.SrcTokenSwapDetails[] memory srcTokenSwapDetails = new SwapperStructs.SrcTokenSwapDetails[](
        1 + endIndex - startIndex
      );

      uint8 srcTokenSwapDetailsIndex;
      for (uint8 j = startIndex; j <= endIndex; ++j) {
        srcTokenSwapDetails[srcTokenSwapDetailsIndex++] = SwapperStructs.SrcTokenSwapDetails({
          token: srcTokens[j].token,
          amount: srcAmounts[j],
          aggregatorData: SwapperStructs.AggregatorData({routerKey: routerKeys[j], swapData: swapDatas[j]})
        });
      }

      startIndex = endIndex + 1;
      srcDatas[srcDataIndex++] = getTransferMethodEncodedSrcData(
        to,
        SwapperStructs.TransferMethod(i),
        srcTokenSwapDetails
      );
    }
  }

  function getTransferMethodEncodedSrcData(
    address to,
    SwapperStructs.TransferMethod transferMethod,
    SwapperStructs.SrcTokenSwapDetails[] memory srcTokenSwapDetails
  ) internal returns (SwapperStructs.SrcData memory srcData) {
    if (
      transferMethod == SwapperStructs.TransferMethod.ALLOWANCE ||
      transferMethod == SwapperStructs.TransferMethod.NATIVE
    ) {
      return
        SwapperStructs.SrcData({
          srcTokenSwapDetails: srcTokenSwapDetails,
          transferMethodData: SwapperStructs.TransferMethodData({method: transferMethod, methodData: ""})
        });
    } else if (transferMethod == SwapperStructs.TransferMethod.PERMIT2) {
      bytes memory encodedPermit2Data;

      // If there is only one token to transfer, get a permit2 signature for that token.
      if (srcTokenSwapDetails.length == 1) {
        ISignatureTransfer.PermitTransferFrom memory permit = defaultERC20PermitTransfer(
          address(srcTokenSwapDetails[0].token),
          srcTokenSwapDetails[0].amount,
          nonce++
        );
        bytes memory sig = getPermitTransferSignature(permit, to, alicePrivateKey, DOMAIN_SEPARATOR);

        ISignatureTransfer.SignatureTransferDetails memory transferDetails = getTransferDetails(
          to,
          srcTokenSwapDetails[0].amount
        );

        encodedPermit2Data = abi.encode(
          SwapperStructs.Permit2EncodedData({
            transferType: SwapperStructs.Permit2TransferType.SINGLE_TRANSFER,
            encodedData: abi.encode(
              SwapperStructs.Permit2SingleTransfer({permit: permit, transferDetails: transferDetails, signature: sig})
            )
          })
        );
      } else {
        // Get permit2 signatures for multiple tokens.
        IERC20[] memory srcTokens = new IERC20[](srcTokenSwapDetails.length);
        uint256[] memory srcAmounts = new uint256[](srcTokenSwapDetails.length);
        for (uint256 i; i < srcTokenSwapDetails.length; ++i) {
          srcTokens[i] = srcTokenSwapDetails[i].token;
          srcAmounts[i] = srcTokenSwapDetails[i].amount;
        }

        ISignatureTransfer.PermitBatchTransferFrom memory permit = defaultERC20PermitMultiple(
          srcTokens,
          srcAmounts,
          nonce++
        );
        bytes memory sig = getPermitBatchTransferSignature(permit, to, alicePrivateKey, DOMAIN_SEPARATOR);

        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails = fillSigTransferDetails(to, srcAmounts);

        encodedPermit2Data = abi.encode(
          SwapperStructs.Permit2EncodedData({
            transferType: SwapperStructs.Permit2TransferType.BATCH_TRANSFER,
            encodedData: abi.encode(
              SwapperStructs.Permit2BatchTransfer({permit: permit, transferDetails: transferDetails, signature: sig})
            )
          })
        );
      }

      return
        SwapperStructs.SrcData({
          srcTokenSwapDetails: srcTokenSwapDetails,
          transferMethodData: SwapperStructs.TransferMethodData({
            method: transferMethod,
            methodData: encodedPermit2Data
          })
        });
    } else {
      revert("Unsupported or invalid transfer method");
    }
  }

  /// @dev Get the default amount in `token` denomination based on the token's decimals and globally set `DEFAULT_AMOUNT`.
  function getDefaultAmountInToken(Token memory token) internal view returns (uint256) {
    return
      (DEFAULT_AMOUNT * (10 ** (8 + IERC20Metadata(address(token.token)).decimals()))) /
      _getChainlinkPrice(token.priceFeed);
  }

  function _getDataFromAggregator(
    address user,
    IERC20 srcToken,
    IERC20 destToken,
    uint256 srcAmount,
    Aggregator aggregator
  ) private returns (bytes32 routerKey_, uint256 buyAmount_, bytes memory data_) {
    return _getDataFromAggregator(user, srcToken, destToken, srcAmount, DEFAULT_SLIPPAGE, aggregator);
  }

  function _getDataFromAggregator(
    address user,
    IERC20 srcToken,
    IERC20 destToken,
    uint256 srcAmount,
    uint8 slippage,
    Aggregator aggregator
  ) private returns (bytes32 routerKey_, uint256 buyAmount_, bytes memory data_) {
    if (aggregator == Aggregator.ONE_INCH_V6) {
      (buyAmount_, data_) = getDataFromOneInchV6(
        OneInchFunctionStruct({
          holder: address(swapperProxy),
          srcToken: srcToken,
          destToken: destToken,
          srcAmount: srcAmount,
          slippage: slippage
        })
      );
      routerKey_ = ONE_INCH_V6_ROUTER_KEY;
    } else if (aggregator == Aggregator.PARASWAP_V6) {
      (buyAmount_, data_) = getDataFromParaswapV6(
        ParaswapFunctionStruct({
          user: user,
          holder: address(swapperProxy),
          srcToken: srcToken,
          destToken: destToken,
          srcAmount: srcAmount,
          slippage: slippage * 100
        })
      );
      routerKey_ = PARASWAP_V6_ROUTER_KEY;
    } else if (aggregator == Aggregator.KYBER_SWAP_V2) {
      (buyAmount_, data_) = getDataFromKyberSwap(
        KyberSwapData({
          user: address(swapperProxy),
          srcToken: address(srcToken),
          destToken: address(destToken),
          srcAmount: srcAmount,
          slippageBPS: slippage * 100
        }),
        block.chainid
      );
      routerKey_ = KYBER_SWAP_V2_ROUTER_KEY;
    } else {
      revert("Invalid aggregator");
    }

    // The amount received from the API doesn't include slippage.
    // We need to adjust it to include slippage.
    buyAmount_ = (buyAmount_ * (100 - slippage) * 1e18) / 100e18;
  }

  function _getChainlinkPrice(IAggregatorV3Interface priceFeed) private view returns (uint256) {
    (, int256 price, , , ) = priceFeed.latestRoundData();

    assert(price > 0);

    return uint256(price);
  }
}
