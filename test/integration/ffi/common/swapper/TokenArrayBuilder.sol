// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Token} from "./SwapperTestSetup.sol";

// Adapted from <https://github.com/Uniswap/permit2/blob/cc56ad0f3439c502c246fc5cfcc3db92bb8b7219/test/utils/AddressBuilder.sol#L4>
library TokenArrayBuilder {
  function fill(uint256 length, Token memory token) external pure returns (Token[] memory tokens) {
    tokens = new Token[](length);
    for (uint256 i = 0; i < length; ++i) {
      tokens[i] = token;
    }
  }

  function push(Token[] calldata tokens, Token memory token) external pure returns (Token[] memory newTokens) {
    newTokens = new Token[](tokens.length + 1);
    for (uint256 i = 0; i < tokens.length; ++i) {
      newTokens[i] = tokens[i];
    }
    newTokens[tokens.length] = token;
  }
}
