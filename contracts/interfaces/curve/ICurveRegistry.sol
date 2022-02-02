// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface ICurveRegistry {
  // solhint-disable-next-line func-name-mixedcase
  function get_address(uint256 i) external view returns (address);
}
