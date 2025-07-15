// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IPMarketFactoryV3 {
  function isValidMarket(address market) external view returns (bool);
}
