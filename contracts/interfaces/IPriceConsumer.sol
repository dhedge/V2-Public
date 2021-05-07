pragma solidity ^0.6.2;

interface IPriceConsumer {
    function addAggregator(address _asset, uint8 _assetType, address _aggregator) external;

    function removeAggregator(address _asset) external;

    function getUSDPrice(address _asset) external view returns (uint256);
}
