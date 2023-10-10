

# Functions:
- [`withdrawProcessing(address pool, address asset, uint256 portion, address withdrawerAddress)`](#MaiVaultWithdrawProcessing-withdrawProcessing-address-address-uint256-address-)
- [`processWithdrawAndReturn(address vault, uint256 vaultId, uint256 portion, address withdrawer)`](#MaiVaultWithdrawProcessing-processWithdrawAndReturn-address-uint256-uint256-address-)
- [`executeOperation(address, uint256 usdcAmount, uint256 premium, address initiator, bytes params)`](#MaiVaultWithdrawProcessing-executeOperation-address-uint256-uint256-address-bytes-)





# Function `withdrawProcessing(address pool, address asset, uint256 portion, address withdrawerAddress) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#MaiVaultWithdrawProcessing-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for reducing a futures position by the portion


## Parameters:
- `pool`: Pool address

- `asset`: MaiVault

- `portion`: The fraction of total future asset to withdraw

- `withdrawerAddress`: Who the withdrawer is


## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the reduction of the futures position in PoolLogic


# Function `processWithdrawAndReturn(address vault, uint256 vaultId, uint256 portion, address withdrawer)` {#MaiVaultWithdrawProcessing-processWithdrawAndReturn-address-uint256-uint256-address-}
This function is called upstream by the pool during withdraw processing after it has transferred the vault to this contract


## Parameters:
- `vault`: MaiVault

- `vaultId`: the vault nftID

- `portion`: the withdrawers portion

- `withdrawer`: the withdrawers address



# Function `executeOperation(address, uint256 usdcAmount, uint256 premium, address initiator, bytes params) → bool` {#MaiVaultWithdrawProcessing-executeOperation-address-uint256-uint256-address-bytes-}
execute function of aave flash loan


## Parameters:
- `usdcAmount`: the loaned amount

- `premium`: the additional owed amount

- `initiator`: the origin caller address of the flash loan

- `params`: Variadic packed params to pass to the receiver as extra information



