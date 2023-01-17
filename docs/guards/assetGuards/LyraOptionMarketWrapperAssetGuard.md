

# Functions:
- [`constructor(contract DhedgeOptionMarketWrapperForLyra _dhedgeLyraWrapper)`](#LyraOptionMarketWrapperAssetGuard-constructor-contract-DhedgeOptionMarketWrapperForLyra-)
- [`marketViewer()`](#LyraOptionMarketWrapperAssetGuard-marketViewer--)
- [`getGWAVCallPrice(address optionMarket, uint256 strikeId)`](#LyraOptionMarketWrapperAssetGuard-getGWAVCallPrice-address-uint256-)
- [`getGWAVPutPrice(address optionMarket, uint256 strikeId)`](#LyraOptionMarketWrapperAssetGuard-getGWAVPutPrice-address-uint256-)
- [`assertNoGWAVDivergence(uint256 price1, uint256 price2)`](#LyraOptionMarketWrapperAssetGuard-assertNoGWAVDivergence-uint256-uint256-)
- [`withdrawProcessing(address pool, address asset, uint256 portion, address to)`](#LyraOptionMarketWrapperAssetGuard-withdrawProcessing-address-address-uint256-address-)
- [`getDecimals(address)`](#LyraOptionMarketWrapperAssetGuard-getDecimals-address-)
- [`getBalance(address pool, address asset)`](#LyraOptionMarketWrapperAssetGuard-getBalance-address-address-)



# Function `constructor(contract DhedgeOptionMarketWrapperForLyra _dhedgeLyraWrapper)` {#LyraOptionMarketWrapperAssetGuard-constructor-contract-DhedgeOptionMarketWrapperForLyra-}
No description




# Function `marketViewer() → contract IOptionMarketViewer` {#LyraOptionMarketWrapperAssetGuard-marketViewer--}
No description




# Function `getGWAVCallPrice(address optionMarket, uint256 strikeId) → uint256 callPrice` {#LyraOptionMarketWrapperAssetGuard-getGWAVCallPrice-address-uint256-}
No description




# Function `getGWAVPutPrice(address optionMarket, uint256 strikeId) → uint256 putPrice` {#LyraOptionMarketWrapperAssetGuard-getGWAVPutPrice-address-uint256-}
No description




# Function `assertNoGWAVDivergence(uint256 price1, uint256 price2)` {#LyraOptionMarketWrapperAssetGuard-assertNoGWAVDivergence-uint256-uint256-}
No description




# Function `withdrawProcessing(address pool, address asset, uint256 portion, address to) → address withdrawAsset, uint256 withdrawBalance, struct IAssetGuard.MultiTransaction[] transactions` {#LyraOptionMarketWrapperAssetGuard-withdrawProcessing-address-address-uint256-address-}
Creates transaction data for withdrawing staked tokens


## Parameters:
- `pool`: Pool address

- `asset`: lyra option market wrapper contract address

- `portion`: The fraction of total staked asset to withdraw


## Return Values:
- withdrawAsset and

- withdrawBalance are used to withdraw portion of asset balance to investor

- transactions is used to execute the staked withdrawal transaction in PoolLogic


# Function `getDecimals(address) → uint256 decimals` {#LyraOptionMarketWrapperAssetGuard-getDecimals-address-}
Returns decimal of the Lyra option market asset





# Function `getBalance(address pool, address asset) → uint256 balance` {#LyraOptionMarketWrapperAssetGuard-getBalance-address-address-}
Returns the balance of the managed asset


## Parameters:
- `pool`: address of the pool

- `asset`: lyra option market wrapper contract address


## Return Values:
- balance The asset balance of given pool


