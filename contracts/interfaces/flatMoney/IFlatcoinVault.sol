// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IFlatcoinVault {
  struct Position {
    uint256 averagePrice;
    uint256 marginDeposited;
    uint256 additionalSize;
    int256 entryCumulativeFunding;
  }

  function collateral() external view returns (address collateralAsset);

  function moduleAddress(bytes32 _moduleKey) external view returns (address module);

  function owner() external view returns (address);

  function getPosition(uint256 _tokenId) external view returns (Position memory position);
}
