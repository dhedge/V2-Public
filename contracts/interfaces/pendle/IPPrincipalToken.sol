// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable
pragma solidity 0.7.6;

import {IERC20Extended} from "../IERC20Extended.sol";

interface IPPrincipalToken is IERC20Extended {
  function SY() external view returns (address);

  function YT() external view returns (address);

  function factory() external view returns (address);

  function expiry() external view returns (uint256);

  function isExpired() external view returns (bool);
}
