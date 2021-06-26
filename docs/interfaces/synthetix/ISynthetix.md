## `ISynthetix`






### `exchange(bytes32 sourceCurrencyKey, uint256 sourceAmount, bytes32 destinationCurrencyKey) → uint256 amountReceived` (external)





### `exchangeWithTracking(bytes32 sourceCurrencyKey, uint256 sourceAmount, bytes32 destinationCurrencyKey, address originator, bytes32 trackingCode) → uint256 amountReceived` (external)





### `synths(bytes32 key) → address synthTokenAddress` (external)





### `synthsByAddress(address asset) → bytes32 key` (external)





### `settle(bytes32 currencyKey) → uint256 reclaimed, uint256 refunded, uint256 numEntriesSettled` (external)






