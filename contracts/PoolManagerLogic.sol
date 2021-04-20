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

import "./interfaces/ISynth.sol";
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/ISynthetix.sol";
import "./interfaces/ISystemStatus.sol";
import "./interfaces/IExchangeRates.sol";
import "./interfaces/IAddressResolver.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasProtocolDaoInfo.sol";
import "./Managed.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

pragma solidity ^0.6.2;

contract PoolManagerLogic is IPoolManagerLogic, Managed, Initializable {
    using SafeMath for uint256;

    bytes32 constant private _EXCHANGE_RATES_KEY = "ExchangeRates";
    bytes32 constant private _SYNTHETIX_KEY = "Synthetix";

    bytes32 constant private _SYSTEM_STATUS_KEY = "SystemStatus";
    bytes32 constant private _SUSD_KEY = "sUSD";

    event Exchange(
        address fundAddress,
        address manager,
        bytes32 sourceKey,
        uint256 sourceAmount,
        bytes32 destinationKey,
        uint256 destinationAmount,
        uint256 time
    );
    event AssetAdded(address fundAddress, address manager, bytes32 assetKey);
    event AssetRemoved(address fundAddress, address manager, bytes32 assetKey);


    event ManagerFeeSet(
        address fundAddress,
        address manager,
        uint256 numerator,
        uint256 denominator
    );

    event ManagerFeeIncreaseAnnounced(
        uint256 newNumerator,
        uint256 announcedFeeActivationTime);

    event ManagerFeeIncreaseRenounced();

    IAddressResolver public override addressResolver;

    address public factory;

    bytes32[] public supportedAssets;
    mapping(bytes32 => uint256) public assetPosition; // maps the asset to its 1-based position

    mapping(bytes32 => bool) public persistentAsset;

    // Fee increase announcement
    uint256 public announcedFeeIncreaseNumerator;
    uint256 public announcedFeeIncreaseTimestamp;


    function initialize(
        address _factory,
        address _manager,
        string memory _managerName,
        IAddressResolver _addressResolver,
        bytes32[] memory _supportedAssets
    ) public initializer {
        initialize(_manager, _managerName);

        factory = _factory;
        // _setPoolPrivacy(_privatePool);
        addressResolver = _addressResolver;

        _addToSupportedAssets(_SUSD_KEY);

        for(uint8 i = 0; i < _supportedAssets.length; i++) {
            _addToSupportedAssets(_supportedAssets[i]);
        }

        // Set persistent assets
        persistentAsset[_SUSD_KEY] = true;
    }


    function getAssetProxy(bytes32 key) public override view returns (address) {
        address synth = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY))
            .synths(key);
        require(synth != address(0), "invalid key");
        address proxy = ISynth(synth).proxy();
        require(proxy != address(0), "invalid proxy");
        return proxy;
    }

    function isAssetSupported(bytes32 key) public view returns (bool) {
        return assetPosition[key] != 0;
    }

    function validateAsset(bytes32 key) public view returns (bool) {
        address synth = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY))
            .synths(key);

        if (synth == address(0))
            return false;

        address proxy = ISynth(synth).proxy();

        if (proxy == address(0))
            return false;

        return true;
    }

    function addToSupportedAssets(bytes32 key) public onlyManagerOrTrader {
        _addToSupportedAssets(key);
    }

    function removeFromSupportedAssets(bytes32 key) public {
        require(msg.sender == IHasProtocolDaoInfo(factory).owner() ||
            msg.sender == manager() ||
            msg.sender == trader(), "only manager, trader or Protocol DAO");

        require(isAssetSupported(key), "asset not supported");

        require(!persistentAsset[key], "persistent assets can't be removed");

        // ISynthetix sx = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY));
        // sx.settle(key);
        if (validateAsset(key) == true) { // allow removal of depreciated synths
            require(
                IERC20(getAssetProxy(key)).balanceOf(address(this)) == 0,
                "non-empty asset cannot be removed"
            );
        }

        // Deprecated
        // require(key != _SUSD_KEY, "sUSD can't be removed");

        _removeFromSupportedAssets(key);
    }

    function numberOfSupportedAssets() public view returns (uint256) {
        return supportedAssets.length;
    }

    // Unsafe internal method that assumes we are not adding a duplicate
    function _addToSupportedAssets(bytes32 key) internal {
        require(supportedAssets.length < IHasAssetInfo(factory).getMaximumSupportedAssetCount(), "maximum assets reached");
        require(!isAssetSupported(key), "asset already supported");
        require(validateAsset(key) == true, "non-synth asset");

        supportedAssets.push(key);
        assetPosition[key] = supportedAssets.length;

        emit AssetAdded(address(this), manager(), key);
    }

    // Unsafe internal method that assumes we are removing an element that exists
    function _removeFromSupportedAssets(bytes32 key) internal {
        uint256 length = supportedAssets.length;
        uint256 index = assetPosition[key].sub(1); // adjusting the index because the map stores 1-based

        bytes32 lastAsset = supportedAssets[length.sub(1)];

        // overwrite the asset to be removed with the last supported asset
        supportedAssets[index] = lastAsset;
        assetPosition[lastAsset] = index.add(1); // adjusting the index to be 1-based
        assetPosition[key] = 0; // update the map

        // delete the last supported asset and resize the array
        supportedAssets.pop();

        emit AssetRemoved(address(this), manager(), key);
    }

    function exchange(
        bytes32 sourceKey,
        uint256 sourceAmount,
        bytes32 destinationKey
    ) public onlyManagerOrTrader {
        require(isAssetSupported(sourceKey), "unsupported source currency");
        require(
            isAssetSupported(destinationKey),
            "unsupported destination currency"
        );

        ISynthetix sx = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY));

        uint256 destinationAmount = sx.exchangeWithTracking(
            sourceKey,
            sourceAmount,
            destinationKey,
            IHasDaoInfo(factory).getDaoAddress(),
            IHasFeeInfo(factory).getTrackingCode()
        );

        emit Exchange(
            address(this),
            msg.sender,
            sourceKey,
            sourceAmount,
            destinationKey,
            destinationAmount,
            block.timestamp
        );
    }



    function assetValue(bytes32 key) public override view returns (uint256) {
        return
            IExchangeRates(addressResolver.getAddress(_EXCHANGE_RATES_KEY))
                .effectiveValue(
                key,
                IERC20(getAssetProxy(key)).balanceOf(address(this)),
                _SUSD_KEY
            );
    }

    function getSuspendedAssets() public view returns (bytes32[] memory, bool[] memory) {

        uint256 assetCount = supportedAssets.length;

        bytes32[] memory assets = new bytes32[](assetCount);
        bool[] memory suspended = new bool[](assetCount);

        ISystemStatus status = ISystemStatus(addressResolver.getAddress(_SYSTEM_STATUS_KEY));

        for (uint256 i = 0; i < assetCount; i++) {
            bytes32 asset = supportedAssets[i];

            assets[i] = asset;

            try status.requireSynthActive(asset) {
                suspended[i] = false;
            } catch {
                suspended[i] = true;
            }
        }

        return (assets, suspended);

    }

    function getSupportedAssets() public override view returns (bytes32[] memory) {
        return supportedAssets;
    }

    function getFundComposition()
        public
        view
        returns (
            bytes32[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 assetCount = supportedAssets.length;

        bytes32[] memory assets = new bytes32[](assetCount);
        uint256[] memory balances = new uint256[](assetCount);
        uint256[] memory rates = new uint256[](assetCount);

        IExchangeRates exchangeRates = IExchangeRates(
            addressResolver.getAddress(_EXCHANGE_RATES_KEY)
        );
        for (uint256 i = 0; i < assetCount; i++) {
            bytes32 asset = supportedAssets[i];
            balances[i] = IERC20(getAssetProxy(asset)).balanceOf(address(this));
            assets[i] = asset;
            rates[i] = exchangeRates.rateForCurrency(asset);
        }
        return (assets, balances, rates);
    }

    function getManagerFee() public view returns (uint256, uint256) {
        return IHasFeeInfo(factory).getPoolManagerFee(address(this));
    }

    function setManagerFeeNumerator(uint256 numerator) public onlyManager {
        _setManagerFeeNumerator(numerator);
    }

    function _setManagerFeeNumerator(uint256 numerator) internal {
        IHasFeeInfo(factory).setPoolManagerFeeNumerator(address(this), numerator);

        uint256 managerFeeNumerator;
        uint256 managerFeeDenominator;
        (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory).getPoolManagerFee(address(this));

        emit ManagerFeeSet(
            address(this),
            manager(),
            managerFeeNumerator,
            managerFeeDenominator
        );
    }

    function announceManagerFeeIncrease(uint256 numerator) public onlyManager {
        uint256 maximumAllowedChange = IHasFeeInfo(factory).getMaximumManagerFeeNumeratorChange();

        uint256 currentFeeNumerator;
        (currentFeeNumerator, ) = getManagerFee();

        require (numerator <= currentFeeNumerator.add(maximumAllowedChange), "exceeded allowed increase");

        uint256 feeChangeDelay = IHasFeeInfo(factory).getManagerFeeNumeratorChangeDelay();

        announcedFeeIncreaseNumerator = numerator;
        announcedFeeIncreaseTimestamp = block.timestamp + feeChangeDelay;
        emit ManagerFeeIncreaseAnnounced(numerator, announcedFeeIncreaseTimestamp);
    }

    function renounceManagerFeeIncrease() public onlyManager {
        announcedFeeIncreaseNumerator = 0;
        announcedFeeIncreaseTimestamp = 0;
        emit ManagerFeeIncreaseRenounced();
    }

    function commitManagerFeeIncrease() public onlyManager {
        require(block.timestamp >= announcedFeeIncreaseTimestamp, "fee increase delay active");

        _setManagerFeeNumerator(announcedFeeIncreaseNumerator);

        announcedFeeIncreaseNumerator = 0;
        announcedFeeIncreaseTimestamp = 0;
    }

    function getManagerFeeIncreaseInfo() public view returns (uint256, uint256) {
        return (announcedFeeIncreaseNumerator, announcedFeeIncreaseTimestamp);
    }

    function setAddressResolver(address _addressResolver) external {
        require(msg.sender == factory, "no permission");
        addressResolver = IAddressResolver(_addressResolver);
    }

    uint256[51] private __gap;
}