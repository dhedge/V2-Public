// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

interface IGmxDepositUtils {
  // @dev CreateDepositParams struct used in createDeposit to avoid stack
  // too deep errors
  //
  // @param receiver the address to send the market tokens to
  // @param callbackContract the callback contract
  // @param uiFeeReceiver the ui fee receiver
  // @param market the market to deposit into
  // @param minMarketTokens the minimum acceptable number of liquidity tokens
  // @param shouldUnwrapNativeToken whether to unwrap the native token when
  // sending funds back to the user in case the deposit gets cancelled
  // @param executionFee the execution fee for keepers
  // @param callbackGasLimit the gas limit for the callbackContract
  struct CreateDepositParams {
    address receiver;
    address callbackContract;
    address uiFeeReceiver;
    address market;
    address initialLongToken;
    address initialShortToken;
    address[] longTokenSwapPath;
    address[] shortTokenSwapPath;
    uint256 minMarketTokens;
    bool shouldUnwrapNativeToken;
    uint256 executionFee;
    uint256 callbackGasLimit;
  }
}
