pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

interface IPriceConsumer {
    
    struct AssetPriceFeed {
        uint8 assetType;
        address aggregator;
    }

    function addAsset(address asset, uint8 assetType, address aggregator) external;

    function removeAsset(address asset) external;

    function getAggregator(address asset) external view returns (address);

    function getUSDPrice(address asset) external view returns (uint256);
}
