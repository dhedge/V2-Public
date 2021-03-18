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

pragma solidity ^0.6.2;

import "./ISynthetix.sol";
import "./IExchanger.sol";
import "./ISynth.sol";
import "./IExchangeRates.sol";
import "./IAddressResolver.sol";
import "./ISystemStatus.sol";
import "./Managed.sol";
import "./IHasDaoInfo.sol";
import "./IHasFeeInfo.sol";
import "./IHasAssetInfo.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";

contract DHedge is Initializable, ERC20UpgradeSafe, Managed {
    using SafeMath for uint256;

    bytes32 constant private _EXCHANGE_RATES_KEY = "ExchangeRates";
    bytes32 constant private _SYNTHETIX_KEY = "Synthetix";
    bytes32 constant private _EXCHANGER_KEY = "Exchanger";
    bytes32 constant private _SYSTEM_STATUS_KEY = "SystemStatus";
    bytes32 constant private _SUSD_KEY = "sUSD";

    event Deposit(
        address fundAddress,
        address investor,
        uint256 valueDeposited,
        uint256 fundTokensReceived,
        uint256 totalInvestorFundTokens,
        uint256 fundValue,
        uint256 totalSupply,
        uint256 time
    );
    event Withdrawal(
        address fundAddress,
        address investor,
        uint256 valueWithdrawn,
        uint256 fundTokensWithdrawn,
        uint256 totalInvestorFundTokens,
        uint256 fundValue,
        uint256 totalSupply,
        uint256 time
    );
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

    event PoolPrivacyUpdated(bool isPoolPrivate);

    event ManagerFeeMinted(
        address pool,
        address manager,
        uint256 available,
        uint256 daoFee,
        uint256 managerFee,
        uint256 tokenPriceAtLastFeeMint
    );

    event ManagerFeeSet(
        address fundAddress,
        address manager,
        uint256 numerator,
        uint256 denominator
    );

    bool public privatePool;
    address public creator;

    uint256 public creationTime;

    IAddressResolver public addressResolver;

    address public factory;

    bytes32[] public supportedAssets;
    mapping(bytes32 => uint256) public assetPosition; // maps the asset to its 1-based position

    mapping(bytes32 => bool) public persistentAsset;

    // Manager fees
    uint256 public tokenPriceAtLastFeeMint;

    mapping(address => uint256) public lastDeposit;

    modifier onlyPrivate() {
        require(
            msg.sender == manager() ||
                !privatePool ||
                isMemberAllowed(msg.sender),
            "only members allowed"
        );
        _;
    }

    function initialize(
        address _factory,
        bool _privatePool,
        address _manager,
        string memory _managerName,
        string memory _fundName,
        IAddressResolver _addressResolver,
        bytes32[] memory _supportedAssets
    ) public initializer {
        ERC20UpgradeSafe.__ERC20_init(_fundName, "DHPT");
        Managed.initialize(_manager, _managerName);

        factory = _factory;
        _setPoolPrivacy(_privatePool);
        creator = msg.sender;
        creationTime = block.timestamp;
        addressResolver = _addressResolver;

        _addToSupportedAssets(_SUSD_KEY);

        for(uint8 i = 0; i < _supportedAssets.length; i++) {
            _addToSupportedAssets(_supportedAssets[i]);
        }

        // Set persistent assets
        persistentAsset[_SUSD_KEY] = true;

        tokenPriceAtLastFeeMint = 10**18;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal virtual override
    {
        super._beforeTokenTransfer(from, to, amount);

        require(getExitFeeRemainingCooldown(from) == 0, "cooldown active");
    }

    function setPoolPrivate(bool _privatePool) public onlyManager {
        require(privatePool != _privatePool, "flag must be different");

        _setPoolPrivacy(_privatePool);
    }

    function _setPoolPrivacy(bool _privacy) internal {
        privatePool = _privacy;

        emit PoolPrivacyUpdated(_privacy);
    }

    function getAssetProxy(bytes32 key) public view returns (address) {
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

    function addToSupportedAssets(bytes32 key) public onlyManager {
        _addToSupportedAssets(key);
    }

    function removeFromSupportedAssets(bytes32 key) public onlyManager {
        require(isAssetSupported(key), "asset not supported");

        require(!persistentAsset[key], "persistent assets can't be removed");

        // ISynthetix sx = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY));
        // sx.settle(key);

        require(
            IERC20(getAssetProxy(key)).balanceOf(address(this)) == 0,
            "non-empty asset cannot be removed"
        );

        require(key != _SUSD_KEY, "sUSD can't be removed");

        _removeFromSupportedAssets(key);
    }

    function numberOfSupportedAssets() public view returns (uint256) {
        return supportedAssets.length;
    }

    // Unsafe internal method that assumes we are not adding a duplicate
    function _addToSupportedAssets(bytes32 key) internal {
        require(supportedAssets.length < IHasAssetInfo(factory).getMaximumSupportedAssetCount(), "maximum assets reached");
        require(!isAssetSupported(key), "asset already supported");
        require(validateAsset(key) == true, "not an asset");

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
    ) public onlyManager {
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
            manager(),
            sourceKey,
            sourceAmount,
            destinationKey,
            destinationAmount,
            block.timestamp
        );
    }

    function totalFundValue() public virtual view returns (uint256) {
        uint256 total = 0;
        uint256 assetCount = supportedAssets.length;

        for (uint256 i = 0; i < assetCount; i++) {
            total = total.add(assetValue(supportedAssets[i]));
        }
        return total;
    }

    function assetValue(bytes32 key) public view returns (uint256) {
        return
            IExchangeRates(addressResolver.getAddress(_EXCHANGE_RATES_KEY))
                .effectiveValue(
                key,
                IERC20(getAssetProxy(key)).balanceOf(address(this)),
                _SUSD_KEY
            );
    }

    function deposit(uint256 _susdAmount) public onlyPrivate returns (uint256) {
        lastDeposit[msg.sender] = block.timestamp;

        //we need to settle all the assets before determining the total fund value
        // _settleAll();

        _mintManagerFee(false);

        uint256 fundValue = totalFundValue();
        uint256 totalSupplyBefore = totalSupply();

        // IExchanger sx = IExchanger(addressResolver.getAddress(_EXCHANGER_KEY));
        // sx.settle(msg.sender, _SUSD_KEY);

        require(
            IERC20(getAssetProxy(_SUSD_KEY)).transferFrom(
                msg.sender,
                address(this),
                _susdAmount
            ),
            "token transfer failed"
        );

        uint256 liquidityMinted;
        if (totalSupplyBefore > 0) {
            //total balance converted to susd that this contract holds
            //need to calculate total value of synths in this contract
            liquidityMinted = _susdAmount.mul(totalSupplyBefore).div(fundValue);
        } else {
            liquidityMinted = _susdAmount;
        }

        _mint(msg.sender, liquidityMinted);

        emit Deposit(
            address(this),
            msg.sender,
            _susdAmount,
            liquidityMinted,
            balanceOf(msg.sender),
            fundValue.add(_susdAmount),
            totalSupplyBefore.add(liquidityMinted),
            block.timestamp
        );

        return liquidityMinted;
    }

    // function _settleAll() internal {
    //     ISynthetix sx = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY));

    //     uint256 assetCount = supportedAssets.length;

    //     for (uint256 i = 0; i < assetCount; i++) {

    //         address proxy = getAssetProxy(supportedAssets[i]);
    //         uint256 totalAssetBalance = IERC20(proxy).balanceOf(address(this));

    //         if (totalAssetBalance > 0)
    //             sx.settle(supportedAssets[i]);

    //     }
    // }

    // function _settleNotSuspended() internal {
    //     ISynthetix sx = ISynthetix(addressResolver.getAddress(_SYNTHETIX_KEY));
    //     ISystemStatus status = ISystemStatus(addressResolver.getAddress(_SYSTEM_STATUS_KEY));

    //     uint256 assetCount = supportedAssets.length;

    //     for (uint256 i = 0; i < assetCount; i++) {
    //         try status.requireSynthActive(supportedAssets[i]) {

    //             address proxy = getAssetProxy(supportedAssets[i]);
    //             uint256 totalAssetBalance = IERC20(proxy).balanceOf(address(this));

    //             if (totalAssetBalance > 0)
    //                 sx.settle(supportedAssets[i]);

    //         } catch {
    //             continue;
    //         }
    //     }
    // }

    function withdraw(uint256 _fundTokenAmount) public virtual {
        _withdraw(_fundTokenAmount, false);
    }

    function forfeitSuspendedSynthsAndWithdraw(uint256 _fundTokenAmount) public virtual {
        _withdraw(_fundTokenAmount, true);
    }

    function _withdraw(uint256 _fundTokenAmount, bool _forfeitSuspendedSynths) internal {
        require(
            balanceOf(msg.sender) >= _fundTokenAmount,
            "insufficient balance of fund tokens"
        );

        //calculate the exit fee and transfer to the DAO in pool tokens
        uint256 exitFeeNumerator;
        uint256 exitFeeDenominator;

        if (getExitFeeRemainingCooldown(msg.sender) > 0) {
            (exitFeeNumerator, exitFeeDenominator) = IHasFeeInfo(factory).getExitFee();
        } else {
            exitFeeNumerator = 0;
            exitFeeDenominator = 1;
        }

        uint256 daoExitFee = _fundTokenAmount.mul(exitFeeNumerator).div(exitFeeDenominator);

        uint256 lastDepositTemp = lastDeposit[msg.sender];
        lastDeposit[msg.sender] = 0;

        if (daoExitFee > 0) {
            address daoAddress = IHasDaoInfo(factory).getDaoAddress();

            _transfer(msg.sender, daoAddress, daoExitFee);
        }

        //we need to settle all the assets before determining the total fund value
        // if(_forfeitSuspendedSynths){
        //     _settleNotSuspended();
        // } else {
        //     _settleAll();
        // }

        _mintManagerFee(false);

        uint256 fundValue = totalFundValue();

        //calculate the proportion
        _fundTokenAmount = _fundTokenAmount.sub(daoExitFee);
        uint256 portion = _fundTokenAmount.mul(10**18).div(totalSupply());

        //first return funded tokens
        _burn(msg.sender, _fundTokenAmount);

        uint256 assetCount = supportedAssets.length;

        if(_forfeitSuspendedSynths){
            ISystemStatus status = ISystemStatus(addressResolver.getAddress(_SYSTEM_STATUS_KEY));
            for (uint256 i = 0; i < assetCount; i++) {
                try status.requireSynthActive(supportedAssets[i]) {

                    address proxy = getAssetProxy(supportedAssets[i]);
                    uint256 totalAssetBalance = IERC20(proxy).balanceOf(address(this));
                    uint256 portionOfAssetBalance = totalAssetBalance.mul(portion).div(10**18);

                    if (portionOfAssetBalance > 0) {
                        IERC20(proxy).transfer(msg.sender, portionOfAssetBalance);
                    }

                } catch {
                    continue;
                }
            }
        } else {
            for (uint256 i = 0; i < assetCount; i++) {
                address proxy = getAssetProxy(supportedAssets[i]);
                uint256 totalAssetBalance = IERC20(proxy).balanceOf(address(this));
                uint256 portionOfAssetBalance = totalAssetBalance.mul(portion).div(10**18);

                if (portionOfAssetBalance > 0) {
                    IERC20(proxy).transfer(msg.sender, portionOfAssetBalance);
                }
            }
        }

        uint256 valueWithdrawn = portion.mul(fundValue);

        lastDeposit[msg.sender] = lastDepositTemp;

        emit Withdrawal(
            address(this),
            msg.sender,
            valueWithdrawn,
            _fundTokenAmount,
            balanceOf(msg.sender),
            totalFundValue(),
            totalSupply(),
            block.timestamp
        );
    }

    function getFundSummary()
        public
        view
        returns (
            string memory,
            uint256,
            uint256,
            address,
            string memory,
            uint256,
            bool,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {

        uint256 managerFeeNumerator;
        uint256 managerFeeDenominator;
        (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory).getPoolManagerFee(address(this));

        uint256 exitFeeNumerator;
        uint256 exitFeeDenominator;
        (exitFeeNumerator, exitFeeDenominator) = IHasFeeInfo(factory).getExitFee();

        return (
            name(),
            totalSupply(),
            totalFundValue(),
            manager(),
            managerName(),
            creationTime,
            privatePool,
            managerFeeNumerator,
            managerFeeDenominator,
            exitFeeNumerator,
            exitFeeDenominator
        );
    }

    function getSupportedAssets() public view returns (bytes32[] memory) {
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

    // function getWaitingPeriods()
    //     public
    //     view
    //     returns (
    //         bytes32[] memory,
    //         uint256[] memory
    //     )
    // {
    //     uint256 assetCount = supportedAssets.length;

    //     bytes32[] memory assets = new bytes32[](assetCount);
    //     uint256[] memory periods = new uint256[](assetCount);

    //     IExchanger exchanger = IExchanger(addressResolver.getAddress(_EXCHANGER_KEY));

    //     for (uint256 i = 0; i < assetCount; i++) {
    //         bytes32 asset = supportedAssets[i];
    //         assets[i] = asset;
    //         periods[i] = exchanger.maxSecsLeftInWaitingPeriod(address(this), asset);
    //     }

    //     return (assets, periods);
    // }

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

    // MANAGER FEES

    function tokenPrice() public view returns (uint256) {
        uint256 fundValue = totalFundValue();
        uint256 tokenSupply = totalSupply();

        return _tokenPrice(fundValue, tokenSupply);
    }

    function _tokenPrice(uint256 _fundValue, uint256 _tokenSupply)
        internal
        pure
        returns (uint256)
    {
        if (_tokenSupply == 0 || _fundValue == 0) return 0;

        return _fundValue.mul(10**18).div(_tokenSupply);
    }

    function availableManagerFee() public view returns (uint256) {
        uint256 fundValue = totalFundValue();
        uint256 tokenSupply = totalSupply();

        uint256 managerFeeNumerator;
        uint256 managerFeeDenominator;
        (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory).getPoolManagerFee(address(this));

        return
            _availableManagerFee(
                fundValue,
                tokenSupply,
                tokenPriceAtLastFeeMint,
                managerFeeNumerator,
                managerFeeDenominator
            );
    }

    function _availableManagerFee(
        uint256 _fundValue,
        uint256 _tokenSupply,
        uint256 _lastFeeMintPrice,
        uint256 _feeNumerator,
        uint256 _feeDenominator
    ) internal pure returns (uint256) {
        if (_tokenSupply == 0 || _fundValue == 0) return 0;

        uint256 currentTokenPrice = _fundValue.mul(10**18).div(_tokenSupply);

        if (currentTokenPrice <= _lastFeeMintPrice) return 0;

        uint256 available = currentTokenPrice
            .sub(_lastFeeMintPrice)
            .mul(_tokenSupply)
            .mul(_feeNumerator)
            .div(_feeDenominator)
            .div(10**18);

        return available;
    }

    function mintManagerFee() public {
        _mintManagerFee(true);
    }

    function _mintManagerFee(bool settle) internal {
        //we need to settle all the assets before minting the manager fee
        // if (settle)
        //     _settleAll();

        uint256 fundValue = totalFundValue();
        uint256 tokenSupply = totalSupply();

        uint256 managerFeeNumerator;
        uint256 managerFeeDenominator;
        (managerFeeNumerator, managerFeeDenominator) = IHasFeeInfo(factory).getPoolManagerFee(address(this));

        uint256 available = _availableManagerFee(
            fundValue,
            tokenSupply,
            tokenPriceAtLastFeeMint,
            managerFeeNumerator,
            managerFeeDenominator
        );

        // Ignore dust when minting performance fees
        if (available < 100)
            return;

        address daoAddress = IHasDaoInfo(factory).getDaoAddress();
        uint256 daoFeeNumerator;
        uint256 daoFeeDenominator;

        (daoFeeNumerator, daoFeeDenominator) = IHasDaoInfo(factory).getDaoFee();

        uint256 daoFee = available.mul(daoFeeNumerator).div(daoFeeDenominator);
        uint256 managerFee = available.sub(daoFee);

        if (daoFee > 0) _mint(daoAddress, daoFee);

        if (managerFee > 0) _mint(manager(), managerFee);

        tokenPriceAtLastFeeMint = _tokenPrice(fundValue, tokenSupply);

        emit ManagerFeeMinted(
            address(this),
            manager(),
            available,
            daoFee,
            managerFee,
            tokenPriceAtLastFeeMint
        );
    }

    function getManagerFee() external view returns (uint256, uint256) {
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

    // Exit fees

    // function getExitFee() external view returns (uint256, uint256) {
    //     return IHasFeeInfo(factory).getExitFee();
    // }

    function getExitFeeCooldown() external view returns (uint256) {
        return IHasFeeInfo(factory).getExitFeeCooldown();
    }

    function getExitFeeRemainingCooldown(address sender) public view returns (uint256) {
        uint256 cooldown = IHasFeeInfo(factory).getExitFeeCooldown();
        uint256 cooldownFinished = lastDeposit[sender].add(cooldown);

        if (cooldownFinished < block.timestamp)
            return 0;

        return cooldownFinished.sub(block.timestamp);
    }

    uint256[50] private __gap;
}
