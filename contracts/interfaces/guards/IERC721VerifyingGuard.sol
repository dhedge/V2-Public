// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IERC721VerifyingGuard {
  function verifyERC721(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata
  ) external returns (bool verified);
}
