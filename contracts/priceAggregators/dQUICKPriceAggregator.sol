// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/IAggregatorV3Interface.sol";
import "../interfaces/quick/IDragonLair.sol";
import "../interfaces/IHasAssetInfo.sol";

/**
 * @title dQUICK price aggregator.
 * @notice You can use this contract for dQUICK token pricing oracle.
 * @dev This should have `latestRoundData` function as chainlink pricing oracle.
 */
contract DQUICKPriceAggregator is IAggregatorV3Interface {
  using SafeMath for uint256;

  address public dQUICK;
  address public quick;
  address public factory;

  constructor(address _dQUICK, address _quick, address _factory) {
    require(_dQUICK != address(0), "_dQUICK address cannot be 0");
    require(_quick != address(0), "_quick address cannot be 0");
    require(_factory != address(0), "_factory address cannot be 0");

    dQUICK = _dQUICK;
    quick = _quick;
    factory = _factory;
  }

  /* ========== VIEWS ========== */

  function decimals() external pure override returns (uint8) {
    return 8;
  }

  /**
   * @notice Get the latest round data. Should be the same format as chainlink aggregator.
   * @return roundId The round ID.
   * @return answer The price - the latest round data of dQUICk token (price decimal: 8)
   * @return startedAt Timestamp of when the round started.
   * @return updatedAt Timestamp of when the round was updated.
   * @return answeredInRound The round ID of the round in which the answer was computed.
   */
  function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
    uint256 quickPrice = _getQUICKPrice(); // decimals = 18

    uint256 dQUICKRatio = IDragonLair(dQUICK).dQUICKForQUICK(10 ** 18); // decimals = 18

    uint256 answer = quickPrice.mul(dQUICKRatio).div(10 ** 28); // decimals = 8

    // we don't need roundId, startedAt and answeredInRound
    return (0, int256(answer), 0, block.timestamp, 0);
  }

  /* ========== INTERNAL ========== */

  function _getQUICKPrice() internal view returns (uint256) {
    return IHasAssetInfo(factory).getAssetPrice(quick);
  }
}
