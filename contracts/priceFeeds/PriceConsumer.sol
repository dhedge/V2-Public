// For dHEDGE Asset Price Feeds
// Asset types:
// 0 = Chainlink direct USD price feed with 8 decimals

pragma solidity ^0.6.2;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../interfaces/IHasDaoInfo.sol";

contract PriceConsumer is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    
    bool internal isDisabledChainlink;
    address public poolFactory;

    // Asset Price feeds
    mapping(address => uint8) internal assetTypes; // asset types (refer to header comment)
    mapping(address => address) internal aggregators; // price feeds (usd)


    function initialize(address _poolFactory) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        poolFactory = _poolFactory;
    }

    // POOL FACTORY FUNCTIONS

    /**
     * Add aggregator for an asset
     */
    function addAggregator(address _asset, uint8 _assetType, address _aggregator) external onlyPoolFactory {
        aggregators[_asset] = _aggregator;
        assetTypes[_asset] = _assetType;
    }

    /**
     * Remove aggregator for an asset
     */
    function removeAggregator(address _asset) external onlyPoolFactory {
        aggregators[_asset] = address(0);
        assetTypes[_asset] = 0;
    }

    // DAO FUNCTIONS

    /**
     * enable chainlink
     */
    function enableChainlink() external onlyDao {
        isDisabledChainlink = false;
    }

    /**
     * disable chainlink
     */
    function disableChainlink() external onlyDao {
        isDisabledChainlink = true;
    }

    // OWNER FUNCTIONS

    function setPoolFactory(address _poolFactory) external onlyOwner {
        poolFactory = _poolFactory;
    }

    // VIEWS

    /**
     * Returns the latest price of a give asset (decimal: 18)
     */
    function getUSDPrice(address _asset) public view returns (uint256) {
        address aggregator = aggregators[_asset];
        uint8 assetType = assetTypes[_asset];

        require(aggregator != address(0), "PriceConsumer: aggregator not found");

        uint256 price;

        if (assetType == 0 && !isDisabledChainlink) { // Chainlink direct feed
            try AggregatorV3Interface(aggregator).latestRoundData() returns (uint80, int256 _price, uint256, uint256 updatedAt, uint80) {
                // check chainlink price updated within 25 hours
                require(updatedAt.add(90000) >= block.timestamp, "PriceConsumer: chainlink price expired");

                if (_price > 0) {
                    price = uint256(_price).mul(10**10); // convert Chainlink decimals 8 -> 18
                }
            } catch {
                revert("PriceConsumer: price get failed");
            }
        }

        require(price > 0, "PriceConsumer: price not available");

        return price;
    }

    // MODIFIERS

    modifier onlyPoolFactory() {
        require(msg.sender == poolFactory, "only pool factory");
        _;
    }

    modifier onlyDao() {
        require(msg.sender == IHasDaoInfo(poolFactory).getDaoAddress(), "only dao");
        _;
    }

    uint256[50] private __gap;
}
