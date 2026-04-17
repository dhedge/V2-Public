// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import {IHasSupportedAsset} from "./IHasSupportedAsset.sol";

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

  function addCustomCooldownWhitelist(address _extAddress) external;

  function createFund(
    bool _privatePool,
    address _manager,
    string memory _managerName,
    string memory _fundName,
    string memory _fundSymbol,
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _entryFeeNumerator,
    uint256 _exitFeeNum,
    IHasSupportedAsset.Asset[] memory _supportedAssets
  ) external returns (address);

  function initialize(
    address _poolLogic,
    address _poolManagerLogic,
    address _assetHandler,
    address _daoAddress,
    address _governanceAddress
  ) external;

  function dataValidator() external view returns (address);

  function valueManipulationCheck() external view returns (address);

  function referralManager() external view returns (address);
}
