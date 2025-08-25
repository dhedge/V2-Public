// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

contract MaliciousYT {
  address public legitPT;
  address public pendleContractGuard;

  constructor(address _legitPT, address _pendleContractGuard) {
    legitPT = _legitPT;
    pendleContractGuard = _pendleContractGuard;
  }

  function isExpired() external pure returns (bool) {
    return true;
  }

  function PT() external view returns (address) {
    if (msg.sender == pendleContractGuard) return address(this);

    return legitPT;
  }

  function balanceOf(address) external pure returns (uint256) {
    return 0;
  }

  function SY() external view returns (address) {
    return address(this);
  }

  function redeemPY(address) external pure returns (uint256 amountSyOut) {
    return 1e18;
  }

  function redeem(address, uint256, address, uint256, bool) external pure returns (uint256 amountTokenOut) {
    return 1e18;
  }
}
