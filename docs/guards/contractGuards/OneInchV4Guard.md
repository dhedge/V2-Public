Transaction guard for OneInchV3Router

# Functions:
- [`constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)`](#OneInchV4Guard-constructor-uint256-uint256-)
- [`txGuard(address _poolManagerLogic, address, bytes data)`](#OneInchV4Guard-txGuard-address-address-bytes-)



# Function `constructor(uint256 _slippageLimitNumerator, uint256 _slippageLimitDenominator)` {#OneInchV4Guard-constructor-uint256-uint256-}
No description




# Function `txGuard(address _poolManagerLogic, address, bytes data) → uint16 txType, bool` {#OneInchV4Guard-txGuard-address-address-bytes-}
Transaction guard for OneInchV3


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type

- isPublic if the transaction is public or private


