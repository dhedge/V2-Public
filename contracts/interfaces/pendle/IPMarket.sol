// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

struct MarketState {
  int256 totalPt;
  int256 totalSy;
  int256 totalLp;
  address treasury;
  int256 scalarRoot;
  uint256 expiry;
  uint256 lnFeeRateRoot;
  uint256 reserveFeePercent;
  uint256 lastLnImpliedRate;
}

interface IPMarket {
  function readTokens() external view returns (address _SY, address _PT, address _YT);

  function readState(address router) external view returns (MarketState memory market);

  function expiry() external view returns (uint256);
}
