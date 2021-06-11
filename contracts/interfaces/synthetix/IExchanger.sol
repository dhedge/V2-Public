// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IExchanger {
  function settle(address from, bytes32 currencyKey)
    external
    returns (
      uint256 reclaimed,
      uint256 refunded,
      uint256 numEntries
    );

  function maxSecsLeftInWaitingPeriod(address account, bytes32 currencyKey) external view returns (uint256);
}
