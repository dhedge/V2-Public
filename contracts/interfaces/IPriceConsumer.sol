pragma solidity ^0.6.2;

interface IPriceConsumer {
    function addAsset(address _asset, uint8 _assetType, address _aggregator) external;

    function removeAsset(address _asset) external;

    function getAggregator(address _asset) external view returns (address);

    function getUSDPrice(address _asset) external view returns (uint256);
}
