// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

interface IOndoSanityCheckOracle {
  struct PriceData {
    uint256 price; // 18 decimals, already includes sValue
    uint64 lastUpdated;
    uint32 maxTimeDelay;
    uint16 allowedDeviationBps;
  }

  function prices(address asset) external view returns (PriceData memory);
}
