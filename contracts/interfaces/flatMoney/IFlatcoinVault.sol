// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IFlatcoinVault {
  function collateral() external view returns (address collateralAsset);

  function moduleAddress(bytes32 _moduleKey) external view returns (address module);

  function owner() external view returns (address);
}
