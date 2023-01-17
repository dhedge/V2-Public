// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/velodrome/IVelodromePair.sol";
import "../interfaces/IERC20Extended.sol"; // includes decimals()
import "../interfaces/IHasAssetInfo.sol";
import "../utils/DhedgeMath.sol";

/**
 * @title Velodrome TWAP aggregator.
 * @notice You can use this contract for token pricing oracle using Velodrome TWAP.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract VelodromeTWAPAggregator is IAggregatorV3Interface {
  using SafeMathUpgradeable for uint256;

  address public pair;
  address public immutable mainToken; // the token for which to get the TWAP price (eg Velo)
  address public immutable pairToken;
  uint256 public immutable mainTokenUnit; // 1 main token in wei
  uint256 public immutable pairTokenUnit; // 1 pair token in wei
  IAggregatorV3Interface public immutable pairTokenUsdAggregator; // Chainlink USD aggregator of pairing token (eg WETH)

  constructor(
    address _pair,
    address _mainToken,
    address _pairToken,
    IAggregatorV3Interface _pairTokenUsdAggregator
  ) {
    require(_pair != address(0), "_pair address cannot be 0");
    address token0 = IVelodromePair(_pair).token0();
    address token1 = IVelodromePair(_pair).token1();
    require(
      (_mainToken == token0 && _pairToken == token1) || (_mainToken == token1 && _pairToken == token0),
      "invalid tokens"
    );

    pair = _pair;
    mainToken = _mainToken;
    pairToken = _pairToken;
    mainTokenUnit = 10**IERC20Extended(_mainToken).decimals();
    pairTokenUnit = 10**IERC20Extended(_pairToken).decimals();
    pairTokenUsdAggregator = _pairTokenUsdAggregator;
  }

  /* ========== VIEWS ========== */

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of a given velodrome lp token (price decimal: 8)
   * @return startedAt Timestamp of when the round started.
   * @return updatedAt Timestamp of when the round was updated.
   * @return answeredInRound The round ID of the round in which the answer was computed.
   */
  function latestRoundData()
    external
    view
    override
    returns (
      uint80,
      int256,
      uint256,
      uint256,
      uint80
    )
  {
    (, int256 pairUsdPrice, , , ) = pairTokenUsdAggregator.latestRoundData(); // decimals 8
    uint256 quoteAmount = IVelodromePair(pair).current(mainToken, mainTokenUnit);
    uint256 answer = uint256(pairUsdPrice).mul(quoteAmount).div(pairTokenUnit);

    // we don't need roundId, startedAt and answeredInRound
    return (0, int256(answer), 0, block.timestamp, 0);
  }
}
