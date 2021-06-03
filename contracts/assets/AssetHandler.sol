// For dHEDGE Asset Price Feeds
// Asset types:
// 0 = Chainlink direct USD price feed with 8 decimals

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2; // TODO: Can we upgrade the solidity versions to include ABIEncoderV2 by default? (not experimental)

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../interfaces/IHasDaoInfo.sol";
import "../interfaces/IAssetHandler.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IERC20Extended.sol"; // includes decimals()
import "../utils/DhedgeMath.sol";

contract AssetHandler is Initializable, OwnableUpgradeSafe, IAssetHandler {
  using SafeMath for uint256;

  uint256 public chainlinkTimeout; // Chainlink oracle timeout period
  address public poolFactory;

  // Asset Price feeds
  mapping(address => uint8) public override assetTypes; // for asset types refer to header comment
  mapping(address => address) public override priceAggregators;

  // Note: in the future, we can add more mappings for new assets if necessary (eg ERC721)

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
  function getUSDPrice(address asset) public view override returns (uint256 price) {
    address aggregator = priceAggregators[asset];
    uint8 assetType = assetTypes[asset];

    if (assetType == 0) {
      // Chainlink direct feed
      require(aggregator != address(0), "Price aggregator not found");

      try AggregatorV3Interface(aggregator).latestRoundData() returns (
        uint80,
        int256 _price,
        uint256,
        uint256 updatedAt,
        uint80
      ) {
        // check chainlink price updated within 25 hours
        require(updatedAt.add(chainlinkTimeout) >= block.timestamp, "Chainlink price expired");

        if (_price > 0) {
          price = uint256(_price).mul(10**10); // convert Chainlink decimals 8 -> 18
        }
      } catch {
        revert("Price get failed");
      }
    } else if (assetType == 2) {
      // Uniswap LP token pricing
      // referenced from https://github.com/sushiswap/kashi-lending/blob/master/contracts/oracles/LPChainlinkOracle.sol

      uint256 totalSupply = IUniswapV2Pair(asset).totalSupply();
      address token0 = IUniswapV2Pair(asset).token0();
      address token1 = IUniswapV2Pair(asset).token1();
      (uint256 r0, uint256 r1, ) = IUniswapV2Pair(asset).getReserves();
      uint256 decimal0 = IERC20Extended(token0).decimals();
      uint256 decimal1 = IERC20Extended(token1).decimals();

      r0 = r0.mul(10**18).div(10**decimal0); // decimal = 18
      r1 = r1.mul(10**18).div(10**decimal1); // decimal = 18
      uint256 k = DhedgeMath.sqrt(r0.mul(r1)); // decimal = 18

      uint256 p0 = getUSDPrice(token0); // decimal = 18
      uint256 p1 = getUSDPrice(token1); // decimal = 18
      uint256 p = DhedgeMath.sqrt(p0.mul(p1)); // decimal = 18

      price = k.mul(p).mul(2).div(totalSupply); // decimal = 18
    }

    require(price > 0, "Price not available");
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /* ---------- From Owner ---------- */

  function setPoolFactory(address _poolFactory) external onlyOwner {
    poolFactory = _poolFactory;
  }

  function setChainlinkTimeout(uint256 newTimeoutPeriod) external onlyOwner {
    chainlinkTimeout = newTimeoutPeriod;
  }

  /// Add valid asset with price aggregator
  function addAsset(
    address asset,
    uint8 assetType,
    address aggregator
  ) public override onlyOwner {
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
