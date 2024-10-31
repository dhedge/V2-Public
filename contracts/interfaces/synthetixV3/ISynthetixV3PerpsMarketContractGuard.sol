// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface ISynthetixV3PerpsMarketContractGuard {
  function getAccountNftTokenId(address _poolLogic, address _to) external view returns (uint128 tokenId);
}
