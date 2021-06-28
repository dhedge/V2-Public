Extends BaseUpgradeabilityProxy with an initializer for initializing
implementation and init data.

# Functions:
- [`initialize(address _factory, bytes _data, uint8 _proxyType)`](#InitializableUpgradeabilityProxy-initialize-address-bytes-uint8-)


# Function `initialize(address _factory, bytes _data, uint8 _proxyType)` {#InitializableUpgradeabilityProxy-initialize-address-bytes-uint8-}
Contract initializer.

## Parameters:
- `_factory`: Address of the factory containing the implementation.

- `_data`: Data to send as msg.data to the implementation to initialize the proxied contract.
It should include the signature and the parameters of the function to be called, as described in
https://solidity.readthedocs.io/en/v0.4.24/abi-spec.html#function-selector-and-argument-encoding.
This parameter is optional, if no data is given the initialization call to proxied contract will be skipped.

