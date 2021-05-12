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
import "./interfaces/IPoolLogic.sol";
import "./interfaces/IPoolManagerLogic.sol";
import "./interfaces/IHasAssetInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasProtocolDaoInfo.sol";
import "./interfaces/IHasGuardInfo.sol";
import "./guards/TxDataUtils.sol";
import "./guards/IGuard.sol";
import "./Managed.sol";
import "./PriceConsumerV3.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";

pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

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
    event AssetAdded(address fundAddress, address manager, address asset, bool isDeposit);
    event AssetRemoved(address fundAddress, address manager, address asset, bool isDeposit);

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
    event PoolLogicSet(address poolLogic, address from);

    address override public factory;
    address override public poolLogic;

    Asset[] public supportedAssets;
    mapping(address => uint256) public assetPosition; // maps the asset to its 1-based position

    // Fee increase announcement
    uint256 public announcedFeeIncreaseNumerator;
    uint256 public announcedFeeIncreaseTimestamp;

    function initialize(
        address _factory,
        address _manager,
        string memory _managerName,
        Asset[] memory _supportedAssets
    ) public initializer {
        initialize(_manager, _managerName);

        factory = _factory;
        // _setPoolPrivacy(_privatePool);

        _changeAssets(_supportedAssets, new Asset[](0));
    }

    function isSupportedAsset(address asset) public view override returns (bool) {
        return assetPosition[asset] != 0;
    }

    function isDepositAsset(address asset) public view override returns(bool) {
        uint256 index = assetPosition[asset];

        return index != 0 &&  supportedAssets[index.sub(1)].isDeposit;
    }

    function validateAsset(address asset) public view override returns (bool) {
        return IHasAssetInfo(factory).isValidAsset(asset);
    }

    function changeAssets(Asset[] memory _addAssets, Asset[] memory _removeAssets) public onlyManagerOrTrader {
        _changeAssets(_addAssets, _removeAssets);
    }

    function _changeAssets(Asset[] memory _addAssets, Asset[] memory _removeAssets) internal {
        for (uint8 i = 0; i < _removeAssets.length; i ++) {
            _removeAsset(_removeAssets[i]);
        }


        for (uint8 i = 0; i < _addAssets.length; i ++) {
            _addAsset(_addAssets[i]);
        }

        require(
            supportedAssets.length <
                IHasAssetInfo(factory).getMaximumSupportedAssetCount(),
            "maximum assets reached"
        );

        require(numberOfDepositAssets() >= 1, "require at least one deposit asset");
    }

    function _addAsset(Asset memory _asset) internal {
        address asset = _asset.asset;
        bool isDeposit = _asset.isDeposit;
        
        require(validateAsset(asset) == true, "invalid asset");

        if (isSupportedAsset(asset)) {
            uint256 index = assetPosition[asset].sub(1);
            supportedAssets[index].isDeposit = isDeposit;
        } else {
            supportedAssets.push(Asset(asset, isDeposit));
            assetPosition[asset] = supportedAssets.length;
        }
    }

    function _removeAsset(Asset memory _asset) internal {
        address asset = _asset.asset;
        bool isDeposit = _asset.isDeposit;

        require(isSupportedAsset(asset), "asset not supported");

        uint256 index = assetPosition[asset].sub(1); // adjusting the index because the map stores 1-based

        if (isDeposit) {
            supportedAssets[index].isDeposit = false;
        } else {
            require(
                assetBalance(asset) == 0,
                "cannot remove non-empty asset"
            );

            uint256 length = supportedAssets.length;
            Asset memory lastAsset = supportedAssets[length.sub(1)];

            // overwrite the asset to be removed with the last supported asset
            supportedAssets[index] = lastAsset;
            assetPosition[lastAsset.asset] = index.add(1); // adjusting the index to be 1-based
            assetPosition[asset] = 0; // update the map

            // delete the last supported asset and resize the array
            supportedAssets.pop();
        }

        emit AssetRemoved(poolLogic, manager(), asset, isDeposit);
    }

    function numberOfSupportedAssets() public view returns (uint256) {
        return supportedAssets.length;
    }

    function numberOfDepositAssets() public view returns (uint256) {
        uint256 result = 0;
        for (uint8 i = 0; i < supportedAssets.length; i ++) {
            if (supportedAssets[i].isDeposit) {
                result = result.add(1);
            }
        }
        return result;
    }

    function execTransaction(address to, bytes memory data)
        public
        onlyManagerOrTrader
        returns (bool)
    {
        require(to != address(0), "non-zero address is required");

        require(!validateAsset(to) || isSupportedAsset(to), "asset not supported");

        address guard = IHasGuardInfo(factory).getGuard(to);

        require(guard != address(0), "invalid destination");

        require(IGuard(guard).txGuard(address(this), data), "invalid transaction");

        (bool success, ) = to.call(data);
        require(success == true, "failed to execute the call");

        emit TransactionExecuted(
            poolLogic,
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
        uint256 price = PriceConsumerV3(factory).getUSDPrice(asset);
        uint256 decimals = uint256(ERC20UpgradeSafe(asset).decimals());
        
        return price.mul(amount).div(10**decimals);
    }

    function assetBalance(address asset) public view returns (uint256) {
        return IERC20(asset).balanceOf(poolLogic);
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
        uint256 assetsCount = supportedAssets.length;
        address[] memory assets = new address[](assetsCount);
        for (uint8 i = 0; i < assetsCount; i ++) {
            assets[i] = supportedAssets[i].asset;
        }
        return assets;
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
            address asset = supportedAssets[i].asset;
            balances[i] = assetBalance(asset);
            assets[i] = asset;
            rates[i] = PriceConsumerV3(factory).getUSDPrice(asset);
        }

        return (assets, balances, rates);
    }

    function getManagerFee()
        public
        view
        returns (uint256, uint256)
    {
        return IHasFeeInfo(factory).getPoolManagerFee(poolLogic);
    }

    function _setManagerFeeNumerator(uint256 numerator) internal {
        IHasFeeInfo(factory).setPoolManagerFeeNumerator(poolLogic, numerator);

        uint256 managerFeeNumerator;
        uint256 managerFeeDenominator;
        (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory)
            .getPoolManagerFee(poolLogic);

        emit ManagerFeeSet(
            poolLogic,
            manager(),
            managerFeeNumerator,
            managerFeeDenominator
        );
    }

    function announceManagerFeeIncrease(uint256 numerator)
        public
        onlyManager
    {
        uint256 maximumAllowedChange =
            IHasFeeInfo(factory).getMaximumManagerFeeNumeratorChange();

        uint256 currentFeeNumerator;
        uint256 currentFeeDenominator;
        (currentFeeNumerator, currentFeeDenominator) = getManagerFee();

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

    function commitManagerFeeIncrease() public onlyManager {
        require(
            block.timestamp >= announcedFeeIncreaseTimestamp,
            "fee increase delay active"
        );

        _setManagerFeeNumerator(announcedFeeIncreaseNumerator);

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

    function setPoolLogic(address _poolLogic)
        external
        override
        returns (bool)
    {
        require(msg.sender == address(factory) || msg.sender == IHasDaoInfo(factory).getDaoAddress(), "only DAO or factory address allowed");

        require(IPoolLogic(_poolLogic).poolManagerLogic() == address(this), "invalid pool logic");

        poolLogic = _poolLogic;
        emit PoolLogicSet(_poolLogic, msg.sender);
        return true;
    }

    uint256[51] private __gap;
}
