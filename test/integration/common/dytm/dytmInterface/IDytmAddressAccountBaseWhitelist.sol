// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
interface IDytmAddressAccountBaseWhitelist {
  function setAddressWhitelist(address accountOwner, bool allowed) external;
}
