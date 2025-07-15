// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface HasLogic {
  function getLogic(uint8 _proxyType) external view returns (address);
}
