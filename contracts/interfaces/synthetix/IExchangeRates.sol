// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IExchangeRates {
  function effectiveValue(
    bytes32 sourceCurrencyKey,
    uint256 sourceAmount,
    bytes32 destinationCurrencyKey
  ) external view returns (uint256);

  function rateForCurrency(bytes32 currencyKey) external view returns (uint256);
}
