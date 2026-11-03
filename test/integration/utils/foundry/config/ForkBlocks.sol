// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

/// @dev Rolling fork block per chain for the integration tests, all taken at the same instant about one
///      hour behind head. Refresh with `pnpm test-freshness:repin`; the pre-commit hook warns once they are
///      older than 30 days. A suite that must stay on a specific block keeps its own literal.
library ForkBlocks {
  // Pinned at 1790225053 (2026-09-24)
  uint256 internal constant ARBITRUM = 508337839;
  uint256 internal constant BASE = 51717853;
  uint256 internal constant ETHEREUM = 26045022;
  uint256 internal constant OPTIMISM = 157313138;
  uint256 internal constant POLYGON = 94346613;
  uint256 internal constant HYPEREVM = 46734754;
}
