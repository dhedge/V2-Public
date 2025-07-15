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
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "./interfaces/IPoolManagerLogic.sol";
import {IHasAssetInfo} from "./interfaces/IHasAssetInfo.sol";
import {IHasFeeInfo} from "./interfaces/IHasFeeInfo.sol";
import {IHasGuardInfo} from "./interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "./interfaces/IHasSupportedAsset.sol";
import {IHasOwnable} from "./interfaces/IHasOwnable.sol";
import {IAssetGuard} from "./interfaces/guards/IAssetGuard.sol";
import {IAddAssetCheckGuard} from "./interfaces/guards/IAddAssetCheckGuard.sol";
import {IPoolFactory} from "./interfaces/IPoolFactory.sol";
import {Managed} from "./Managed.sol";

/// @notice Logic implmentation for pool management
contract PoolManagerLogic is Initializable, IPoolManagerLogic, IHasSupportedAsset, Managed {
  using SafeMathUpgradeable for uint256;

  event AssetAdded(address indexed fundAddress, address manager, address asset, bool isDeposit);

  event AssetRemoved(address fundAddress, address manager, address asset);

  event ManagerFeeSet(
    address fundAddress,
    address manager,
    uint256 performanceFeeNumerator,
    uint256 managerFeeNumerator,
    uint256 entryFeeNumerator,
    uint256 exitFeeNumerator,
    uint256 denominator
  );

  event ManagerFeeIncreaseAnnounced(
    uint256 performanceFeeNumerator,
    uint256 managerFeeNumerator,
    uint256 entryFeeNumerator,
    uint256 exitFeeNumerator,
    uint256 announcedFeeActivationTime
  );

  event ManagerFeeIncreaseRenounced();

  event PoolLogicSet(address poolLogic, address from);

  event MinDepositUpdated(uint256 minDepositUSD);

  address public override factory;
  address public override poolLogic;

  Asset[] public supportedAssets;
  mapping(address => uint256) public assetPosition; // maps the asset to its 1-based position

  // Fee increase announcement
  uint256 public announcedPerformanceFeeNumerator;
  uint256 public announcedFeeIncreaseTimestamp;
  uint256 public performanceFeeNumerator;
  // Management (or streaming) fee is referred to as manager fee (backward compatibility)
  uint256 public announcedManagerFeeNumerator;
  uint256 public managerFeeNumerator;

  // Should be in Managed.sol but not upgradable
  address public nftMembershipCollectionAddress;

  uint256 public override minDepositUSD;

  uint256 public announcedEntryFeeNumerator;
  uint256 public entryFeeNumerator;

  uint256 public announcedExitFeeNumerator;
  uint256 public exitFeeNumerator;

  // By default, traders can change supported assets.
  bool public traderAssetChangeDisabled;

  /// @notice initialize the pool manager
  /// @param _factory address of the factory
  /// @param _manager address of the manager
  /// @param _managerName name of the manager
  /// @param _poolLogic address of the pool logic
  /// @param _performanceFeeNumerator numerator of the performance fee
  /// @param _managerFeeNumerator numerator of the management fee
  /// @param _supportedAssets array of supported assets
  function initialize(
    address _factory,
    address _manager,
    string calldata _managerName,
    address _poolLogic,
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    Asset[] calldata _supportedAssets
  ) external initializer {
    require(_factory != address(0), "Invalid factory");
    require(_manager != address(0), "Invalid manager");
    require(_poolLogic != address(0), "Invalid poolLogic");
    _initialize(_manager, _managerName);

    factory = _factory;
    poolLogic = _poolLogic;
    _setFeeNumerator(_performanceFeeNumerator, _managerFeeNumerator, 0, 0); // By default entry and exit fees will be set to 0%.
    _changeAssets(_supportedAssets, new address[](0));
  }

  /// @notice Checks if the asset is enabled in the pool
  /// @param _asset address of the asset
  /// @return true if the asset is supported, false otherwise
  function isSupportedAsset(address _asset) public view override returns (bool) {
    return assetPosition[_asset] != 0;
  }

  /// @notice Checks if the asset can be used for deposits into the pool
  /// @param _asset address of the asset
  /// @return true if the asset is a deposit asset, false otherwise
  function isDepositAsset(address _asset) external view override returns (bool) {
    uint256 index = assetPosition[_asset];

    return index != 0 && supportedAssets[index.sub(1)].isDeposit;
  }

  /// @notice Checks if the asset is supported within the system
  /// @param _asset address of the asset
  /// @return true if the asset is valid, false otherwise
  function validateAsset(address _asset) public view override returns (bool) {
    return IHasAssetInfo(factory).isValidAsset(_asset);
  }

  /// @notice Change assets of the pool
  /// @param _addAssets array of assets to add
  /// @param _removeAssets array of asset addresses to remove
  function changeAssets(Asset[] calldata _addAssets, address[] calldata _removeAssets) external {
    /* solhint-disable reason-string */
    require(
      (msg.sender == trader && !traderAssetChangeDisabled) ||
        msg.sender == manager ||
        msg.sender == IHasOwnable(factory).owner(),
      "only manager, owner or trader enabled"
    );
    /* solhint-enable reason-string */

    _changeAssets(_addAssets, _removeAssets);
    _emitFactoryEvent();
  }

  /// @notice Change assets of the pool internal call
  /// @param _addAssets array of assets to add
  /// @param _removeAssets array of asset addresses to remove
  function _changeAssets(Asset[] calldata _addAssets, address[] memory _removeAssets) internal {
    for (uint8 i = 0; i < _removeAssets.length; i++) {
      _removeAsset(_removeAssets[i]);
    }

    for (uint8 i = 0; i < _addAssets.length; i++) {
      _addAsset(_addAssets[i]);
    }

    require(supportedAssets.length <= IHasAssetInfo(factory).getMaximumSupportedAssetCount(), "maximum assets reached");

    require(getDepositAssets().length >= 1, "at least one deposit asset");
  }

  /// @notice Add an asset to the pool
  /// @param _asset an asset struct
  function _addAsset(Asset calldata _asset) internal {
    address asset = _asset.asset;
    bool isDeposit = _asset.isDeposit;

    require(validateAsset(asset), "invalid asset");
    // Pools with price aggregators cannot add other pools as assets
    require(!validateAsset(poolLogic) || !IPoolFactory(factory).isPool(asset), "cannot add pool asset");

    address guard = IHasGuardInfo(factory).getAssetGuard(asset);
    if (guard != address(0)) {
      // solhint-disable-next-line avoid-low-level-calls
      (bool hasFunction, bytes memory answer) = guard.call(abi.encodeWithSignature("isAddAssetCheckGuard()"));
      if (hasFunction && abi.decode(answer, (bool))) {
        IAddAssetCheckGuard(guard).addAssetCheck(poolLogic, _asset);
      }
    }

    if (isSupportedAsset(asset)) {
      uint256 index = assetPosition[asset].sub(1);
      supportedAssets[index].isDeposit = isDeposit;
    } else {
      uint256 i = supportedAssets.length;
      supportedAssets.push(_asset);
      assetPosition[asset] = i.add(1); // adjusting the index because the map stores 1-based
      uint16 assetType = IHasAssetInfo(factory).getAssetType(asset);
      for (i; i > 0 && IHasAssetInfo(factory).getAssetType(supportedAssets[i.sub(1)].asset) < assetType; i--) {
        Asset memory temp = supportedAssets[i];
        supportedAssets[i] = supportedAssets[i.sub(1)];
        assetPosition[supportedAssets[i].asset] = i.add(1);
        supportedAssets[i.sub(1)] = temp;
        assetPosition[supportedAssets[i.sub(1)].asset] = i;
      }
    }

    emit AssetAdded(poolLogic, manager, asset, isDeposit);
  }

  /// @notice Remove asset from the pool
  /// @dev use asset address to remove from supportedAssets
  /// @param _asset asset address
  function _removeAsset(address _asset) internal {
    require(isSupportedAsset(_asset), "asset not supported");

    address guard = IHasGuardInfo(factory).getAssetGuard(_asset);
    if (guard != address(0)) {
      // should be able to remove any deprecated assets
      require(assetBalance(_asset) == 0, "cannot remove non-empty asset");
      IAssetGuard(guard).removeAssetCheck(poolLogic, _asset);
    }

    uint256 index = assetPosition[_asset].sub(1); // adjusting the index because the map stores 1-based
    uint256 length = supportedAssets.length;
    for (uint256 i = index; i.add(1) < length; i++) {
      Asset memory temp = supportedAssets[i];
      supportedAssets[i] = supportedAssets[i.add(1)];
      assetPosition[supportedAssets[i].asset] = i.add(1);
      supportedAssets[i.add(1)] = temp;
      assetPosition[supportedAssets[i.add(1)].asset] = i.add(2);
    }

    assetPosition[supportedAssets[length.sub(1)].asset] = 0;
    supportedAssets.pop();

    emit AssetRemoved(poolLogic, manager, _asset);
  }

  /// @notice Get all the supported assets
  /// @return Return array of supported assets
  function getSupportedAssets() external view override returns (Asset[] memory) {
    return supportedAssets;
  }

  /// @notice Get all the deposit assets
  /// @return Return array of deposit assets' addresses
  function getDepositAssets() public view returns (address[] memory) {
    uint256 assetCount = supportedAssets.length;
    address[] memory depositAssets = new address[](assetCount);
    uint8 index = 0;
    for (uint8 i = 0; i < assetCount; i++) {
      if (supportedAssets[i].isDeposit) {
        depositAssets[index] = supportedAssets[i].asset;
        index++;
      }
    }
    // Reduce length for withdrawnAssets to remove the empty items
    uint256 reduceLength = assetCount.sub(index);
    assembly {
      mstore(depositAssets, sub(mload(depositAssets), reduceLength))
    }
    return depositAssets;
  }

  /// @notice Get asset balance including any staked balance in external contracts
  /// @param _asset address of the asset
  /// @return balance of the asset
  function assetBalance(address _asset) public view override returns (uint256 balance) {
    address guard = IHasGuardInfo(factory).getAssetGuard(_asset);
    balance = IAssetGuard(guard).getBalance(poolLogic, _asset);
  }

  /// @notice Get asset decimal
  /// @param _asset address of the asset
  /// @return decimal of the asset
  function assetDecimal(address _asset) public view returns (uint256 decimal) {
    address guard = IHasGuardInfo(factory).getAssetGuard(_asset);
    decimal = IAssetGuard(guard).getDecimals(_asset);
  }

  /// @notice Get value of the asset
  /// @param _asset address of the asset
  /// @param _amount amount of the asset
  /// @return value of the asset
  function assetValue(address _asset, uint256 _amount) public view override returns (uint256 value) {
    uint256 price = IHasAssetInfo(factory).getAssetPrice(_asset);
    uint256 decimals = assetDecimal(_asset);

    value = price.mul(_amount).div(10 ** decimals);
  }

  /// @notice Get value of the asset
  /// @param _asset address of the asset
  /// @return value of the asset
  function assetValue(address _asset) public view override returns (uint256 value) {
    value = assetValue(_asset, assetBalance(_asset));
  }

  /// @notice Return the fund composition of the pool
  /// @dev Return assets, balances of the asset and their prices
  /// @return assets array of supported assets
  /// @return balances balances of each asset
  /// @return rates price of each asset in USD
  function getFundComposition()
    external
    view
    returns (Asset[] memory assets, uint256[] memory balances, uint256[] memory rates)
  {
    uint256 assetCount = supportedAssets.length;
    assets = new Asset[](assetCount);
    balances = new uint256[](assetCount);
    rates = new uint256[](assetCount);

    for (uint8 i = 0; i < assetCount; i++) {
      address asset = supportedAssets[i].asset;
      balances[i] = assetBalance(asset);
      assets[i] = supportedAssets[i];
      rates[i] = IHasAssetInfo(factory).getAssetPrice(asset);
    }
  }

  /// @notice Return the total fund value of the pool
  /// @dev Calculate the total fund value from the supported assets
  /// @return total value in USD
  function totalFundValue() external view override returns (uint256 total) {
    uint256 assetCount = supportedAssets.length;

    for (uint256 i; i < assetCount; ++i) {
      total = total.add(assetValue(supportedAssets[i].asset));
    }
  }

  /* ========== MANAGER FEES ========== */

  /// @notice Return the manager fees
  /// @return performanceFeeNumerator numerator of the performance fee
  /// @return managerFeeNumerator numerator of the management fee
  /// @return entryFeeNumerator numerator of the entry fee
  /// @return exitFeeNumerator numerator of the exit fee
  /// @return managerFeeDenominator denominator of the fees
  function getFee() external view override returns (uint256, uint256, uint256, uint256, uint256) {
    (, , , , uint256 managerFeeDenominator) = IHasFeeInfo(factory).getMaximumFee();
    return (performanceFeeNumerator, managerFeeNumerator, entryFeeNumerator, exitFeeNumerator, managerFeeDenominator);
  }

  /// @notice Get maximum manager fee
  /// @return maximumPerformanceFeeNumerator numerator of the maximum performance fee
  /// @return maximumManagerFeeNumerator numerator of the maximum management fee
  /// @return maximumEntryFeeNumerator numerator of the maximum entry fee
  /// @return maximumExitFeeNumerator numerator of the maximum exit fee
  /// @return managerFeeDenominator denominator of the fees
  function getMaximumFee() public view returns (uint256, uint256, uint256, uint256, uint256) {
    return IHasFeeInfo(factory).getMaximumFee();
  }

  /// @notice Get maximum performance fee change
  /// @return change maximum performance fee change
  function getMaximumPerformanceFeeChange() public view returns (uint256 change) {
    change = IHasFeeInfo(factory).maximumPerformanceFeeNumeratorChange();
  }

  /// @notice Manager can decrease fees in a single transaction
  /// @param _performanceFeeNumerator The decreased numerator of the performance fee
  /// @param _managerFeeNumerator The decreased numerator of the management fee
  /// @param _entryFeeNumerator The decreased numerator of the entry fee
  /// @param _exitFeeNumerator The decreased numerator of the exit fee
  function setFeeNumerator(
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _entryFeeNumerator,
    uint256 _exitFeeNumerator
  ) external onlyManager {
    require(
      _performanceFeeNumerator <= performanceFeeNumerator &&
        _managerFeeNumerator <= managerFeeNumerator &&
        _entryFeeNumerator <= entryFeeNumerator &&
        _exitFeeNumerator <= exitFeeNumerator,
      "manager fee too high"
    );
    _setFeeNumerator(_performanceFeeNumerator, _managerFeeNumerator, _entryFeeNumerator, _exitFeeNumerator);
    _emitFactoryEvent();
  }

  function _setFeeNumerator(
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _entryFeeNumerator,
    uint256 _exitFeeNumerator
  ) internal {
    (
      uint256 maximumPerformanceFeeNumerator,
      uint256 maximumManagerFeeNumerator,
      uint256 maximumEntryFeeNumerator,
      uint256 maximumExitFeeNumerator,
      uint256 denominator
    ) = getMaximumFee();
    require(
      _performanceFeeNumerator <= maximumPerformanceFeeNumerator &&
        _managerFeeNumerator <= maximumManagerFeeNumerator &&
        _entryFeeNumerator <= maximumEntryFeeNumerator &&
        _exitFeeNumerator <= maximumExitFeeNumerator,
      "invalid manager fee"
    );

    performanceFeeNumerator = _performanceFeeNumerator;
    managerFeeNumerator = _managerFeeNumerator;
    entryFeeNumerator = _entryFeeNumerator;
    exitFeeNumerator = _exitFeeNumerator;

    emit ManagerFeeSet(
      poolLogic,
      manager,
      _performanceFeeNumerator,
      _managerFeeNumerator,
      _entryFeeNumerator,
      _exitFeeNumerator,
      denominator
    );
  }

  /// @notice Manager can announce an increase to the fees
  /// @dev The commit to the new fees can happen after a time delay
  ///      The new performance fee cannot exceed the current performance fee by more than the maximum allowed change
  /// @param _performanceFeeNumerator The numerator of the new performance fee
  /// @param _managerFeeNumerator The numerator of the new management fee
  /// @param _entryFeeNumerator The numerator of the new entry fee
  /// @param _exitFeeNumerator The numerator of the new exit fee
  function announceFeeIncrease(
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _entryFeeNumerator,
    uint256 _exitFeeNumerator
  ) external onlyManager {
    (
      uint256 maximumPerformanceFeeNumerator,
      uint256 maximumManagerFeeNumerator,
      uint256 maximumEntryFeeNumerator,
      uint256 maximumExitFeeNumerator,

    ) = getMaximumFee();
    uint256 maximumAllowedChange = getMaximumPerformanceFeeChange();

    require(
      _performanceFeeNumerator <= maximumPerformanceFeeNumerator &&
        _managerFeeNumerator <= maximumManagerFeeNumerator &&
        _entryFeeNumerator <= maximumEntryFeeNumerator &&
        _exitFeeNumerator <= maximumExitFeeNumerator &&
        _performanceFeeNumerator <= performanceFeeNumerator.add(maximumAllowedChange),
      "exceeded allowed increase"
    );

    uint256 feeChangeDelay = IHasFeeInfo(factory).performanceFeeNumeratorChangeDelay();

    announcedPerformanceFeeNumerator = _performanceFeeNumerator;
    announcedManagerFeeNumerator = _managerFeeNumerator;
    announcedEntryFeeNumerator = _entryFeeNumerator;
    announcedExitFeeNumerator = _exitFeeNumerator;
    announcedFeeIncreaseTimestamp = block.timestamp + feeChangeDelay;

    emit ManagerFeeIncreaseAnnounced(
      _performanceFeeNumerator,
      _managerFeeNumerator,
      _entryFeeNumerator,
      _exitFeeNumerator,
      announcedFeeIncreaseTimestamp
    );

    _emitFactoryEvent();
  }

  /// @notice Manager can cancel fees increase at any time before the commit
  /// @dev Fees increase needs to be announced first, otherwise function does nothing
  function renounceFeeIncrease() external onlyManager {
    announcedPerformanceFeeNumerator = 0;
    announcedManagerFeeNumerator = 0;
    announcedEntryFeeNumerator = 0;
    announcedExitFeeNumerator = 0;
    announcedFeeIncreaseTimestamp = 0;

    emit ManagerFeeIncreaseRenounced();
    _emitFactoryEvent();
  }

  /// @notice Manager can commit fees increase after the delay
  /// @dev Fees increase needs to be announced first
  function commitFeeIncrease() external onlyManager {
    require(block.timestamp >= announcedFeeIncreaseTimestamp, "fee increase delay active");

    IPoolLogic(poolLogic).mintManagerFee();

    _setFeeNumerator(
      announcedPerformanceFeeNumerator,
      announcedManagerFeeNumerator,
      announcedEntryFeeNumerator,
      announcedExitFeeNumerator
    );

    announcedPerformanceFeeNumerator = 0;
    announcedManagerFeeNumerator = 0;
    announcedEntryFeeNumerator = 0;
    announcedExitFeeNumerator = 0;
    announcedFeeIncreaseTimestamp = 0;
  }

  /// @notice Set `traderAssetChangeDisabled` to `true` to disable trader asset change
  /// @dev Can only be called by the manager
  /// @param _disabled boolean value to set trader asset change disabled status
  function setTraderAssetChangeDisabled(bool _disabled) external onlyManager {
    traderAssetChangeDisabled = _disabled;
  }

  /// @notice Get manager fees increase information
  /// @return announcedPerformanceFeeNumerator numerator of the announced performance fee
  /// @return announcedManagerFeeNumerator numerator of the announced management fee
  /// @return announcedEntryFeeNumerator numerator of the announced entry fee
  /// @return announcedExitFeeNumerator numerator of the announced exit fee
  /// @return announcedFeeIncreaseTimestamp timestamp when the fee increase was announced
  function getFeeIncreaseInfo() external view returns (uint256, uint256, uint256, uint256, uint256) {
    return (
      announcedPerformanceFeeNumerator,
      announcedManagerFeeNumerator,
      announcedEntryFeeNumerator,
      announcedExitFeeNumerator,
      announcedFeeIncreaseTimestamp
    );
  }

  /// @notice Setter for poolLogic contract
  /// @dev Not required to be used under normal circumstances
  /// @param _poolLogic address of the new pool logic contract
  /// @return true if the pool logic was set successfully
  function setPoolLogic(address _poolLogic) external override returns (bool) {
    address owner = IHasOwnable(factory).owner();
    require(msg.sender == owner, "only owner address allowed");

    require(IPoolLogic(_poolLogic).poolManagerLogic() == address(this), "invalid pool logic");

    poolLogic = _poolLogic;
    emit PoolLogicSet(_poolLogic, msg.sender);
    _emitFactoryEvent();
    return true;
  }

  /// @notice Set the address of the nftMembershipCollectionAddress
  /// @param _newNftMembershipCollectionAddress The address of the new nftMembershipCollectionAddress
  function setNftMembershipCollectionAddress(address _newNftMembershipCollectionAddress) external onlyManager {
    if (_newNftMembershipCollectionAddress == address(0)) {
      nftMembershipCollectionAddress = _newNftMembershipCollectionAddress;
      return;
    }
    try ERC721Upgradeable(_newNftMembershipCollectionAddress).balanceOf(address(this)) returns (uint256) {
      nftMembershipCollectionAddress = _newNftMembershipCollectionAddress;
    } catch {
      revert("Invalid collection");
    }
  }

  /// @notice Set minimum deposit amount in USD
  /// @param _minDepositUSD minimum deposit amount in USD
  function setMinDepositUSD(uint256 _minDepositUSD) external onlyManager {
    _setMinDepositUSD(_minDepositUSD);
    _emitFactoryEvent();
  }

  function _setMinDepositUSD(uint256 _minDepositUSD) internal {
    minDepositUSD = _minDepositUSD;
    emit MinDepositUpdated(_minDepositUSD);
  }

  /// @notice Return boolean if the there is a nftMembership address set and the member owns one
  /// @param _member The address of the member
  /// @return True if the address owns an nft
  function isNftMemberAllowed(address _member) public view returns (bool) {
    return (nftMembershipCollectionAddress != address(0) &&
      ERC721Upgradeable(nftMembershipCollectionAddress).balanceOf(_member) > 0);
  }

  /// @notice Return boolean if the address is a member of the list or owns an nft in the membership collection
  /// @param _member The address of the member
  /// @return True if the address is a member of the list or owns nft in the membership collection, false otherwise
  function isMemberAllowed(address _member) public view virtual override returns (bool) {
    return _isMemberAllowed(_member) || isNftMemberAllowed(_member);
  }

  /// @notice Emits an event through the factory, so we can just listen to the factory offchain
  function _emitFactoryEvent() internal {
    IPoolFactory(factory).emitPoolManagerEvent();
  }

  uint256[42] private __gap;
}
