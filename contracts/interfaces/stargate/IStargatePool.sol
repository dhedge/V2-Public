// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IStargatePool {
  function poolId() external view returns (uint256);

  function token() external view returns (address);

  function router() external view returns (address);

  function amountLPtoLD(uint256 amountLP) external view returns (uint256 amountLD);

  function localDecimals() external view returns (uint256 decimals);

  function balanceOf(address owner) external view returns (uint256);
}
