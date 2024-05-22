// SPDX-License-Identifier: BSD-3-Clause
pragma solidity >=0.7.6 <=0.8.10;

import "./PriceOracle.sol";
import "./CTokenInterfaces.sol";

interface ComptrollerLensInterface {
  function markets(address) external view returns (bool, uint256);

  function oracle() external view returns (PriceOracle);

  function getAccountLiquidity(address) external view returns (uint256, uint256, uint256);

  function getAssetsIn(address) external view returns (CTokenInterface[] memory);

  function getCompAddress() external view returns (address);

  function claimComp(address) external;

  function compAccrued(address) external view returns (uint256);

  function compSpeeds(address) external view returns (uint256);

  function compSupplySpeeds(address) external view returns (uint256);

  function compBorrowSpeeds(address) external view returns (uint256);

  function borrowCaps(address) external view returns (uint256);

  function getExternalRewardDistributorAddress() external view returns (address);
}
