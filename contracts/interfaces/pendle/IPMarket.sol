// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable
pragma solidity 0.7.6;

interface IPMarket {
  function readTokens() external view returns (address _SY, address _PT, address _YT);

  function expiry() external view returns (uint256);
}
