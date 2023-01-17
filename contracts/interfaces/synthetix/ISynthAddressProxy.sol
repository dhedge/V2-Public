// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface ISynthTarget {
  function currencyKey() external view returns (bytes32);
}

interface ISynthAddressProxy {
  function target() external view returns (ISynthTarget synthAsset);

  function approve(address spender, uint256 amount) external returns (bool);

  function balanceOf(address user) external view returns (uint256);
}
