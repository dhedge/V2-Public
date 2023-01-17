// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IAggregationRouterV5 {
  struct SwapDescription {
    address srcToken;
    address dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
  }

  function swap(
    IAggregationExecutor executor,
    SwapDescription calldata desc,
    bytes calldata permit,
    bytes calldata data
  ) external payable returns (uint256 returnAmount, uint256 spentAmount);

  function unoswap(
    address srcToken,
    uint256 amount,
    uint256 minReturn,
    uint256[] calldata pools
  ) external payable returns (uint256 returnAmount);

  function uniswapV3Swap(
    uint256 amount,
    uint256 minReturn,
    uint256[] calldata pools
  ) external payable returns (uint256 returnAmount);

  function uniswapV3SwapTo(
    address payable recipient,
    uint256 amount,
    uint256 minReturn,
    uint256[] calldata pools
  ) external payable returns (uint256 returnAmount);
}

interface IAggregationExecutor {
  /// @notice propagates information about original msg.sender and executes arbitrary data
  function execute(address msgSender) external payable; // 0x4b64e492
}
