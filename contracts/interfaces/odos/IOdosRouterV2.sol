// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IOdosRouterV2 {
  /// @dev Contains all information needed to describe the input and output for a swap
  struct SwapTokenInfo {
    address inputToken;
    uint256 inputAmount;
    address inputReceiver;
    address outputToken;
    uint256 outputQuote;
    uint256 outputMin;
    address outputReceiver;
  }

  /// @notice Custom decoder to swap with compact calldata for efficient execution on L2s
  function swapCompact() external payable returns (uint256);

  /// @notice Externally facing interface for swapping two tokens
  /// @param tokenInfo All information about the tokens being swapped
  /// @param pathDefinition Encoded path definition for executor
  /// @param executor Address of contract that will execute the path
  /// @param referralCode referral code to specify the source of the swap
  function swap(
    SwapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  ) external payable returns (uint256 amountOut);
}
