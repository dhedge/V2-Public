// For dHEDGE Asset Price Feeds
// Asset types:
// 0 = Chainlink direct USD price feed with 8 decimals

pragma solidity ^0.6.2;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../interfaces/IHasDaoInfo.sol";

contract PriceConsumer is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    
    bool public isDisabledChainlink;
    address public poolFactory;

    // Asset Price feeds
    mapping(address => uint8) internal assetTypes; // asset types (refer to header comment)
    mapping(address => address) internal aggregators; // price feeds (usd)

    function initialize(address _poolFactory) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        poolFactory = _poolFactory;
    }


    /* ========== VIEWS ========== */

    function getAggregator(address asset) public view returns (address) {
        return aggregators[asset];
    }

    function getTypeAndAggregator(address asset) public view returns (uint8, address) {
        return (assetTypes[asset], aggregators[asset]);
    }

    /**
     * Returns the latest price of a given asset (decimal: 18)
     * Takes into account the asset type.
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


    /* ========== MUTATIVE FUNCTIONS ========== */

    /* ---------- From Owner ---------- */

    function setPoolFactory(address _poolFactory) external onlyOwner {
        poolFactory = _poolFactory;
    }

    /* ---------- From DAO ---------- */

    function enableChainlink() external onlyDao {
        isDisabledChainlink = false;
    }

    function disableChainlink() external onlyDao {
        isDisabledChainlink = true;
    }

    /* ---------- From Pool Factory ---------- */

    /**
     * Add valid asset with price aggregator
     */
    function addAsset(address asset, uint8 assetType, address aggregator) external onlyPoolFactory {
        aggregators[asset] = aggregator;
        assetTypes[asset] = assetType;
    }

    /**
     * Remove valid asset
     */
    function removeAsset(address asset) external onlyPoolFactory {
        aggregators[asset] = address(0);
        assetTypes[asset] = 0;
    }


    /* ========== MODIFIERS ========== */

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
