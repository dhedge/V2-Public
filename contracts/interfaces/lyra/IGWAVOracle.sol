// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

interface IGWAVOracle {
  function deltaGWAV(uint256 strikeId, uint256 secondsAgo) external view returns (int256 callDelta);

  function optionPriceGWAV(uint256 strikeId, uint256 secondsAgo)
    external
    view
    returns (uint256 callPrice, uint256 putPrice);
}
