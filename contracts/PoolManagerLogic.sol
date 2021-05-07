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
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasProtocolDaoInfo.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./interfaces/IERC20.sol"; // includes decimals()
import "./guards/TxDataUtils.sol";
import "./guards/IGuard.sol";
import "./Managed.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";

pragma solidity ^0.6.2;

contract PoolManagerLogic is 
    Initializable,
    IPoolManagerLogic,
    Managed,
    TxDataUtils
{
    using SafeMath for uint256;
    using Address for address;

    event TransactionExecuted(
        address fundAddress,
        address manager,
        uint256 time
    );
    event AssetAdded(address fundAddress, address manager, address asset);
    event AssetRemoved(address fundAddress, address manager, address asset);

    event ManagerFeeSet(
        address fundAddress,
        address manager,
        uint256 numerator,
        uint256 denominator
    );

    event ManagerFeeIncreaseAnnounced(
        uint256 newNumerator,
        uint256 announcedFeeActivationTime
    );

    event ManagerFeeIncreaseRenounced();

    address override public factory;

    address[] public supportedAssets;
    mapping(address => uint256) public assetPosition; // maps the asset to its 1-based position
    mapping(address => bool) public persistentAsset;

    // Fee increase announcement
    uint256 public announcedFeeIncreaseNumerator;
    uint256 public announcedFeeIncreaseTimestamp;

    function initialize(
        address _factory,
        address _manager,
        string memory _managerName,
        address[] memory _supportedAssets
    ) public initializer {
        initialize(_manager, _managerName);

        factory = _factory;
        // _setPoolPrivacy(_privatePool);

        for (uint8 i = 0; i < _supportedAssets.length; i++) {
            _addToSupportedAssets(_supportedAssets[i]);
        }
    }

    function isAssetSupported(address asset) public view override returns (bool) {
        return assetPosition[asset] != 0;
    }

    function validateAsset(address asset) public view override returns (bool) {
        return IHasAssetInfo(factory).isValidAsset(asset);
    }

    function addToSupportedAssets(address asset) public onlyManagerOrTrader {
        _addToSupportedAssets(asset);
    }

    function removeFromSupportedAssets(address asset) public {
        require(
            msg.sender == IHasProtocolDaoInfo(factory).owner() ||
                msg.sender == manager() ||
                msg.sender == trader(),
            "only manager, trader or DAO"
        );

        require(isAssetSupported(asset), "asset not supported");

        require(!persistentAsset[asset], "cannot remove persistent assets");

        require(
            IERC20(asset).balanceOf(address(this)) == 0,
            "cannot remove non-empty asset"
        );

        _removeFromSupportedAssets(asset);
    }

    function numberOfSupportedAssets() public view returns (uint256) {
        return supportedAssets.length;
    }

    // Unsafe internal method that assumes we are not adding a duplicate
    function _addToSupportedAssets(address asset) internal {
        require(
            supportedAssets.length <
                IHasAssetInfo(factory).getMaximumSupportedAssetCount(),
            "maximum assets reached"
        );
        require(!isAssetSupported(asset), "asset already supported");
        require(validateAsset(asset) == true, "invalid asset");

        supportedAssets.push(asset);
        assetPosition[asset] = supportedAssets.length;

        emit AssetAdded(address(this), manager(), asset);
    }

    // Unsafe internal method that assumes we are removing an element that exists
    function _removeFromSupportedAssets(address asset) internal {
        uint256 length = supportedAssets.length;
        uint256 index = assetPosition[asset].sub(1); // adjusting the index because the map stores 1-based

        address lastAsset = supportedAssets[length.sub(1)];

        // overwrite the asset to be removed with the last supported asset
        supportedAssets[index] = lastAsset;
        assetPosition[lastAsset] = index.add(1); // adjusting the index to be 1-based
        assetPosition[asset] = 0; // update the map

        // delete the last supported asset and resize the array
        supportedAssets.pop();

        emit AssetRemoved(address(this), manager(), asset);
    }

    function execTransaction(address to, bytes memory data)
        public
        onlyManagerOrTrader
        returns (bool)
    {
        require(to != address(0), "non-zero address is required");

        address guard = IHasGuardInfo(factory).getGuard(to);

        require(guard != address(0), "invalid destination");

        require(IGuard(guard).txGuard(address(this), data), "invalid transaction");

        (bool success, ) = to.call(data);
        require(success == true, "failed to execute the call");

        emit TransactionExecuted(
            address(this),
            manager(),
            block.timestamp
        );

        return true;
    }

    function assetValue(address asset, uint256 amount)
        public
        view
        override
        returns (uint256)
    {
        uint256 price = IHasAssetInfo(factory).getAssetPrice(asset);
        uint256 decimals = uint256(IERC20(asset).decimals());
        
        return price.mul(amount).div(10**decimals);
    }

    function assetBalance(address asset) public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function assetValue(address asset) public view override returns (uint256) {
        return assetValue(asset, assetBalance(asset));
    }

    function getSupportedAssets()
        public
        view
        override
        returns (address[] memory)
    {
        return supportedAssets;
    }

    function getFundComposition()
        public
        view
        returns (
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256 assetCount = supportedAssets.length;

        address[] memory assets = new address[](assetCount);
        uint256[] memory balances = new uint256[](assetCount);
        uint256[] memory rates = new uint256[](assetCount);

        for (uint256 i = 0; i < assetCount; i++) {
            address asset = supportedAssets[i];
            balances[i] = assetBalance(asset);
            assets[i] = asset;
            rates[i] = IHasAssetInfo(factory).getAssetPrice(asset);
        }

        return (assets, balances, rates);
    }

    function getManagerFee(address pool)
        public
        view
        returns (uint256, uint256)
    {
        return IHasFeeInfo(factory).getPoolManagerFee(pool);
    }

    function _setManagerFeeNumerator(address pool, uint256 numerator) internal {
        IHasFeeInfo(factory).setPoolManagerFeeNumerator(pool, numerator);

        uint256 managerFeeNumerator;
        uint256 managerFeeDenominator;
        (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory)
            .getPoolManagerFee(pool);

        emit ManagerFeeSet(
            address(this),
            manager(),
            managerFeeNumerator,
            managerFeeDenominator
        );
    }

    function announceManagerFeeIncrease(address pool, uint256 numerator)
        public
        onlyManager
    {
        uint256 maximumAllowedChange =
            IHasFeeInfo(factory).getMaximumManagerFeeNumeratorChange();

        uint256 currentFeeNumerator;
        uint256 currentFeeDenominator;
        (currentFeeNumerator, currentFeeDenominator) = getManagerFee(pool);

        require(numerator <= currentFeeDenominator, "invalid fraction");
        require(
            numerator <= currentFeeNumerator.add(maximumAllowedChange),
            "exceeded allowed increase"
        );

        uint256 feeChangeDelay =
            IHasFeeInfo(factory).getManagerFeeNumeratorChangeDelay();

        announcedFeeIncreaseNumerator = numerator;
        announcedFeeIncreaseTimestamp = block.timestamp + feeChangeDelay;
        emit ManagerFeeIncreaseAnnounced(
            numerator,
            announcedFeeIncreaseTimestamp
        );
    }

    function renounceManagerFeeIncrease() public onlyManager {
        announcedFeeIncreaseNumerator = 0;
        announcedFeeIncreaseTimestamp = 0;
        emit ManagerFeeIncreaseRenounced();
    }

    function commitManagerFeeIncrease(address pool) public onlyManager {
        require(
            block.timestamp >= announcedFeeIncreaseTimestamp,
            "fee increase delay active"
        );

        _setManagerFeeNumerator(pool, announcedFeeIncreaseNumerator);

        announcedFeeIncreaseNumerator = 0;
        announcedFeeIncreaseTimestamp = 0;
    }

    function getManagerFeeIncreaseInfo()
        public
        view
        returns (uint256, uint256)
    {
        return (announcedFeeIncreaseNumerator, announcedFeeIncreaseTimestamp);
    }

    uint256[51] private __gap;
}
