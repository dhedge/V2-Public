// SPDX-License-Identifier: MIT
// solhint-disable
pragma solidity 0.8.28;

interface IAssetHandlerMock {
  function owner() external view returns (address);
  function setChainlinkTimeout(uint256 newTimeoutPeriod) external;
}
