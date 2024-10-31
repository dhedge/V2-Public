// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {IERC20Extended} from "../interfaces/IERC20Extended.sol";

library PrecisionHelper {
  function getPrecisionForConversion(address _token) internal view returns (uint256 precision) {
    precision = 10 ** (18 - (IERC20Extended(_token).decimals()));
  }
}
