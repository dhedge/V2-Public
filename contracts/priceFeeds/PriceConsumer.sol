// For dHEDGE Asset Price Feeds
// Asset types:
// 0 = Chainlink direct USD price feed with 8 decimals

pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2; // TODO: Can we upgrade the solidity versions to include ABIEncoderV2 by default? (not experimental)

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../interfaces/IHasDaoInfo.sol";
import "../interfaces/IPriceConsumer.sol";

contract PriceConsumer is Initializable, OwnableUpgradeSafe, IPriceConsumer {
    using SafeMath for uint256;
    
    bool public isDisabledChainlink;
    address public poolFactory;

    // Asset Price feeds
    mapping(address => uint8) internal assetTypes; // for asset types refer to header comment
    mapping(address => address) internal aggregators;
    // Note: in the future, we can add more mappings for new assets if necessary (eg ERC721)

    function initialize(address _poolFactory, Asset[] memory assets) public initializer {
        OwnableUpgradeSafe.__Ownable_init();

        poolFactory = _poolFactory;
        addAssets(assets);
    }


    /* ========== VIEWS ========== */

    function getAggregator(address asset) public view override returns (address) {
        return aggregators[asset];
    }

    function getTypeAndAggregator(address asset) public view override returns (uint8, address) {
        return (assetTypes[asset], aggregators[asset]);
    }

    /**
     * Returns the latest price of a given asset (decimal: 18)
     * Takes into account the asset type.
     */
    function getUSDPrice(address asset) public view override returns (uint256) {
        address aggregator = aggregators[asset];
        uint8 assetType = assetTypes[asset];

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

    function enableChainlink() external onlyOwner {
        isDisabledChainlink = false;
    }

    function disableChainlink() external onlyOwner {
        isDisabledChainlink = true;
    }

    /// Add valid asset with price aggregator
    function addAsset(address asset, uint8 assetType, address aggregator) public override onlyOwner {
        assetTypes[asset] = assetType;
        aggregators[asset] = aggregator;
    }

    function addAssets(Asset[] memory assets) public override onlyOwner {
        for (uint8 i = 0; i < assets.length; i++) {
            addAsset(assets[i].asset, assets[i].assetType, assets[i].aggregator);
        }
    }

    /// Remove valid asset
    function removeAsset(address asset) public override onlyOwner {
        assetTypes[asset] = 0;
        aggregators[asset] = address(0);
    }

    uint256[50] private __gap;
}
