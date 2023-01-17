// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IExchanger {
  function settle(address from, bytes32 currencyKey)
    external
    returns (
      uint256 reclaimed,
      uint256 refunded,
      uint256 numEntries
    );

  function maxSecsLeftInWaitingPeriod(address account, bytes32 currencyKey) external view returns (uint256);

  function getAmountsForExchange(
    uint256 sourceAmount,
    bytes32 sourceCurrencyKey,
    bytes32 destinationCurrencyKey
  )
    external
    view
    returns (
      uint256 amountReceived,
      uint256 fee,
      uint256 exchangeFeeRate
    );
}
