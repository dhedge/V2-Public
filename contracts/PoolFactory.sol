//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// MIT License
// ===========
//
// Copyright (c) 2020 dHEDGE DAO
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

pragma experimental ABIEncoderV2;

import "./PoolLogic.sol";
import "./upgradability/ProxyFactory.sol";
import "./interfaces/IAssetHandler.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IPoolLogic.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IHasPausable.sol";
import "./interfaces/IHasSupportedAsset.sol";

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/// @title A Factory to spawn pools
contract PoolFactory is
  PausableUpgradeable,
  ProxyFactory,
  IHasDaoInfo,
  IHasFeeInfo,
  IHasAssetInfo,
  IHasGuardInfo,
  IHasPausable
{
  using SafeMathUpgradeable for uint256;

  event FundCreated(
    address fundAddress,
    bool isPoolPrivate,
    string fundName,
    string managerName,
    address manager,
    uint256 time,
    uint256 managerFeeNumerator,
    uint256 managerFeeDenominator
  );

  event DaoAddressSet(address dao);
  event DaoFeeSet(uint256 numerator, uint256 denominator);

  event ExitFeeSet(uint256 numerator, uint256 denominator);
  event ExitCooldownSet(uint256 cooldown);

  event MaximumSupportedAssetCountSet(uint256 count);

  event LogUpgrade(address indexed manager, address indexed pool);

  address[] public deployedFunds;

  address internal _daoAddress;
  address internal _assetHandler;
  uint256 internal _daoFeeNumerator;
  uint256 internal _daoFeeDenominator;

  mapping(address => bool) public isPool;
  mapping(address => bool) public isPoolManager;

  uint256 private _MAXIMUM_MANAGER_FEE_NUMERATOR;
  uint256 private _MANAGER_FEE_DENOMINATOR;
  mapping(address => uint256) public poolManagerFeeNumerator;
  mapping(address => uint256) public poolManagerFeeDenominator;

  uint256 internal _exitCooldown;

  uint256 internal _maximumSupportedAssetCount;

  bytes32 internal _trackingCode;

  mapping(address => uint256) public poolVersion;
  uint256 public poolStorageVersion;

  uint256 public maximumManagerFeeNumeratorChange;
  uint256 public managerFeeNumeratorChangeDelay;

  // Transaction Guards
  mapping(address => address) internal contractGuards;
  mapping(uint8 => address) internal assetGuards;

  modifier onlyDao() {
    require(msg.sender == _daoAddress, "only dao");
    _;
  }

  function initialize(
    address _poolLogic,
    address _managerLogic,
    address assetHandler,
    address daoAddress
  ) public initializer {
    __ProxyFactory_init(_poolLogic, _managerLogic);
    __Pausable_init();

    _setAssetHandler(assetHandler);

    _setDaoAddress(daoAddress);

    _setMaximumManagerFee(5000, 10000);

    _setDaoFee(10, 100); // 10%
    _setExitCooldown(1 days);
    setManagerFeeNumeratorChangeDelay(4 weeks);
    setMaximumManagerFeeNumeratorChange(1000);

    _setMaximumSupportedAssetCount(10);

    _setTrackingCode(0x4448454447450000000000000000000000000000000000000000000000000000);
  }

  function createFund(
    bool _privatePool,
    address _manager,
    string memory _managerName,
    string memory _fundName,
    string memory _fundSymbol,
    uint256 _managerFeeNumerator,
    IHasSupportedAsset.Asset[] memory _supportedAssets
  ) public returns (address) {
    bytes memory poolLogicData =
      abi.encodeWithSignature(
        "initialize(address,bool,string,string)",
        address(this),
        _privatePool,
        _fundName,
        _fundSymbol
      );

    address fund = deploy(poolLogicData, 2);

    bytes memory managerLogicData =
      abi.encodeWithSignature(
        "initialize(address,address,string,address,(address,bool)[])",
        address(this),
        _manager,
        _managerName,
        fund,
        _supportedAssets
      );

    address managerLogic = deploy(managerLogicData, 1);
    // Ignore return value as want it to continue regardless
    IPoolLogic(fund).setPoolManagerLogic(managerLogic);

    deployedFunds.push(fund);
    isPool[fund] = true;
    isPoolManager[managerLogic] = true;

    poolVersion[fund] = poolStorageVersion;

    _setPoolManagerFee(fund, _managerFeeNumerator, _MANAGER_FEE_DENOMINATOR);

    emit FundCreated(
      fund,
      _privatePool,
      _fundName,
      _managerName,
      _manager,
      block.timestamp,
      _managerFeeNumerator,
      _MANAGER_FEE_DENOMINATOR
    );

    return fund;
  }

  // DAO info

  function getDaoAddress() public view override returns (address) {
    return _daoAddress;
  }

  function setDaoAddress(address daoAddress) public onlyOwner {
    _setDaoAddress(daoAddress);
  }

  function _setDaoAddress(address daoAddress) internal {
    _daoAddress = daoAddress;

    emit DaoAddressSet(daoAddress);
  }

  function setDaoFee(uint256 numerator, uint256 denominator) public onlyOwner {
    _setDaoFee(numerator, denominator);
  }

  function _setDaoFee(uint256 numerator, uint256 denominator) internal {
    require(numerator <= denominator, "invalid fraction");

    _daoFeeNumerator = numerator;
    _daoFeeDenominator = denominator;

    emit DaoFeeSet(numerator, denominator);
  }

  function getDaoFee() public view override returns (uint256, uint256) {
    return (_daoFeeNumerator, _daoFeeDenominator);
  }

  modifier onlyPool() {
    require(isPool[msg.sender], "Not a pool");
    _;
  }

  modifier onlyPoolManager() {
    require(isPoolManager[msg.sender], "Not a pool manager");
    _;
  }

  // Manager fees

  function getPoolManagerFee(address pool) external view override returns (uint256, uint256) {
    require(isPool[pool], "supplied address is not a pool");

    return (poolManagerFeeNumerator[pool], poolManagerFeeDenominator[pool]);
  }

  function setPoolManagerFeeNumerator(address pool, uint256 numerator) external override onlyPoolManager {
    // require(pool == msg.sender, "only a pool can change own fee");
    require(isPool[pool], "supplied address is not a pool");
    require(numerator <= poolManagerFeeNumerator[pool].add(maximumManagerFeeNumeratorChange), "manager fee too high");

    _setPoolManagerFee(pool, numerator, _MANAGER_FEE_DENOMINATOR);
  }

  function _setPoolManagerFee(
    address pool,
    uint256 numerator,
    uint256 denominator
  ) internal {
    require(numerator <= denominator && numerator <= _MAXIMUM_MANAGER_FEE_NUMERATOR, "invalid fraction");

    poolManagerFeeNumerator[pool] = numerator;
    poolManagerFeeDenominator[pool] = denominator;
  }

  function getMaximumManagerFee() public view returns (uint256, uint256) {
    return (_MAXIMUM_MANAGER_FEE_NUMERATOR, _MANAGER_FEE_DENOMINATOR);
  }

  function _setMaximumManagerFee(uint256 numerator, uint256 denominator) internal {
    require(numerator <= denominator, "invalid fraction");

    _MAXIMUM_MANAGER_FEE_NUMERATOR = numerator;
    _MANAGER_FEE_DENOMINATOR = denominator;
  }

  function setMaximumManagerFeeNumeratorChange(uint256 amount) public onlyOwner {
    maximumManagerFeeNumeratorChange = amount;
  }

  function getMaximumManagerFeeNumeratorChange() public view override returns (uint256) {
    return maximumManagerFeeNumeratorChange;
  }

  function setManagerFeeNumeratorChangeDelay(uint256 delay) public onlyOwner {
    managerFeeNumeratorChangeDelay = delay;
  }

  function getManagerFeeNumeratorChangeDelay() public view override returns (uint256) {
    return managerFeeNumeratorChangeDelay;
  }

  function setExitCooldown(uint256 cooldown) external onlyOwner {
    _setExitCooldown(cooldown);
  }

  function _setExitCooldown(uint256 cooldown) internal {
    _exitCooldown = cooldown;

    emit ExitCooldownSet(cooldown);
  }

  function getExitCooldown() external view override returns (uint256) {
    return _exitCooldown;
  }

  // Asset Info

  function setMaximumSupportedAssetCount(uint256 count) external onlyOwner {
    _setMaximumSupportedAssetCount(count);
  }

  function _setMaximumSupportedAssetCount(uint256 count) internal {
    _maximumSupportedAssetCount = count;

    emit MaximumSupportedAssetCountSet(count);
  }

  function getMaximumSupportedAssetCount() external view virtual override returns (uint256) {
    return _maximumSupportedAssetCount;
  }

  function isValidAsset(address asset) public view override returns (bool) {
    return IAssetHandler(_assetHandler).priceAggregators(asset) != address(0);
  }

  /**
   * Returns the latest price of a given asset
   */
  function getAssetPrice(address asset) external view override returns (uint256) {
    return IAssetHandler(_assetHandler).getUSDPrice(asset);
  }

  function getAssetType(address asset) external view override returns (uint8) {
    return IAssetHandler(_assetHandler).assetTypes(asset);
  }

  function getAssetHandler() public view returns (address) {
    return _assetHandler;
  }

  function setAssetHandler(address assetHandler) public onlyOwner {
    _setAssetHandler(assetHandler);
  }

  function _setAssetHandler(address assetHandler) internal {
    _assetHandler = assetHandler;
  }

  // Synthetix tracking

  function setTrackingCode(bytes32 code) external onlyOwner {
    _setTrackingCode(code);
  }

  function _setTrackingCode(bytes32 code) internal {
    _trackingCode = code;
  }

  function getTrackingCode() public view override returns (bytes32) {
    return _trackingCode;
  }

  // Upgrade

  /**
   * @dev Backdoor function
   * @param pool Address of the target.
   * @param data Calldata for the target address.
   * @param targetVersion set target version after call
   */
  function _upgradePool(
    address pool,
    bytes calldata data,
    uint256 targetVersion
  ) internal {
    require(pool != address(0), "target-invalid");
    require(data.length > 0, "data-invalid");
    bytes memory _data = data;
    assembly {
      let succeeded := delegatecall(gas(), pool, add(_data, 0x20), mload(_data), 0, 0)
      switch iszero(succeeded)
        case 1 {
          // throw if delegatecall failed
          let size := returndatasize()
          returndatacopy(0x00, 0x00, size)
          revert(0x00, size)
        }
    }
    emit LogUpgrade(msg.sender, pool);

    poolVersion[pool] = targetVersion;
  }

  function upgradePoolBatch(
    uint256 startIndex,
    uint256 endIndex,
    uint256 sourceVersion,
    uint256 targetVersion,
    bytes calldata data
  ) external onlyOwner {
    require(
      startIndex <= endIndex && startIndex < deployedFunds.length && endIndex < deployedFunds.length,
      "invalid bounds"
    );

    for (uint256 i = startIndex; i <= endIndex; i++) {
      address pool = deployedFunds[i];

      if (poolVersion[pool] != sourceVersion) continue;

      _upgradePool(pool, data, targetVersion);
    }
  }

  // Transaction Guards
  function getGuard(address extContract) public view override returns (address) {
    if (isValidAsset(extContract)) {
      uint8 assetType = IAssetHandler(_assetHandler).assetTypes(extContract);
      return assetGuards[assetType];
    }
    return contractGuards[extContract];
  }

  function setContractGuard(address extContract, address guardAddress) public onlyDao {
    _setContractGuard(extContract, guardAddress);
  }

  function _setContractGuard(address extContract, address guardAddress) internal {
    contractGuards[extContract] = guardAddress;
  }

  function setAssetGuard(uint8 assetType, address guardAddress) public onlyDao {
    _setAssetGuard(assetType, guardAddress);
  }

  function _setAssetGuard(uint8 assetType, address guardAddress) internal {
    assetGuards[assetType] = guardAddress;
  }

  function pause() public onlyDao {
    _pause();
  }

  function unpause() public onlyDao {
    _unpause();
  }

  function isPaused() public view override returns (bool) {
    return paused();
  }

  /// @notice Return full array of deployed funds
  /// @return full array of deployed funds
  function getDeployedFunds() public view returns (address[] memory) {
    return deployedFunds;
  }

  uint256[50] private __gap;
}
