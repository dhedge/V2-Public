// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./IAddressResolver.sol";

interface IFuturesMarketSettings {
  function minInitialMargin() external view returns (uint256);
}
