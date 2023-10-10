// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title ERC721 extension with helper functions that allow the enumeration of NFT tokens.
 */
interface IERC721Enumerable is IERC721 {
  /**
   * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
   * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
   *
   * Requirements:
   * - `owner` must be a valid address
   * - `index` must be less than the balance of the tokens for the owner
   */
  function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
}
