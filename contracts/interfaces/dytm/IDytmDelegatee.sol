// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

interface IDytmDelegatee {
  function onDelegationCallback(bytes calldata callbackData) external returns (bytes memory returnData);
}
