// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable
pragma solidity 0.7.6;

import {IERC20Extended} from "../IERC20Extended.sol";

interface IPYieldToken is IERC20Extended {
  function SY() external view returns (address);

  function PT() external view returns (address);

  function expiry() external view returns (uint256);

  function isExpired() external view returns (bool);
}
