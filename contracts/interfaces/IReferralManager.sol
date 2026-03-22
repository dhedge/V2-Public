// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface IReferralManager {
  function getReferralShare(address _vault, address _manager) external view returns (uint256 shareNumerator);
}
