// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "./IOptionMarket.sol";

interface IOptionGreekCache {
  function isGlobalCacheStale(uint256 spotPrice) external view returns (bool);

  function isBoardCacheStale(uint256 boardId) external view returns (bool);

  function updateBoardCachedGreeks(uint256 boardId) external;

  function getMinCollateral(
    IOptionMarket.OptionType optionType,
    uint256 strikePrice,
    uint256 expiry,
    uint256 spotPrice,
    uint256 amount
  ) external view returns (uint256 minCollateral);
}
