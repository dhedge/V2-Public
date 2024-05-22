// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {AddressLib} from "./AddressLib.sol";

/**
 * @dev Taken from 1inch AggregationRouterV6 contract, rest of the library can be found there.
 */
library ProtocolLib {
  using AddressLib for uint256;

  enum Protocol {
    UniswapV2,
    UniswapV3,
    Curve
  }

  uint256 private constant _PROTOCOL_OFFSET = 253;
  uint256 private constant _WETH_UNWRAP_FLAG = 1 << 252;

  function protocol(uint256 self) internal pure returns (Protocol) {
    // there is no need to mask because protocol is stored in the highest 3 bits
    return Protocol((self >> _PROTOCOL_OFFSET));
  }

  function shouldUnwrapWeth(uint256 self) internal pure returns (bool) {
    return self.getFlag(_WETH_UNWRAP_FLAG);
  }
}
