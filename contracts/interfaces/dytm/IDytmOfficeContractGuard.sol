// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IDytmOfficeContractGuard {
  function dytmOffice() external view returns (address);

  function dytmPeriphery() external view returns (address);

  function poolFactory() external view returns (address);

  function getOwnedTokenIds(address _poolLogic) external view returns (uint256[] memory);

  function isValidOwnedTokenId(address _poolLogic, uint256 _tokenId) external view returns (bool);

  function poolsWhitelist(address _pool) external view returns (bool);

  function dytmMarketsWhitelist(uint88 _market) external view returns (bool);
}
