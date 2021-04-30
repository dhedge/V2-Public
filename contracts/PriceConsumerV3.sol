pragma solidity ^0.6.2;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";

contract PriceConsumerV3 {
    using SafeMath for uint256;
    
    bool internal isDisabledChainlink;
    mapping(address => address) internal aggregators; // chainlink price feeds (usd)

    constructor() public {}

    /**
     * Add aggregator for an asset
     */
    function _addAggregator(address _asset, address _aggregator) internal {
        aggregators[_asset] = _aggregator;
    }

    /**
     * Remove aggregator for an asset
     */
    function _removeAggregator(address _asset) internal {
        aggregators[_asset] = address(0);
    }

    /**
     * enable chainlink
     */
    function _enableChainlink() internal {
        isDisabledChainlink = false;
    }

    /**
     * disable chainlink
     */
    function _disableChainlink() internal {
        isDisabledChainlink = true;
    }

    /**
     * Returns the latest price of a give asset (decimal: 8)
     */
    function getUSDPrice(address _asset) public view returns (uint256) {
        address aggregator = aggregators[_asset];

        require(aggregator != address(0), "PriceConsumerV3: aggregator not found");

        uint256 price;

        if (!isDisabledChainlink) {
            (, int256 _price, , uint256 updatedAt, ) =
                AggregatorV3Interface(aggregator).latestRoundData();

            // check chainlink price updated within 25 hours
            require(updatedAt.add(90000) >= block.timestamp, "PriceConsumerV3: chainlink price expired");

            if (_price > 0) {
                price = uint256(_price);
            }
        }

        require(price > 0, "PriceConsumerV3: price not available");

        // decimals -> 36 - decimal
        uint256 decimals = uint256(ERC20UpgradeSafe(_asset).decimals());

        return price.mul(10**28).div(10**decimals);
    }
}
