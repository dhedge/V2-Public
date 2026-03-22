// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IPullTokenWrapper {
  function token() external view returns (address);

  function underlying() external view returns (address);
}
