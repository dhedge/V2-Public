// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface ISynthetix {
  function exchange(
    bytes32 sourceCurrencyKey,
    uint256 sourceAmount,
    bytes32 destinationCurrencyKey
  ) external returns (uint256 amountReceived);

  function exchangeWithTracking(
    bytes32 sourceCurrencyKey,
    uint256 sourceAmount,
    bytes32 destinationCurrencyKey,
    address originator,
    bytes32 trackingCode
  ) external returns (uint256 amountReceived);

  function synths(bytes32 key) external view returns (address synthTokenAddress);

  function synthsByAddress(address asset) external view returns (bytes32 key);

  function settle(bytes32 currencyKey)
    external
    returns (
      uint256 reclaimed,
      uint256 refunded,
      uint256 numEntriesSettled
    );
}
