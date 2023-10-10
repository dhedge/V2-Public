

# Functions:
- [`constructor(address _nftTracker)`](#MaiVaultContractGuard-constructor-address-)
- [`getNftType(address to)`](#MaiVaultContractGuard-getNftType-address-)
- [`afterTxGuard(address _poolManagerLogic, address to, bytes data)`](#MaiVaultContractGuard-afterTxGuard-address-address-bytes-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#MaiVaultContractGuard-txGuard-address-address-bytes-)
- [`getNftIds(address pool, address maiVault)`](#MaiVaultContractGuard-getNftIds-address-address-)

# Events:
- [`MaiEvent(address fundAddress, address maiVault)`](#MaiVaultContractGuard-MaiEvent-address-address-)


# Function `constructor(address _nftTracker)` {#MaiVaultContractGuard-constructor-address-}
No description




# Function `getNftType(address to) → bytes32` {#MaiVaultContractGuard-getNftType-address-}
We use the vaultAddress as the NFT_Type


## Parameters:
- `to`: // the mai vault


## Return Values:
- nftType the byte key used to store data


# Function `afterTxGuard(address _poolManagerLogic, address to, bytes data)` {#MaiVaultContractGuard-afterTxGuard-address-address-bytes-}
This function is called after execution transaction (used to track transactions)


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: the mai vault

- `data`: the transaction data



# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool` {#MaiVaultContractGuard-txGuard-address-address-bytes-}
Transaction guard for a Synthetix Mai Market


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: the mai vault

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data.

- isPublic if the transaction is public or private


# Function `getNftIds(address pool, address maiVault) → uint256[]` {#MaiVaultContractGuard-getNftIds-address-address-}
We use the vaultAddress as the NFT_Type


## Parameters:
- `pool`: // the dhedge pool

- `maiVault`: // the mai vault


## Return Values:
- nftIds the ids in storage for this vault


