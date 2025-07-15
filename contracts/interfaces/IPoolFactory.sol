// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface IPoolFactory {
  function governanceAddress() external view returns (address);

  function isPool(address pool) external view returns (bool);

  function customCooldownWhitelist(address from) external view returns (bool);

  function receiverWhitelist(address to) external view returns (bool);

  function emitPoolEvent() external;

  function emitPoolManagerEvent() external;

  function isValidAsset(address asset) external view returns (bool);

  function getAssetPrice(address asset) external view returns (uint256);

  function getAssetHandler() external view returns (address);
}
