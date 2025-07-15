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
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ProxyFactory} from "./upgradability/ProxyFactory.sol";
import {IAssetHandler} from "./interfaces/IAssetHandler.sol";
import {IHasDaoInfo} from "./interfaces/IHasDaoInfo.sol";
import {IHasFeeInfo} from "./interfaces/IHasFeeInfo.sol";
import {IHasAssetInfo} from "./interfaces/IHasAssetInfo.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "./interfaces/IPoolManagerLogic.sol";
import {IHasGuardInfo} from "./interfaces/IHasGuardInfo.sol";
import {IHasPausable} from "./interfaces/IHasPausable.sol";
import {IHasSupportedAsset} from "./interfaces/IHasSupportedAsset.sol";
import {IGovernance} from "./interfaces/IGovernance.sol";
import {IManaged} from "./interfaces/IManaged.sol";

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

  struct PoolPausedInput {
    address pool;
    bool pauseShares; // Disable any pool tokens movement
    bool pauseTrading; // Solely for disabling _execTransaction
  }

  event FundCreated(
    address fundAddress,
    bool isPoolPrivate,
    string fundName,
    string managerName,
    address manager,
    uint256 time,
    uint256 performanceFeeNumerator,
    uint256 managerFeeNumerator,
    uint256 managerFeeDenominator
  );

  event PoolEvent(address poolAddress);

  event PoolManagerEvent(address poolManagerAddress);

  event DAOAddressSet(address daoAddress);

  event GovernanceAddressSet(address governanceAddress);

  event DaoFeeSet(uint256 numerator, uint256 denominator);

  event ExitCooldownSet(uint256 cooldown);

  event MaximumSupportedAssetCountSet(uint256 count);

  event SetMaximumFee(
    uint256 performanceFeeNumerator,
    uint256 managerFeeNumerator,
    uint256 entryFeeNumerator,
    uint256 exitFeeNumerator,
    uint256 denominator
  );

  event SetMaximumPerformanceFeeNumeratorChange(uint256 amount);

  event SetAssetHandler(address assetHandler);

  event SetPerformanceFeeNumeratorChangeDelay(uint256 delay);

  event PoolPauseStatusChanged(address pool, bool pausedShares, bool pausedTrading);

  address[] public deployedFunds;

  address public override daoAddress;
  address public governanceAddress;

  address internal _assetHandler;
  uint256 internal _daoFeeNumerator;
  uint256 internal _daoFeeDenominator;

  mapping(address => bool) public isPool;

  uint256 private maximumPerformanceFeeNumerator;
  // solhint-disable-next-line var-name-mixedcase
  uint256 private _MANAGER_FEE_DENOMINATOR;

  uint256 internal _exitCooldown;

  uint256 internal _maximumSupportedAssetCount;

  mapping(address => uint256) public poolVersion; // Deprecated
  uint256 public poolStorageVersion; // Deprecated

  uint256 public override maximumPerformanceFeeNumeratorChange;
  uint256 public override performanceFeeNumeratorChangeDelay;

  // Added after initial deployment
  address public poolPerformanceAddress; // Deprecated
  uint256 private _exitFeeNumerator; // Deprecated here but similar thing is used in PoolManagerLogic
  uint256 private _exitFeeDenominator; // Deprecated here but similar thing is used in PoolManagerLogic

  // Allows to perform pool deposit with lockup cooldown passed as param
  mapping(address => bool) public customCooldownWhitelist;

  // Management (or streaming) fee is referred to as manager fee (backward compatibility)
  uint256 private maximumManagerFeeNumerator;

  // A list of addresses that can receive tokens that are still under a lockup
  mapping(address => bool) public receiverWhitelist;

  uint256 private maximumEntryFeeNumerator;

  // If true, pool deposits, withdrawals, fee mints and pool token transfers are disabled
  mapping(address => bool) public override pausedPools;

  uint256 private maximumExitFeeNumerator;

  mapping(address => bool) public override tradingPausedPools;

  /// @notice Initialize the factory
  /// @param _poolLogic The pool logic address
  /// @param _managerLogic The manager logic address
  /// @param _assetHandlerAddress The address of the asset handler
  /// @param _daoAddress The address of the DAO
  /// @param _governanceAddress The address of the governance contract
  function initialize(
    address _poolLogic,
    address _managerLogic,
    address _assetHandlerAddress,
    address _daoAddress,
    address _governanceAddress
  ) external initializer {
    __ProxyFactory_init(_poolLogic, _managerLogic);
    __Pausable_init();

    _setAssetHandler(_assetHandlerAddress);
    _setDAOAddress(_daoAddress);
    _setGovernanceAddress(_governanceAddress);
    _setMaximumFee(5000, 300, 100, 100, 10000); // 50% performance fee, 3% management fee, 1% entry fee, 1% exit fee
    _setDaoFee(10, 100); // 10%
    _setExitCooldown(1 days);
    setPerformanceFeeNumeratorChangeDelay(2 weeks);
    setMaximumPerformanceFeeNumeratorChange(1000);
    _setMaximumSupportedAssetCount(12);
  }

  modifier onlyPool() {
    require(isPool[msg.sender] == true, "only pools");
    _;
  }

  modifier onlyPoolManager() {
    address poolLogic = IPoolManagerLogic(msg.sender).poolLogic();
    require(isPool[poolLogic] == true && IPoolLogic(poolLogic).poolManagerLogic() == msg.sender, "only managers");
    _;
  }

  /// @notice Function to create a new fund
  /// @param _privatePool A boolean indicating whether the fund is private or not
  /// @param _manager A manager address
  /// @param _managerName The name of the manager
  /// @param _fundName The name of the fund
  /// @param _fundSymbol The symbol of the fund
  /// @param _performanceFeeNumerator The numerator of the performance fee
  /// @param _managerFeeNumerator The numerator of the management fee
  /// @param _supportedAssets An array of supported assets
  /// @return fund Address of the fund
  function createFund(
    bool _privatePool,
    address _manager,
    string memory _managerName,
    string memory _fundName,
    string memory _fundSymbol,
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    IHasSupportedAsset.Asset[] memory _supportedAssets
  ) external returns (address fund) {
    require(!paused(), "contracts paused");

    bytes memory poolLogicData = abi.encodeWithSignature(
      "initialize(address,bool,string,string)",
      address(this),
      _privatePool,
      _fundName,
      _fundSymbol
    );

    fund = deploy(poolLogicData, 2);

    bytes memory managerLogicData = abi.encodeWithSignature(
      "initialize(address,address,string,address,uint256,uint256,(address,bool)[])",
      address(this),
      _manager,
      _managerName,
      fund,
      _performanceFeeNumerator,
      _managerFeeNumerator,
      _supportedAssets
    );

    address managerLogic = deploy(managerLogicData, 1);
    IPoolLogic(fund).setPoolManagerLogic(managerLogic);

    deployedFunds.push(fund);
    isPool[fund] = true;

    emit FundCreated(
      fund,
      _privatePool,
      _fundName,
      _managerName,
      _manager,
      block.timestamp,
      _performanceFeeNumerator,
      _managerFeeNumerator,
      _MANAGER_FEE_DENOMINATOR
    );
  }

  /// @notice Add an address to the whitelist
  /// @dev allows address to perform pool deposit with custom lockup cooldown
  /// @param _extAddress The address to add to whitelist
  function addCustomCooldownWhitelist(address _extAddress) external onlyOwner {
    customCooldownWhitelist[_extAddress] = true;
  }

  /// @notice Remove an address from the whitelist
  /// @dev allows address to perform pool deposit with custom lockup cooldown
  /// @param _extAddress The address to remove from whitelist
  function removeCustomCooldownWhitelist(address _extAddress) external onlyOwner {
    customCooldownWhitelist[_extAddress] = false;
  }

  /// @notice Add an address to the whitelist
  /// @dev allows address to receive tokens that are under lockup
  /// @param _extAddress The address to add to whitelist
  function addReceiverWhitelist(address _extAddress) external onlyOwner {
    receiverWhitelist[_extAddress] = true;
  }

  /// @notice Remove an address from the whitelist
  /// @dev disallows address to receive tokens that are under lockup
  /// @param _extAddress The address to remove from whitelist
  function removeReceiverWhitelist(address _extAddress) external onlyOwner {
    receiverWhitelist[_extAddress] = false;
  }

  // DAO info

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

  function _setGovernanceAddress(address _governanceAddress) internal {
    require(_governanceAddress != address(0), "Invalid governanceAddress");

    governanceAddress = _governanceAddress;

    emit GovernanceAddressSet(_governanceAddress);
  }

  /// @notice Set the DAO fee
  /// @param _numerator The numerator of the DAO fee
  /// @param _denominator The denominator of the DAO fee
  function setDaoFee(uint256 _numerator, uint256 _denominator) external onlyOwner {
    _setDaoFee(_numerator, _denominator);
  }

  function _setDaoFee(uint256 _numerator, uint256 _denominator) internal {
    require(_numerator <= _denominator, "invalid fraction");

    _daoFeeNumerator = _numerator;
    _daoFeeDenominator = _denominator;

    emit DaoFeeSet(_numerator, _denominator);
  }

  /// @notice Get the DAO fee
  /// @return The numerator of the DAO fee
  /// @return The denominator of the DAO fee
  function getDaoFee() external view override returns (uint256, uint256) {
    return (_daoFeeNumerator, _daoFeeDenominator);
  }

  // Manager fees

  /// @notice Get the maximum manager fee
  /// @return The maximum performance fee numerator
  /// @return The maximum management fee numerator
  /// @return The maximum entry fee numerator
  /// @return The maximum exit fee numerator
  /// @return The maximum fee denominator
  function getMaximumFee() external view override returns (uint256, uint256, uint256, uint256, uint256) {
    return (
      maximumPerformanceFeeNumerator,
      maximumManagerFeeNumerator,
      maximumEntryFeeNumerator,
      maximumExitFeeNumerator,
      _MANAGER_FEE_DENOMINATOR
    );
  }

  /// @notice Set maximum manager fees
  /// @param _maxPerformanceFeeNumerator The numerator of the maximum performance fee
  /// @param _maxManagerFeeNumerator The numerator of the maximum management fee
  /// @param _maxEntryFeeNumerator The numerator of the maximum entry fee
  /// @param _maxExitFeeNumerator The numerator of the maximum exit fee
  function setMaximumFee(
    uint256 _maxPerformanceFeeNumerator,
    uint256 _maxManagerFeeNumerator,
    uint256 _maxEntryFeeNumerator,
    uint256 _maxExitFeeNumerator
  ) external onlyOwner {
    _setMaximumFee(
      _maxPerformanceFeeNumerator,
      _maxManagerFeeNumerator,
      _maxEntryFeeNumerator,
      _maxExitFeeNumerator,
      _MANAGER_FEE_DENOMINATOR
    );
  }

  function _setMaximumFee(
    uint256 _maxPerformanceFeeNumerator,
    uint256 _maxManagerFeeNumerator,
    uint256 _maxEntryFeeNumerator,
    uint256 _maxExitFeeNumerator,
    uint256 _denominator
  ) internal {
    require(
      _maxPerformanceFeeNumerator <= _denominator &&
        _maxManagerFeeNumerator <= _denominator &&
        _maxEntryFeeNumerator <= _denominator &&
        _maxExitFeeNumerator <= _denominator,
      "invalid fraction"
    );

    maximumPerformanceFeeNumerator = _maxPerformanceFeeNumerator;
    maximumManagerFeeNumerator = _maxManagerFeeNumerator;
    maximumEntryFeeNumerator = _maxEntryFeeNumerator;
    maximumExitFeeNumerator = _maxExitFeeNumerator;
    _MANAGER_FEE_DENOMINATOR = _denominator;

    emit SetMaximumFee(
      _maxPerformanceFeeNumerator,
      _maxManagerFeeNumerator,
      _maxEntryFeeNumerator,
      _maxExitFeeNumerator,
      _denominator
    );
  }

  /// @notice Set maximum performance fee change
  /// @param _amount The amount for the maximum performance fee numerator change
  function setMaximumPerformanceFeeNumeratorChange(uint256 _amount) public onlyOwner {
    maximumPerformanceFeeNumeratorChange = _amount;

    emit SetMaximumPerformanceFeeNumeratorChange(_amount);
  }

  /// @notice Set manager fees increase delay
  /// @param _delay The delay in seconds for the manager fees numerator increase
  function setPerformanceFeeNumeratorChangeDelay(uint256 _delay) public onlyOwner {
    performanceFeeNumeratorChangeDelay = _delay;

    emit SetPerformanceFeeNumeratorChangeDelay(_delay);
  }

  /// @notice Set exit cool down time (in seconds)
  /// @param _cooldown The lockup time in seconds
  function setExitCooldown(uint256 _cooldown) external onlyOwner {
    _setExitCooldown(_cooldown);
  }

  function _setExitCooldown(uint256 _cooldown) internal {
    _exitCooldown = _cooldown;

    emit ExitCooldownSet(_cooldown);
  }

  /// @notice Get the exit cool down time (in seconds)
  /// @return The exit cool down time in seconds
  function getExitCooldown() external view override returns (uint256) {
    return _exitCooldown;
  }

  // Asset Info

  /// @notice Set maximum supported asset count
  /// @param _count The maximum supported asset count
  function setMaximumSupportedAssetCount(uint256 _count) external onlyOwner {
    _setMaximumSupportedAssetCount(_count);
  }

  function _setMaximumSupportedAssetCount(uint256 _count) internal {
    _maximumSupportedAssetCount = _count;

    emit MaximumSupportedAssetCountSet(_count);
  }

  /// @notice Get maximum supported asset count
  /// @return The maximum supported asset count
  function getMaximumSupportedAssetCount() external view virtual override returns (uint256) {
    return _maximumSupportedAssetCount;
  }

  /// @notice Return boolean if the asset is supported
  /// @param _asset The address of the asset
  /// @return True if it's valid asset, false otherwise
  function isValidAsset(address _asset) public view override returns (bool) {
    return IAssetHandler(_assetHandler).priceAggregators(_asset) != address(0);
  }

  /// @notice Return the latest price of a given asset
  /// @param _asset The address of the asset
  /// @return price The latest price of a given asset
  function getAssetPrice(address _asset) external view override returns (uint256 price) {
    price = IAssetHandler(_assetHandler).getUSDPrice(_asset);
  }

  /// @notice Return type of the asset
  /// @param _asset The address of the asset
  /// @return assetType The type of the asset
  function getAssetType(address _asset) external view override returns (uint16 assetType) {
    assetType = IAssetHandler(_assetHandler).assetTypes(_asset);
  }

  /// @notice Return the address of the asset handler
  /// @return Address of the asset handler
  function getAssetHandler() external view returns (address) {
    return _assetHandler;
  }

  /// @notice Set the asset handler address
  /// @param _handler The address of the asset handler
  function setAssetHandler(address _handler) external onlyOwner {
    _setAssetHandler(_handler);
  }

  function _setAssetHandler(address _handler) internal {
    require(_handler != address(0), "Invalid assetHandler");

    _assetHandler = _handler;

    emit SetAssetHandler(_handler);
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

  /// @notice Set the pause status of the pool
  /// @param _pools The array of pool paused info
  /// @dev This function is used to pause/unpause the pool
  /// @dev The pool can be paused/unpaused by the owner only
  function setPoolsPaused(PoolPausedInput[] calldata _pools) external onlyOwner {
    uint256 poolsLength = _pools.length;
    for (uint256 i; i < poolsLength; ++i) {
      PoolPausedInput memory poolInfo = _pools[i];
      require(isPool[poolInfo.pool], "invalid pool");
      pausedPools[poolInfo.pool] = poolInfo.pauseShares;
      tradingPausedPools[poolInfo.pool] = poolInfo.pauseTrading;

      emit PoolPauseStatusChanged(poolInfo.pool, poolInfo.pauseShares, poolInfo.pauseTrading);
    }
  }

  // Transaction Guards

  /// @notice Get address of the contract guard
  /// @param _extContract The address of the external contract
  /// @return guard Return the address of the transaction guard
  function getContractGuard(address _extContract) external view override returns (address guard) {
    guard = IGovernance(governanceAddress).contractGuards(_extContract);
  }

  /// @notice Get address of the asset guard
  /// @param _extAsset The address of the external asset
  /// @return guard Address of the asset guard
  function getAssetGuard(address _extAsset) external view override returns (address guard) {
    if (isValidAsset(_extAsset)) {
      uint16 assetType = IAssetHandler(_assetHandler).assetTypes(_extAsset);
      guard = IGovernance(governanceAddress).assetGuards(assetType);
    }
  }

  /// @notice Return full array of deployed funds
  /// @return Full array of deployed funds
  function getDeployedFunds() external view returns (address[] memory) {
    return deployedFunds;
  }

  /// @notice Returns all invested pools by a given user
  /// @param _user the user address
  /// @return investedPools All invested pools by a given user
  function getInvestedPools(address _user) external view returns (address[] memory investedPools) {
    uint256 length = deployedFunds.length;
    investedPools = new address[](length);
    uint256 index = 0;
    for (uint256 i = 0; i < length; i++) {
      if (IPoolLogic(deployedFunds[i]).balanceOf(_user) > 0) {
        investedPools[index] = deployedFunds[i];
        index++;
      }
    }

    uint256 reduceLength = length.sub(index);
    assembly {
      mstore(investedPools, sub(mload(investedPools), reduceLength))
    }
  }

  /// @notice Returns all managed pools by a given manager
  /// @param _manager The manager address
  /// @return managedPools All managed pools by a given manager
  function getManagedPools(address _manager) external view returns (address[] memory managedPools) {
    uint256 length = deployedFunds.length;
    managedPools = new address[](length);
    uint256 index = 0;
    for (uint256 i = 0; i < length; i++) {
      address poolManagerLogic = IPoolLogic(deployedFunds[i]).poolManagerLogic();
      if (IManaged(poolManagerLogic).manager() == _manager) {
        managedPools[index] = deployedFunds[i];
        index++;
      }
    }

    uint256 reduceLength = length.sub(index);
    assembly {
      mstore(managedPools, sub(mload(managedPools), reduceLength))
    }
  }

  /// @notice Allows us to just listen to the PoolFactory for all pool events
  function emitPoolEvent() external onlyPool {
    emit PoolEvent(msg.sender);
  }

  /// @notice Allows us to just listen to the PoolFactory for all poolManager events
  function emitPoolManagerEvent() external onlyPoolManager {
    emit PoolManagerEvent(msg.sender);
  }

  // The Factory is not safe to be inherited by other contracts
  // uint256[47] private __gap;
}
