// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

contract FakeERC20ForAssetsConfusion {
  address public immutable oneInchV6ContractGuard;

  mapping(address => uint256) public balances;

  constructor(address _oneInchV6ContractGuard) {
    oneInchV6ContractGuard = _oneInchV6ContractGuard;
  }

  function transfer(address to, uint256 value) public returns (bool) {
    balances[to] += value;
    return true;
  }

  function transferFrom(address, address to, uint256 value) public returns (bool) {
    balances[to] += value;
    return true;
  }

  function balanceOf(address account) public view returns (uint256) {
    if (msg.sender == oneInchV6ContractGuard) return gasleft();
    return balances[account];
  }
}
