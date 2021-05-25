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
import "../interfaces/IAssetHandler.sol";

contract AssetHandler is Initializable, OwnableUpgradeSafe, IAssetHandler {
    using SafeMath for uint256;
    
    bool public isDisabledChainlink;
    address public poolFactory;

    // Asset Price feeds
    mapping(address => uint8) public override assetTypes; // for asset types refer to header comment
    mapping(address => address) public override priceAggregators;
    // Note: in the future, we can add more mappings for new assets if necessary (eg ERC721)

    // TODO: move this variable above the asset price feeds before mainnet deployment
    uint256 public chainlinkTimeout; // Chainlink oracle timeout period

    function initialize(address _poolFactory, Asset[] memory assets) public initializer {
        OwnableUpgradeSafe.__Ownable_init();

        poolFactory = _poolFactory;
        chainlinkTimeout = 90000; // 25 hours
        addAssets(assets);
    }


    /* ========== VIEWS ========== */

    function getAssetTypeAndAggregator(address asset) public view override returns (uint8, address) {
        return (assetTypes[asset], priceAggregators[asset]);
    }

    /**
     * Returns the latest price of a given asset (decimal: 18)
     * Takes into account the asset type.
     */
    function getUSDPrice(address asset) public view override returns (uint256) {
        address aggregator = priceAggregators[asset];
        uint8 assetType = assetTypes[asset];

        require(aggregator != address(0), "Price aggregator not found");

        uint256 price;

        if (assetType == 0 && !isDisabledChainlink) { // Chainlink direct feed
            try AggregatorV3Interface(aggregator).latestRoundData() returns (uint80, int256 _price, uint256, uint256 updatedAt, uint80) {
                // check chainlink price updated within 25 hours
                require(updatedAt.add(chainlinkTimeout) >= block.timestamp, "Chainlink price expired");

                if (_price > 0) {
                    price = uint256(_price).mul(10**10); // convert Chainlink decimals 8 -> 18
                }
            } catch {
                revert("Price get failed");
            }
        }

        require(price > 0, "Price not available");

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

    function setChainlinkTimeout(uint256 newTimeoutPeriod) external onlyOwner {
        chainlinkTimeout = newTimeoutPeriod;
    }

    /// Add valid asset with price aggregator
    function addAsset(address asset, uint8 assetType, address aggregator) public override onlyOwner {
        assetTypes[asset] = assetType;
        priceAggregators[asset] = aggregator;

        emit AddedAsset(asset, assetType, aggregator);
    }

    function addAssets(Asset[] memory assets) public override onlyOwner {
        for (uint8 i = 0; i < assets.length; i++) {
            addAsset(assets[i].asset, assets[i].assetType, assets[i].aggregator);
        }
    }

    /// Remove valid asset
    function removeAsset(address asset) public override onlyOwner {
        assetTypes[asset] = 0;
        priceAggregators[asset] = address(0);

        emit RemovedAsset(asset);
    }

    uint256[50] private __gap;
}
