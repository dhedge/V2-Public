// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ILeverageModuleV2} from "./ILeverageModuleV2.sol";

interface IFlatcoinVaultV2 {
  function collateral() external view returns (address collateralAsset);

  function moduleAddress(bytes32 moduleKey) external view returns (address module);

  function getPosition(uint256 tokenId) external view returns (ILeverageModuleV2.Position memory position);

  function owner() external view returns (address);

  function setSkewFractionMax(uint256 newSkewFractionMax) external;

  function isPositionOpenWhitelisted(address account) external view returns (bool whitelisted);
}
