// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface INftTrackerConsumerGuard {
  function getOwnedTokenIds(address _poolLogic) external view returns (uint256[] memory);

  function isValidOwnedTokenId(address _poolLogic, uint256 _tokenId) external view returns (bool);
}
