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

import "hardhat/console.sol";

pragma solidity ^0.6.2;

import "./interfaces/ISynthetix.sol";
import "./interfaces/IExchangeRates.sol";
import "./interfaces/IAddressResolver.sol";
import "./PoolLogic.sol";
import "./upgradability/ProxyFactory.sol";
import "./interfaces/IHasDaoInfo.sol";
import "./interfaces/IHasFeeInfo.sol";
import "./interfaces/IHasAssetInfo.sol";

contract PoolFactory is ProxyFactory, IHasDaoInfo, IHasFeeInfo, IHasAssetInfo {
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
    event ExitFeeCooldownSet(uint256 cooldown);

    event MaximumSupportedAssetCountSet(uint256 count);

    IAddressResolver public addressResolver;

    address public addressResolverAddress;

    address[] public deployedFunds;

    address internal _daoAddress;
    uint256 internal _daoFeeNumerator;
    uint256 internal _daoFeeDenominator;

    mapping (address => bool) public isPool;

    uint256 private _MAXIMUM_MANAGER_FEE_NUMERATOR;
    uint256 private _MANAGER_FEE_DENOMINATOR;
    mapping (address => uint256) public poolManagerFeeNumerator;
    mapping (address => uint256) public poolManagerFeeDenominator;

    uint256 internal _exitFeeNumerator;
    uint256 internal _exitFeeDenominator;
    uint256 internal _exitFeeCooldown;

    uint256 internal _maximumSupportedAssetCount;

    bytes32 internal _trackingCode;

    function initialize(address _addressResolver, address _poolLogic, address _managerLogic, address daoAddress) public initializer {
        __ProxyFactory_init(_poolLogic, _managerLogic);

        addressResolver = IAddressResolver(_addressResolver);

        addressResolverAddress = _addressResolver;

        _setDaoAddress(daoAddress);

        _setMaximumManagerFee(5000, 10000);

        _setDaoFee(10, 100); // 10%
        _setExitFee(5, 1000); // 0.5%
        _setExitFeeCooldown(1 days);

        _setMaximumSupportedAssetCount(10);

        _setTrackingCode(
            0x4448454447450000000000000000000000000000000000000000000000000000
        );
    }

    function createFund(
        bool _privatePool,
        address _manager,
        string memory _managerName,
        string memory _fundName,
        uint256 _managerFeeNumerator,
        bytes32[] memory _supportedAssets
    ) public returns (address) {
        console.log("factory %s", address(this));
        console.log("_manager %s", _manager);
        console.log("_managerName %s", _managerName);
        console.log("addressResolverAddress %s", addressResolverAddress);
        bytes memory managerLogicData = abi.encodeWithSignature(
            "initialize(address,address,string,address,bytes32[])",
            address(this),
            // _privatePool,
            _manager,
            _managerName,
            // _fundName,
            // addressResolver,
            addressResolverAddress,
            _supportedAssets
        );

        address managerLogic = deploy(managerLogicData, 1);

        console.log("deployed managerLogic");

        bytes memory poolLogicData = abi.encodeWithSignature(
            "initialize(address,bool,address,string,string,address)",
            address(this),
            _privatePool,
            _manager,
            _managerName,
            _fundName,
            managerLogic
            // addressResolver,
            // _supportedAssets
        );

        address fund = deploy(poolLogicData, 2);

        deployedFunds.push(fund);
        isPool[fund] = true;

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

    function deployedFundsLength() external view returns (uint256) {
        return deployedFunds.length;
    }

    // DAO info

    function getDaoAddress() public override view returns (address) {
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

    function getDaoFee() public override view returns (uint256, uint256) {
        return (_daoFeeNumerator, _daoFeeDenominator);
    }

    modifier onlyPool() {
        require(
            isPool[msg.sender] == true,
            "Only a pool contract can perform this action"
        );
        _;
    }

    // Manager fees

    function getPoolManagerFee(address pool) external override view returns (uint256, uint256) {
        require(isPool[pool] == true, "supplied address is not a pool");

        return (poolManagerFeeNumerator[pool], poolManagerFeeDenominator[pool]);
    }

    function setPoolManagerFeeNumerator(address pool, uint256 numerator) external override {
        require(pool == msg.sender && isPool[msg.sender] == true, "only a pool can change own fee");
        require(isPool[pool] == true, "supplied address is not a pool");
        require(numerator < poolManagerFeeNumerator[pool], "manager fee too high");

        _setPoolManagerFee(msg.sender, numerator, _MANAGER_FEE_DENOMINATOR);
    }

    function _setPoolManagerFee(address pool, uint256 numerator, uint256 denominator) internal {
        require(numerator <= denominator && numerator <= _MAXIMUM_MANAGER_FEE_NUMERATOR, "invalid fraction");

        poolManagerFeeNumerator[pool] = numerator;
        poolManagerFeeDenominator[pool] = denominator;
    }

    function getMaximumManagerFee() public view returns (uint256, uint256) {
        return (_MAXIMUM_MANAGER_FEE_NUMERATOR, _MANAGER_FEE_DENOMINATOR);
    }

    function _setMaximumManagerFee(uint256 numerator, uint256 denominator) internal {
        require(denominator > 0, "denominator must be positive");

        _MAXIMUM_MANAGER_FEE_NUMERATOR = numerator;
        _MANAGER_FEE_DENOMINATOR = denominator;
    }

    // Exit fees

    function setExitFee(uint256 numerator, uint256 denominator) public onlyOwner {
        _setExitFee(numerator, denominator);
    }

    function _setExitFee(uint256 numerator, uint256 denominator) internal {
        require(numerator <= denominator, "invalid fraction");

        _exitFeeNumerator = numerator;
        _exitFeeDenominator = denominator;

        emit ExitFeeSet(numerator, denominator);
    }

    function getExitFee() external override view returns (uint256, uint256) {
        return (_exitFeeNumerator, _exitFeeDenominator);
    }

    function setExitFeeCooldown(uint256 cooldown)
        external
        onlyOwner
    {
        _setExitFeeCooldown(cooldown);
    }

    function _setExitFeeCooldown(uint256 cooldown) internal {
        _exitFeeCooldown = cooldown;

        emit ExitFeeCooldownSet(cooldown);
    }

    function getExitFeeCooldown() public override view returns (uint256) {
        return _exitFeeCooldown;
    }

    // Asset Info

    function setMaximumSupportedAssetCount(uint256 count) external onlyOwner {
        _setMaximumSupportedAssetCount(count);
    }

    function _setMaximumSupportedAssetCount(uint256 count) internal {
        _maximumSupportedAssetCount = count;

        emit MaximumSupportedAssetCountSet(count);
    }

    function getMaximumSupportedAssetCount() external virtual view override returns (uint256) {
        return _maximumSupportedAssetCount;
    }

    // Synthetix tracking

    function setTrackingCode(bytes32 code) external onlyOwner {
        _setTrackingCode(code);
    }

    function _setTrackingCode(bytes32 code) internal {
        _trackingCode = code;
    }

    function getTrackingCode() public override view returns (bytes32) {
        return _trackingCode;
    }

    uint256[50] private __gap;
}

