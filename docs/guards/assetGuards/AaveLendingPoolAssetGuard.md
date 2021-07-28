

# Functions:
- [`constructor(address _aaveProtocolDataProvider)`](#AaveLendingPoolAssetGuard-constructor-address-)
- [`getBalance(address pool, address)`](#AaveLendingPoolAssetGuard-getBalance-address-address-)
- [`getDecimals(address)`](#AaveLendingPoolAssetGuard-getDecimals-address-)
- [`withdrawProcessing(address pool, address, uint256 portion, address to)`](#AaveLendingPoolAssetGuard-withdrawProcessing-address-address-uint256-address-)
- [`flashloanProcessing(address pool, uint256 portion, address[] repayAssets, uint256[] repayAmounts, uint256[] premiums, uint256[] interestRateModes)`](#AaveLendingPoolAssetGuard-flashloanProcessing-address-uint256-address---uint256---uint256---uint256---)



# Function `constructor(address _aaveProtocolDataProvider)` {#AaveLendingPoolAssetGuard-constructor-address-}
No description




# Function `getBalance(address pool, address) → uint256 balance` {#AaveLendingPoolAssetGuard-getBalance-address-address-}
Returns the pool position of Aave lending pool


## Parameters:
- `pool`: The pool logic address


## Return Values:
- balance The total balance of the pool


# Function `getDecimals(address) → uint256 decimals` {#AaveLendingPoolAssetGuard-getDecimals-address-}
Returns decimal of the Aave lending pool asset





# Function `withdrawProcessing(address pool, address, uint256 portion, address to) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#AaveLendingPoolAssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing tokens



## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the withdrawal transaction in PoolLogic












# Function `flashloanProcessing(address pool, uint256 portion, address[] repayAssets, uint256[] repayAmounts, uint256[] premiums, uint256[] interestRateModes) → struct IAssetGuard.MultiTransaction[] transactions` {#AaveLendingPoolAssetGuard-flashloanProcessing-address-uint256-address---uint256---uint256---uint256---}
process flash loan and return the transactions for execution


## Parameters:
- `pool`: the PoolLogic address

- `portion`: the portion of assets to be withdrawn

- `repayAssets`: Array of assets to be repaid

- `repayAmounts`: Array of amounts to be repaid

- `premiums`: Array of premiums to be paid for flash loan

- `interestRateModes`: Array of interest rate modes of the debts


## Return Values:
- transactions Array of transactions to be executed








