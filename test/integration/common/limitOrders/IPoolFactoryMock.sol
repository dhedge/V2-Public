// SPDX-License-Identifier: MIT
// solhint-disable
pragma solidity 0.8.28;

library IHasSupportedAssetMock {
  struct Asset {
    address asset;
    bool isDeposit;
  }
}

interface IPoolFactoryMock {
  function addReceiverWhitelist(address _extAddress) external;
  function createFund(
    bool _privatePool,
    address _manager,
    string memory _managerName,
    string memory _fundName,
    string memory _fundSymbol,
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    IHasSupportedAssetMock.Asset[] memory _supportedAssets
  ) external returns (address fund);
  function getAssetHandler() external view returns (address);
}
