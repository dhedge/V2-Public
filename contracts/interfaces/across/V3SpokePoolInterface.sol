// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;

interface V3SpokePoolInterface {
  function deposit(
    bytes32 depositor,
    bytes32 recipient,
    bytes32 inputToken,
    bytes32 outputToken,
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 destinationChainId,
    bytes32 exclusiveRelayer,
    uint32 quoteTimestamp,
    uint32 fillDeadline,
    uint32 exclusivityParameter,
    bytes calldata message
  ) external payable;

  function depositV3(
    address depositor,
    address recipient,
    address inputToken,
    address outputToken,
    uint256 inputAmount,
    uint256 outputAmount,
    uint256 destinationChainId,
    address exclusiveRelayer,
    uint32 quoteTimestamp,
    uint32 fillDeadline,
    uint32 exclusivityDeadline,
    bytes calldata message
  ) external payable;

  function speedUpV3Deposit(
    address depositor,
    uint32 depositId,
    uint256 updatedOutputAmount,
    address updatedRecipient,
    bytes calldata updatedMessage,
    bytes calldata depositorSignature
  ) external;
}
