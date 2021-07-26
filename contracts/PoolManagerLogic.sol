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
import "./Managed.sol";

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

contract PoolManagerLogic is Initializable, IPoolManagerLogic, IHasSupportedAsset, Managed {
  using SafeMathUpgradeable for uint256;
  using AddressUpgradeable for address;

  event AssetAdded(address indexed fundAddress, address manager, address asset, bool isDeposit);
  event AssetRemoved(address fundAddress, address manager, address asset);

  event ManagerFeeSet(address fundAddress, address manager, uint256 numerator, uint256 denominator);

  event ManagerFeeIncreaseAnnounced(uint256 newNumerator, uint256 announcedFeeActivationTime);

  event ManagerFeeIncreaseRenounced();
  event PoolLogicSet(address poolLogic, address from);

  address public override factory;
  address public override poolLogic;

  Asset[] public supportedAssets;
  mapping(address => uint256) public assetPosition; // maps the asset to its 1-based position

  // Fee increase announcement
  uint256 public announcedFeeIncreaseNumerator;
  uint256 public announcedFeeIncreaseTimestamp;
  uint256 public managerFeeNumerator;

  function initialize(
    address _factory,
    address _manager,
    string calldata _managerName,
    address _poolLogic,
    uint256 _managerFeeNumerator,
    Asset[] calldata _supportedAssets
  ) external initializer {
    require(_factory != address(0), "Invalid factory");
    require(_manager != address(0), "Invalid manager");
    require(_poolLogic != address(0), "Invalid poolLogic");
    initialize(_manager, _managerName);

    factory = _factory;
    poolLogic = _poolLogic;
    managerFeeNumerator = _managerFeeNumerator;
    _changeAssets(_supportedAssets, new address[](0));
  }

  function isSupportedAsset(address asset) public view override returns (bool) {
    return assetPosition[asset] != 0;
  }

  function isDepositAsset(address asset) public view override returns (bool) {
    uint256 index = assetPosition[asset];

    return index != 0 && supportedAssets[index.sub(1)].isDeposit;
  }

  function validateAsset(address asset) public view override returns (bool) {
    return IHasAssetInfo(factory).isValidAsset(asset);
  }

  function changeAssets(Asset[] calldata _addAssets, address[] calldata _removeAssets) external onlyManagerOrTrader {
    _changeAssets(_addAssets, _removeAssets);
  }

  function _changeAssets(Asset[] calldata _addAssets, address[] memory _removeAssets) internal {
    for (uint8 i = 0; i < _removeAssets.length; i++) {
      _removeAsset(_removeAssets[i]);
    }

    for (uint8 i = 0; i < _addAssets.length; i++) {
      _addAsset(_addAssets[i]);
    }

    require(supportedAssets.length < IHasAssetInfo(factory).getMaximumSupportedAssetCount(), "maximum assets reached");

    require(getDepositAssets().length >= 1, "at least one deposit asset");
  }

  function _addAsset(Asset calldata _asset) internal {
    address asset = _asset.asset;
    bool isDeposit = _asset.isDeposit;

    require(validateAsset(asset), "invalid asset");

    if (isSupportedAsset(asset)) {
      uint256 index = assetPosition[asset].sub(1);
      supportedAssets[index].isDeposit = isDeposit;
    } else {
      supportedAssets.push(Asset(asset, isDeposit));
      assetPosition[asset] = supportedAssets.length;
    }

    emit AssetAdded(poolLogic, manager, asset, isDeposit);
  }

  /// @notice Remove asset from the pool
  /// @dev use asset address to remove from supportedAssets
  /// @param asset asset address
  function _removeAsset(address asset) internal {
    require(isSupportedAsset(asset), "asset not supported");

    require(assetBalance(asset) == 0, "cannot remove non-empty asset");

    uint256 length = supportedAssets.length;
    Asset memory lastAsset = supportedAssets[length.sub(1)];
    uint256 index = assetPosition[asset].sub(1); // adjusting the index because the map stores 1-based

    // overwrite the asset to be removed with the last supported asset
    supportedAssets[index] = lastAsset;
    assetPosition[lastAsset.asset] = index.add(1); // adjusting the index to be 1-based
    assetPosition[asset] = 0; // update the map

    // delete the last supported asset and resize the array
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
  function assetBalance(address asset) public view returns (uint256) {
    address guard = IHasGuardInfo(factory).getAssetGuard(asset);
    return IAssetGuard(guard).getBalance(poolLogic, asset);
  }

  /// @notice Get asset decimal
  function assetDecimal(address asset) public view returns (uint256) {
    address guard = IHasGuardInfo(factory).getAssetGuard(asset);
    return IAssetGuard(guard).getDecimals(asset);
  }

  function assetValue(address asset, uint256 amount) public view override returns (uint256) {
    uint256 price = IHasAssetInfo(factory).getAssetPrice(asset);
    uint256 decimals = assetDecimal(asset);

    return price.mul(amount).div(10**decimals);
  }

  function assetValue(address asset) public view override returns (uint256) {
    return assetValue(asset, assetBalance(asset));
  }

  /// @notice Return the fund composition of the pool
  /// @dev Return assets, balances of the asset and their prices
  /// @return assets array of supported assets
  /// @return balances balances of each asset
  /// @return rates price of each asset in USD
  function getFundComposition()
    public
    view
    returns (
      Asset[] memory assets,
      uint256[] memory balances,
      uint256[] memory rates
    )
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

  /* ========== MANAGER FEES ========== */

  function getManagerFee() external view override returns (uint256, uint256) {
    (, uint256 managerFeeDenominator) = IHasFeeInfo(factory).getMaximumManagerFee();
    return (managerFeeNumerator, managerFeeDenominator);
  }

  function getMaximumManagerFee() public view returns (uint256, uint256) {
    return IHasFeeInfo(factory).getMaximumManagerFee();
  }

  function getMaximumManagerFeeChange() public view returns (uint256) {
    return IHasFeeInfo(factory).maximumManagerFeeNumeratorChange();
  }

  // Manager fee decreases

  /// @notice Manager can decrease performance fee
  function setManagerFeeNumerator(uint256 numerator) external onlyManager {
    require(numerator <= managerFeeNumerator, "manager fee too high");
    _setManagerFeeNumerator(numerator);
  }

  function _setManagerFeeNumerator(uint256 numerator) internal {
    (uint256 maximumNumerator, uint256 denominator) = getMaximumManagerFee();
    require(numerator <= denominator && numerator <= maximumNumerator, "invalid manager fee");

    managerFeeNumerator = numerator;

    emit ManagerFeeSet(poolLogic, manager, numerator, denominator);
  }

  // Manager fee increases

  /// @notice Manager can announce an increase to the performance fee
  /// @dev The commit to the new fee can happen after a time delay
  function announceManagerFeeIncrease(uint256 numerator) external onlyManager {
    (uint256 maximumNumerator, uint256 denominator) = getMaximumManagerFee();
    uint256 maximumAllowedChange = getMaximumManagerFeeChange();

    require(numerator <= denominator, "invalid fraction");
    require(
      numerator <= maximumNumerator && numerator <= managerFeeNumerator.add(maximumAllowedChange),
      "exceeded allowed increase"
    );

    uint256 feeChangeDelay = IHasFeeInfo(factory).managerFeeNumeratorChangeDelay();

    announcedFeeIncreaseNumerator = numerator;
    announcedFeeIncreaseTimestamp = block.timestamp + feeChangeDelay;
    emit ManagerFeeIncreaseAnnounced(numerator, announcedFeeIncreaseTimestamp);
  }

  /// @notice Manager can cancel the performance fee increase
  /// @dev Fee increase needs to be announced first
  function renounceManagerFeeIncrease() external onlyManager {
    announcedFeeIncreaseNumerator = 0;
    announcedFeeIncreaseTimestamp = 0;
    emit ManagerFeeIncreaseRenounced();
  }

  /// @notice Manager can commit the performance fee increase
  /// @dev Fee increase needs to be announced first
  function commitManagerFeeIncrease() external onlyManager {
    require(block.timestamp >= announcedFeeIncreaseTimestamp, "fee increase delay active");

    _setManagerFeeNumerator(announcedFeeIncreaseNumerator);

    announcedFeeIncreaseNumerator = 0;
    announcedFeeIncreaseTimestamp = 0;
  }

  function getManagerFeeIncreaseInfo() external view returns (uint256, uint256) {
    return (announcedFeeIncreaseNumerator, announcedFeeIncreaseTimestamp);
  }

  /// @notice Setter for poolLogic contract
  /// @dev Not required to be used under normal circumstances
  function setPoolLogic(address _poolLogic) external override returns (bool) {
    address daoAddress = IHasOwnable(factory).owner();
    require(msg.sender == daoAddress, "only DAO address allowed");

    require(IPoolLogic(_poolLogic).poolManagerLogic() == address(this), "invalid pool logic");

    poolLogic = _poolLogic;
    emit PoolLogicSet(_poolLogic, msg.sender);
    return true;
  }

  uint256[51] private __gap;
}
