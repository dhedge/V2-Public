

# Functions:
- [`constructor(address _susdProxy)`](#SynthRedeemerContractGuard-constructor-address-)
- [`txGuard(address _poolManagerLogic, address, bytes _data)`](#SynthRedeemerContractGuard-txGuard-address-address-bytes-)



# Function `constructor(address _susdProxy)` {#SynthRedeemerContractGuard-constructor-address-}
No description




# Function `txGuard(address _poolManagerLogic, address, bytes _data) → uint16 txType, bool isPublic` {#SynthRedeemerContractGuard-txGuard-address-address-bytes-}
Transaction guard for Synthetix SynthRedeemer


## Parameters:
- `_poolManagerLogic`: The pool manager logic address

- `_data`: Transaction call data attempt


## Return Values:
- txType Transaction type described in PoolLogic

- isPublic If the transaction is public or private


