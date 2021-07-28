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
// Copyright (c) 2021 dHEDGE DAO
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
// SPDX-License-Identifier: BUSL-1.1

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
import "./interfaces/IGovernance.sol";
import "./interfaces/IManaged.sol";

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title Pool Factory
/// @dev A Factory to spawn pools
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

  event DAOAddressSet(address daoAddress);

  event GovernanceAddressSet(address governanceAddress);

  event DaoFeeSet(uint256 numerator, uint256 denominator);

  event ExitFeeSet(uint256 numerator, uint256 denominator);

  event ExitCooldownSet(uint256 cooldown);

  event MaximumSupportedAssetCountSet(uint256 count);

  event LogUpgrade(address indexed manager, address indexed pool);

  event SetPoolManagerFee(uint256 numerator, uint256 denominator);

  event SetMaximumManagerFee(uint256 numerator, uint256 denominator);

  event SetMaximumManagerFeeNumeratorChange(uint256 amount);

  event SetAssetHandler(address assetHandler);

  event SetPoolStorageVersion(uint256 poolStorageVersion);

  event SetManagerFeeNumeratorChangeDelay(uint256 delay);

  address[] public deployedFunds;

  address public override daoAddress;
  address public governanceAddress;

  address internal _assetHandler;
  uint256 internal _daoFeeNumerator;
  uint256 internal _daoFeeDenominator;

  mapping(address => bool) public isPool;

  uint256 private _MAXIMUM_MANAGER_FEE_NUMERATOR;
  uint256 private _MANAGER_FEE_DENOMINATOR;

  uint256 internal _exitCooldown;

  uint256 internal _maximumSupportedAssetCount;

  mapping(address => uint256) public poolVersion;
  uint256 public poolStorageVersion;

  uint256 public override maximumManagerFeeNumeratorChange;
  uint256 public override managerFeeNumeratorChangeDelay;

  /// @notice Initialize the factory
  /// @param _poolLogic The pool logic address
  /// @param _managerLogic The manager logic address
  /// @param assetHandler The address of the asset handler
  /// @param _daoAddress The address of the DAO
  /// @param _governanceAddress The address of the governance contract
  function initialize(
    address _poolLogic,
    address _managerLogic,
    address assetHandler,
    address _daoAddress,
    address _governanceAddress
  ) external initializer {
    __ProxyFactory_init(_poolLogic, _managerLogic);
    __Pausable_init();

    _setAssetHandler(assetHandler);

    _setDAOAddress(_daoAddress);

    _setGovernanceAddress(_governanceAddress);

    _setMaximumManagerFee(5000, 10000);

    _setDaoFee(10, 100); // 10%
    _setExitCooldown(1 days);
    setManagerFeeNumeratorChangeDelay(4 weeks);
    setMaximumManagerFeeNumeratorChange(1000);

    _setMaximumSupportedAssetCount(10);

    _setPoolStorageVersion(230); // V2.3.0;
  }

  /// @notice Function to create a new fund
  /// @param _privatePool A boolean indicating whether the fund is private or not
  /// @param _manager A manager address
  /// @param _managerName The name of the manager
  /// @param _fundName The name of the fund
  /// @param _fundSymbol The symbol of the fund
  /// @param _managerFeeNumerator The numerator of the manager fee
  /// @param _supportedAssets An array of supported assets
  /// @return fund Address of the fund
  function createFund(
    bool _privatePool,
    address _manager,
    string memory _managerName,
    string memory _fundName,
    string memory _fundSymbol,
    uint256 _managerFeeNumerator,
    IHasSupportedAsset.Asset[] memory _supportedAssets
  ) external returns (address fund) {
    require(!paused(), "contracts paused");
    require(_supportedAssets.length <= _maximumSupportedAssetCount, "maximum assets reached");
    require(_managerFeeNumerator <= _MAXIMUM_MANAGER_FEE_NUMERATOR, "invalid manager fee");

    bytes memory poolLogicData =
      abi.encodeWithSignature(
        "initialize(address,bool,string,string)",
        address(this),
        _privatePool,
        _fundName,
        _fundSymbol
      );

    fund = deploy(poolLogicData, 2);

    bytes memory managerLogicData =
      abi.encodeWithSignature(
        "initialize(address,address,string,address,uint256,(address,bool)[])",
        address(this),
        _manager,
        _managerName,
        fund,
        _managerFeeNumerator,
        _supportedAssets
      );

    address managerLogic = deploy(managerLogicData, 1);
    // Ignore return value as want it to continue regardless
    IPoolLogic(fund).setPoolManagerLogic(managerLogic);

    deployedFunds.push(fund);
    isPool[fund] = true;

    poolVersion[fund] = poolStorageVersion;

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
  }

  // DAO info (Uber Pool)

  /// @notice Set the DAO address
  /// @param _daoAddress The address of the DAO
  function setDAOAddress(address _daoAddress) external onlyOwner {
    _setDAOAddress(_daoAddress);
  }

  /// @notice Set the DAO address internal call
  /// @param _daoAddress The address of the DAO
  function _setDAOAddress(address _daoAddress) internal {
    require(_daoAddress != address(0), "Invalid daoAddress");

    daoAddress = _daoAddress;

    emit DAOAddressSet(_daoAddress);
  }

  // Governance info

  /// @notice Set the governance address
  /// @param _governanceAddress The address of the governance contract
  function setGovernanceAddress(address _governanceAddress) external onlyOwner {
    _setGovernanceAddress(_governanceAddress);
  }

  /// @notice Set the governance address internal call
  /// @param _governanceAddress The address of the governance contract
  function _setGovernanceAddress(address _governanceAddress) internal {
    require(_governanceAddress != address(0), "Invalid governanceAddress");

    governanceAddress = _governanceAddress;

    emit GovernanceAddressSet(_governanceAddress);
  }

  /// @notice Set the DAO fee
  /// @param numerator The numerator of the DAO fee
  /// @param denominator The denominator of the DAO fee
  function setDaoFee(uint256 numerator, uint256 denominator) external onlyOwner {
    _setDaoFee(numerator, denominator);
  }

  /// @notice Set the DAO fee internal call
  /// @param numerator The numerator of the DAO fee
  /// @param denominator The denominator of the DAO fee
  function _setDaoFee(uint256 numerator, uint256 denominator) internal {
    require(numerator <= denominator, "invalid fraction");

    _daoFeeNumerator = numerator;
    _daoFeeDenominator = denominator;

    emit DaoFeeSet(numerator, denominator);
  }

  /// @notice Get the DAO fee
  /// @return The numerator of the DAO fee
  /// @return The denominator of the DAO fee
  function getDaoFee() external view override returns (uint256, uint256) {
    return (_daoFeeNumerator, _daoFeeDenominator);
  }

  // Manager fees

  /// @notice Get the maximum manager fee
  /// @return The maximum manager fee numerator
  /// @return The maximum manager fee denominator
  function getMaximumManagerFee() external view override returns (uint256, uint256) {
    return (_MAXIMUM_MANAGER_FEE_NUMERATOR, _MANAGER_FEE_DENOMINATOR);
  }

  /// @notice Set the maximum manager fee
  /// @param numerator The numerator of the maximum manager fee
  function setMaximumManagerFee(uint256 numerator) external onlyOwner {
    _setMaximumManagerFee(numerator, _MANAGER_FEE_DENOMINATOR);
  }

  /// @notice Set the maximum manager fee internal call
  /// @param numerator The numerator of the maximum manager fee
  /// @param denominator The denominator of the maximum manager fee
  function _setMaximumManagerFee(uint256 numerator, uint256 denominator) internal {
    require(numerator <= denominator, "invalid fraction");

    _MAXIMUM_MANAGER_FEE_NUMERATOR = numerator;
    _MANAGER_FEE_DENOMINATOR = denominator;

    emit SetMaximumManagerFee(numerator, denominator);
  }

  /// @notice Set maximum manager fee numberator change
  /// @param amount The amount for the maximum manager fee numerator change
  function setMaximumManagerFeeNumeratorChange(uint256 amount) public onlyOwner {
    maximumManagerFeeNumeratorChange = amount;

    emit SetMaximumManagerFeeNumeratorChange(amount);
  }

  /// @notice Set manager fee numberator change delay
  /// @param delay The delay in seconds for the manager fee numerator change
  function setManagerFeeNumeratorChangeDelay(uint256 delay) public onlyOwner {
    managerFeeNumeratorChangeDelay = delay;

    emit SetManagerFeeNumeratorChangeDelay(delay);
  }

  /// @notice Set exit cool down time (in seconds)
  /// @param cooldown The cool down time in seconds
  function setExitCooldown(uint256 cooldown) external onlyOwner {
    _setExitCooldown(cooldown);
  }

  /// @notice Set exit cool down time (in seconds) internal call
  /// @param cooldown The cool down time in seconds
  function _setExitCooldown(uint256 cooldown) internal {
    _exitCooldown = cooldown;

    emit ExitCooldownSet(cooldown);
  }

  /// @notice Get the exit cool down time (in seconds)
  /// @return The exit cool down time in seconds
  function getExitCooldown() external view override returns (uint256) {
    return _exitCooldown;
  }

  // Asset Info

  /// @notice Set maximum supported asset count
  /// @param count The maximum supported asset count
  function setMaximumSupportedAssetCount(uint256 count) external onlyOwner {
    _setMaximumSupportedAssetCount(count);
  }

  /// @notice Set maximum supported asset count internal call
  /// @param count The maximum supported asset count
  function _setMaximumSupportedAssetCount(uint256 count) internal {
    _maximumSupportedAssetCount = count;

    emit MaximumSupportedAssetCountSet(count);
  }

  /// @notice Get maximum supported asset count
  /// @return The maximum supported asset count
  function getMaximumSupportedAssetCount() external view virtual override returns (uint256) {
    return _maximumSupportedAssetCount;
  }

  /// @notice Return boolean if the asset is supported
  /// @return True if it's valid asset, false otherwise
  function isValidAsset(address asset) public view override returns (bool) {
    return IAssetHandler(_assetHandler).priceAggregators(asset) != address(0);
  }

  /// @notice Return the latest price of a given asset
  /// @param asset The address of the asset
  /// @return price The latest price of a given asset
  function getAssetPrice(address asset) external view override returns (uint256 price) {
    price = IAssetHandler(_assetHandler).getUSDPrice(asset);
  }

  /// @notice Return type of the asset
  /// @param asset The address of the asset
  /// @return assetType The type of the asset
  function getAssetType(address asset) external view override returns (uint16 assetType) {
    assetType = IAssetHandler(_assetHandler).assetTypes(asset);
  }

  /// @notice Return the address of the asset handler
  /// @return Address of the asset handler
  function getAssetHandler() external view returns (address) {
    return _assetHandler;
  }

  /// @notice Set the asset handler address
  /// @param assetHandler The address of the asset handler
  function setAssetHandler(address assetHandler) external onlyOwner {
    _setAssetHandler(assetHandler);
  }

  /// @notice Set the asset handler address internal call
  /// @param assetHandler The address of the asset handler
  function _setAssetHandler(address assetHandler) internal {
    require(assetHandler != address(0), "Invalid assetHandler");

    _assetHandler = assetHandler;

    emit SetAssetHandler(assetHandler);
  }

  // Upgrade

  /// @notice Set the pool storage version
  /// @param _poolStorageVersion The pool storage version
  function setPoolStorageVersion(uint256 _poolStorageVersion) external onlyOwner {
    _setPoolStorageVersion(_poolStorageVersion);
  }

  /// @notice Set the pool storage version internal call
  /// @param _poolStorageVersion The pool storage version
  function _setPoolStorageVersion(uint256 _poolStorageVersion) internal {
    require(_poolStorageVersion > poolStorageVersion, "version needs to be higher");

    poolStorageVersion = _poolStorageVersion;

    emit SetPoolStorageVersion(_poolStorageVersion);
  }

  /**
   * @notice Backdoor function
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

  /// @notice Upgrade pools in batch
  /// @param startIndex The start index of the pool upgrade
  /// @param endIndex The end index of the pool upgrade
  /// @param sourceVersion The source version of the pool upgrade
  /// @param targetVersion The target version of the pool upgrade
  /// @param data The calldata for the target address
  function upgradePoolBatch(
    uint256 startIndex,
    uint256 endIndex,
    uint256 sourceVersion,
    uint256 targetVersion,
    bytes calldata data
  ) external onlyOwner {
    require(startIndex <= endIndex && endIndex < deployedFunds.length, "invalid bounds");

    for (uint256 i = startIndex; i <= endIndex; i++) {
      address pool = deployedFunds[i];

      if (poolVersion[pool] != sourceVersion) continue;

      _upgradePool(pool, data, targetVersion);
    }
  }

  /// @notice call the pause the contract
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice call the unpause the contract
  function unpause() external onlyOwner {
    _unpause();
  }

  /// @notice Return the pause status
  /// @return The pause status
  function isPaused() external view override returns (bool) {
    return paused();
  }

  // Transaction Guards

  /// @notice Get address of the transaction guard
  /// @param extContract The address of the external contract
  /// @return guard Return the address of the transaction guard
  function getGuard(address extContract) external view override returns (address guard) {
    guard = IGovernance(governanceAddress).contractGuards(extContract);
    if (guard == address(0)) {
      guard = getAssetGuard(extContract);
    }
  }

  /// @notice Get address of the asset guard
  /// @param extAsset The address of the external asset
  /// @return guard Address of the asset guard
  function getAssetGuard(address extAsset) public view override returns (address guard) {
    if (isValidAsset(extAsset)) {
      uint16 assetType = IAssetHandler(_assetHandler).assetTypes(extAsset);
      guard = IGovernance(governanceAddress).assetGuards(assetType);
    }
  }

  /// @notice Get address from the Governance contract
  /// @param name The name of the address
  /// @return destination The destination address
  function getAddress(bytes32 name) external view override returns (address destination) {
    destination = IGovernance(governanceAddress).nameToDestination(name);
    require(destination != address(0), "governance: invalid name");
  }

  /// @notice Return full array of deployed funds
  /// @return Full array of deployed funds
  function getDeployedFunds() external view returns (address[] memory) {
    return deployedFunds;
  }

  /**
   * @notice Returns all invested pools by a given user
   * @param user the user address
   * @return investedPools All invested pools by a given user
   */
  function getInvestedPools(address user) external view returns (address[] memory investedPools) {
    uint256 length = deployedFunds.length;
    investedPools = new address[](length);
    uint256 index = 0;
    for (uint256 i = 0; i < length; i++) {
      if (IERC20Upgradeable(deployedFunds[i]).balanceOf(user) > 0) {
        investedPools[index] = deployedFunds[i];
        index++;
      }
    }

    uint256 reduceLength = length.sub(index);
    assembly {
      mstore(investedPools, sub(mload(investedPools), reduceLength))
    }
  }

  /**
   * @notice Returns all managed pools by a given manager
   * @param manager The manager address
   * @return managedPools All managed pools by a given manager
   */
  function getManagedPools(address manager) external view returns (address[] memory managedPools) {
    uint256 length = deployedFunds.length;
    managedPools = new address[](length);
    uint256 index = 0;
    for (uint256 i = 0; i < length; i++) {
      address poolManagerLogic = IPoolLogic(deployedFunds[i]).poolManagerLogic();
      if (IManaged(poolManagerLogic).manager() == manager) {
        managedPools[index] = deployedFunds[i];
        index++;
      }
    }

    uint256 reduceLength = length.sub(index);
    assembly {
      mstore(managedPools, sub(mload(managedPools), reduceLength))
    }
  }

  uint256[50] private __gap;
}
