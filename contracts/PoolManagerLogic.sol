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

import "./interfaces/IPoolLogic.sol";
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasProtocolDaoInfo.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IHasSupportedAsset.sol";
import "./interfaces/IHasOwnable.sol";
import "./interfaces/guards/IGuard.sol";
import "./interfaces/guards/IAssetGuard.sol";
import "./interfaces/guards/IMutableBalanceAssetGuard.sol";
import "./interfaces/IPoolFactory.sol";
import "./Managed.sol";

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

/// @notice Logic implmentation for pool manager
contract PoolManagerLogic is Initializable, IPoolManagerLogic, IHasSupportedAsset, Managed {
  using SafeMathUpgradeable for uint256;
  using AddressUpgradeable for address;

  event AssetAdded(address indexed fundAddress, address manager, address asset, bool isDeposit);
  event AssetRemoved(address fundAddress, address manager, address asset);

  event ManagerFeeSet(
    address fundAddress,
    address manager,
    uint256 performanceFeeNumerator,
    uint256 managerFeeNumerator,
    uint256 entryFeeNumerator,
    uint256 denominator
  );

  event ManagerFeeIncreaseAnnounced(
    uint256 performanceFeeNumerator,
    uint256 managerFeeNumerator,
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
  uint256 public announcedManagerFeeNumerator;
  uint256 public managerFeeNumerator;

  // Should be in Managed.sol but not upgradable
  address public nftMembershipCollectionAddress;

  uint256 public override minDepositUSD;

  uint256 public announcedEntryFeeNumerator;
  uint256 public entryFeeNumerator;

  modifier onlyManagerOrTraderOrOwner() {
    require(
      msg.sender == manager || msg.sender == trader || msg.sender == IHasOwnable(factory).owner(),
      "only manager, trader or owner"
    );
    _;
  }

  /// @notice initialize the pool manager
  /// @param _factory address of the factory
  /// @param _manager address of the manager
  /// @param _managerName name of the manager
  /// @param _poolLogic address of the pool logic
  /// @param _performanceFeeNumerator numerator of the manager fee
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
    initialize(_manager, _managerName);

    factory = _factory;
    poolLogic = _poolLogic;
    _setFeeNumerator(_performanceFeeNumerator, _managerFeeNumerator, 0); // By default entry fee will be set as 0%
    _changeAssets(_supportedAssets, new address[](0));
  }

  /// @notice Return true if it's supported asset, false otherwise
  /// @param asset address of the asset
  function isSupportedAsset(address asset) public view override returns (bool) {
    return assetPosition[asset] != 0;
  }

  /// @notice Return true if it's deposit asset, false otherwise
  /// @param asset address of the asset
  function isDepositAsset(address asset) public view override returns (bool) {
    uint256 index = assetPosition[asset];

    return index != 0 && supportedAssets[index.sub(1)].isDeposit;
  }

  /// @notice Return true if it's valid asset, false otherwise
  /// @param asset address of the asset
  function validateAsset(address asset) public view override returns (bool) {
    return IHasAssetInfo(factory).isValidAsset(asset);
  }

  /// @notice Change assets of the pool
  /// @param _addAssets array of assets to add
  /// @param _removeAssets array of asset addresses to remove
  function changeAssets(
    Asset[] calldata _addAssets,
    address[] calldata _removeAssets
  ) external onlyManagerOrTraderOrOwner {
    _changeAssets(_addAssets, _removeAssets);
    emitFactoryEvent();
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
  /// @param asset asset address
  function _removeAsset(address asset) internal {
    require(isSupportedAsset(asset), "asset not supported");

    address guard = IHasGuardInfo(factory).getAssetGuard(asset);
    if (guard != address(0)) {
      // should be able to remove any deprecated assets
      require(assetBalance(asset) == 0, "cannot remove non-empty asset");
      IAssetGuard(guard).removeAssetCheck(poolLogic, asset);
    }

    uint256 index = assetPosition[asset].sub(1); // adjusting the index because the map stores 1-based
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

    emit AssetRemoved(poolLogic, manager, asset);
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
  /// @return balance of the asset
  function assetBalance(address asset) public view override returns (uint256 balance) {
    address guard = IHasGuardInfo(factory).getAssetGuard(asset);
    balance = IAssetGuard(guard).getBalance(poolLogic, asset);
  }

  /// @notice Get asset decimal
  /// @return decimal of the asset
  function assetDecimal(address asset) public view returns (uint256 decimal) {
    address guard = IHasGuardInfo(factory).getAssetGuard(asset);
    decimal = IAssetGuard(guard).getDecimals(asset);
  }

  /// @notice Get value of the asset
  /// @param asset address of the asset
  /// @param amount amount of the asset
  /// @return value of the asset
  function assetValue(address asset, uint256 amount) public view override returns (uint256 value) {
    uint256 price = IHasAssetInfo(factory).getAssetPrice(asset);
    uint256 decimals = assetDecimal(asset);

    value = price.mul(amount).div(10 ** decimals);
  }

  /// @notice Get value of the asset
  /// @param asset address of the asset
  /// @return value of the asset
  function assetValue(address asset) public view override returns (uint256 value) {
    value = assetValue(asset, assetBalance(asset));
  }

  /// @notice Return the fund composition of the pool
  /// @dev Return assets, balances of the asset and their prices
  /// @return assets array of supported assets
  /// @return balances balances of each asset
  /// @return rates price of each asset in USD
  function getFundComposition()
    public
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
  /// @return value in USD
  function totalFundValue() external view override returns (uint256) {
    uint256 total = 0;
    uint256 assetCount = supportedAssets.length;

    for (uint256 i = 0; i < assetCount; i++) {
      total = total.add(assetValue(supportedAssets[i].asset));
    }
    return total;
  }

  function totalFundValueMutable() external override returns (uint256 total) {
    uint256 assetCount = supportedAssets.length;

    for (uint256 i; i < assetCount; ++i) {
      address asset = supportedAssets[i].asset;
      address guard = IHasGuardInfo(factory).getAssetGuard(asset);
      uint256 balance;
      // solhint-disable-next-line avoid-low-level-calls
      (bool hasFunction, bytes memory answer) = guard.call(abi.encodeWithSignature("isStateMutatingGuard()"));
      if (hasFunction && abi.decode(answer, (bool))) {
        balance = IMutableBalanceAssetGuard(guard).getBalanceMutable(poolLogic, asset);
      } else {
        balance = IAssetGuard(guard).getBalance(poolLogic, asset);
      }
      total = total.add(assetValue(asset, balance));
    }
  }

  /* ========== MANAGER FEES ========== */

  /// @notice Return the manager fees
  function getFee() external view override returns (uint256, uint256, uint256, uint256) {
    (, , , uint256 managerFeeDenominator) = IHasFeeInfo(factory).getMaximumFee();
    return (performanceFeeNumerator, managerFeeNumerator, entryFeeNumerator, managerFeeDenominator);
  }

  /// @notice Get maximum manager fee
  /// @return numerator numerator of the maximum manager fee
  /// @return entryFeeNumerator numerator of the maximum entry fee
  /// @return denominator denominator of the maximum manager fee
  function getMaximumFee() public view returns (uint256, uint256, uint256, uint256) {
    return IHasFeeInfo(factory).getMaximumFee();
  }

  /// @notice Get maximum manager fee change
  /// @return change change of the maximum manager fee
  function getMaximumPerformanceFeeChange() public view returns (uint256 change) {
    change = IHasFeeInfo(factory).maximumPerformanceFeeNumeratorChange();
  }

  // Manager fee decreases

  /// @notice Manager can decrease performance fee
  /// @param _performanceFeeNumerator The numerator of the maximum manager fee
  /// @param _managerFeeNumerator The numerator of the maximum streaming fee
  function setFeeNumerator(
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _entryFeeNumerator
  ) external onlyManager {
    require(
      _performanceFeeNumerator <= performanceFeeNumerator &&
        _managerFeeNumerator <= managerFeeNumerator &&
        _entryFeeNumerator <= entryFeeNumerator,
      "manager fee too high"
    );
    _setFeeNumerator(_performanceFeeNumerator, _managerFeeNumerator, _entryFeeNumerator);
    emitFactoryEvent();
  }

  /// @notice Manager can decrease performance fee internal call
  /// @param _performanceFeeNumerator The numerator of the maximum manager fee
  /// @param _managerFeeNumerator The numerator of the maximum streaming fee
  function _setFeeNumerator(
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _entryFeeNumerator
  ) internal {
    (
      uint256 maximumPerformanceFeeNumerator,
      uint256 maximumManagerFeeNumerator,
      uint256 maximumEntryFeeNumerator,
      uint256 denominator
    ) = getMaximumFee();
    require(
      _performanceFeeNumerator <= maximumPerformanceFeeNumerator &&
        _managerFeeNumerator <= maximumManagerFeeNumerator &&
        _entryFeeNumerator <= maximumEntryFeeNumerator,
      "invalid manager fee"
    );

    performanceFeeNumerator = _performanceFeeNumerator;
    managerFeeNumerator = _managerFeeNumerator;
    entryFeeNumerator = _entryFeeNumerator;

    emit ManagerFeeSet(
      poolLogic,
      manager,
      _performanceFeeNumerator,
      _managerFeeNumerator,
      _entryFeeNumerator,
      denominator
    );
  }

  // Manager fee increases

  /// @notice Manager can announce an increase to the performance fee
  /// @dev The commit to the new fee can happen after a time delay
  /// @param _performanceFeeNumerator The numerator of the maximum manager fee
  /// @param _managerFeeNumerator The numerator of the maximum streaming fee
  function announceFeeIncrease(
    uint256 _performanceFeeNumerator,
    uint256 _managerFeeNumerator,
    uint256 _entryFeeNumerator
  ) external onlyManager {
    (
      uint256 maximumPerformanceFeeNumerator,
      uint256 maximumManagerFeeNumerator,
      uint256 maximumEntryFeeNumerator,

    ) = getMaximumFee();
    uint256 maximumAllowedChange = getMaximumPerformanceFeeChange();

    require(
      _performanceFeeNumerator <= maximumPerformanceFeeNumerator &&
        _managerFeeNumerator <= maximumManagerFeeNumerator &&
        _entryFeeNumerator <= maximumEntryFeeNumerator &&
        _performanceFeeNumerator <= performanceFeeNumerator.add(maximumAllowedChange),
      "exceeded allowed increase"
    );

    uint256 feeChangeDelay = IHasFeeInfo(factory).performanceFeeNumeratorChangeDelay();

    announcedPerformanceFeeNumerator = _performanceFeeNumerator;
    announcedManagerFeeNumerator = _managerFeeNumerator;
    announcedEntryFeeNumerator = _entryFeeNumerator;
    announcedFeeIncreaseTimestamp = block.timestamp + feeChangeDelay;
    emit ManagerFeeIncreaseAnnounced(_performanceFeeNumerator, _managerFeeNumerator, announcedFeeIncreaseTimestamp);
    emitFactoryEvent();
  }

  /// @notice Manager can cancel the performance fee increase
  /// @dev Fee increase needs to be announced first
  function renounceFeeIncrease() external onlyManager {
    announcedPerformanceFeeNumerator = 0;
    announcedManagerFeeNumerator = 0;
    announcedEntryFeeNumerator = 0;
    announcedFeeIncreaseTimestamp = 0;
    emit ManagerFeeIncreaseRenounced();
    emitFactoryEvent();
  }

  /// @notice Manager can commit the performance fee increase
  /// @dev Fee increase needs to be announced first
  function commitFeeIncrease() external onlyManager {
    require(block.timestamp >= announcedFeeIncreaseTimestamp, "fee increase delay active");

    IPoolLogic(poolLogic).mintManagerFee();

    _setFeeNumerator(announcedPerformanceFeeNumerator, announcedManagerFeeNumerator, announcedEntryFeeNumerator);

    announcedPerformanceFeeNumerator = 0;
    announcedManagerFeeNumerator = 0;
    announcedEntryFeeNumerator = 0;
    announcedFeeIncreaseTimestamp = 0;
  }

  /// @notice Get manager fee increase information
  function getFeeIncreaseInfo() external view returns (uint256, uint256, uint256, uint256) {
    return (
      announcedPerformanceFeeNumerator,
      announcedManagerFeeNumerator,
      announcedEntryFeeNumerator,
      announcedFeeIncreaseTimestamp
    );
  }

  /// @notice Setter for poolLogic contract
  /// @dev Not required to be used under normal circumstances
  function setPoolLogic(address _poolLogic) external override returns (bool) {
    address owner = IHasOwnable(factory).owner();
    require(msg.sender == owner, "only owner address allowed");

    require(IPoolLogic(_poolLogic).poolManagerLogic() == address(this), "invalid pool logic");

    poolLogic = _poolLogic;
    emit PoolLogicSet(_poolLogic, msg.sender);
    emitFactoryEvent();
    return true;
  }

  /// @notice Set the address of the nftMembershipCollectionAddress
  /// @param newNftMembershipCollectionAddress The address of the new nftMembershipCollectionAddress
  function setNftMembershipCollectionAddress(address newNftMembershipCollectionAddress) external onlyManager {
    if (newNftMembershipCollectionAddress == address(0)) {
      nftMembershipCollectionAddress = newNftMembershipCollectionAddress;
      return;
    }
    try ERC721Upgradeable(newNftMembershipCollectionAddress).balanceOf(address(this)) returns (uint256) {
      nftMembershipCollectionAddress = newNftMembershipCollectionAddress;
    } catch {
      revert("Invalid collection");
    }
  }

  /// @notice Set minimum deposit amount in USD
  /// @param _minDepositUSD minimum deposit amount in USD
  function setMinDepositUSD(uint256 _minDepositUSD) external onlyManager {
    _setMinDepositUSD(_minDepositUSD);
    emitFactoryEvent();
  }

  /// @notice Set minimum deposit amount in USD internal call
  /// @param _minDepositUSD minimum deposit amount in USD
  function _setMinDepositUSD(uint256 _minDepositUSD) internal {
    minDepositUSD = _minDepositUSD;
    emit MinDepositUpdated(_minDepositUSD);
  }

  /// @notice Return boolean if the there is a nftMembership address set and the member owns one
  /// @param member The address of the member
  /// @return True if the address owns an nft
  function isNftMemberAllowed(address member) public view returns (bool) {
    return (nftMembershipCollectionAddress != address(0) &&
      ERC721Upgradeable(nftMembershipCollectionAddress).balanceOf(member) > 0);
  }

  /// @notice Return boolean if the address is a member of the list or owns an nft in the membership collection
  /// @param member The address of the member
  /// @return True if the address is a member of the list or owns nft in the membership collection, false otherwise
  function isMemberAllowed(address member) public view virtual override returns (bool) {
    return _isMemberAllowed(member) || isNftMemberAllowed(member);
  }

  /// @notice Emits an event through the factory, so we can just listen to the factory offchain
  function emitFactoryEvent() internal {
    IPoolFactory(factory).emitPoolManagerEvent();
  }

  uint256[45] private __gap;
}
