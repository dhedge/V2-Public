// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IPriceOracle {
  function getAssetPrice(address _asset) external view returns (uint256);
}
