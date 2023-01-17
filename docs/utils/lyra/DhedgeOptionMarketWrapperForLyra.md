

# Functions:
- [`constructor(contract ILyraRegistry _lyraRegistry, address _aaveLendingPool)`](#DhedgeOptionMarketWrapperForLyra-constructor-contract-ILyraRegistry-address-)
- [`getOptionMarketViewer()`](#DhedgeOptionMarketWrapperForLyra-getOptionMarketViewer--)
- [`getOptionMarketWrapper()`](#DhedgeOptionMarketWrapperForLyra-getOptionMarketWrapper--)
- [`getSynthetixAdapter()`](#DhedgeOptionMarketWrapperForLyra-getSynthetixAdapter--)
- [`tryCloseAndForceClosePosition(struct LyraOptionMarketWrapperContractGuard.OptionPosition dhedgeStoredPosition, uint256 portion, address recipient)`](#DhedgeOptionMarketWrapperForLyra-tryCloseAndForceClosePosition-struct-LyraOptionMarketWrapperContractGuard-OptionPosition-uint256-address-)
- [`executeOperation(address[] assets, uint256[] amounts, uint256[] premiums, address originator, bytes params)`](#DhedgeOptionMarketWrapperForLyra-executeOperation-address---uint256---uint256---address-bytes-)
- [`getAmountOfQuoteToBorrow(struct IOptionMarketWrapper.OptionPositionParams closeParams)`](#DhedgeOptionMarketWrapperForLyra-getAmountOfQuoteToBorrow-struct-IOptionMarketWrapper-OptionPositionParams-)



# Function `constructor(contract ILyraRegistry _lyraRegistry, address _aaveLendingPool)` {#DhedgeOptionMarketWrapperForLyra-constructor-contract-ILyraRegistry-address-}
No description




# Function `getOptionMarketViewer() → contract IOptionMarketViewer` {#DhedgeOptionMarketWrapperForLyra-getOptionMarketViewer--}
No description




# Function `getOptionMarketWrapper() → contract IOptionMarketWrapper` {#DhedgeOptionMarketWrapperForLyra-getOptionMarketWrapper--}
No description




# Function `getSynthetixAdapter() → contract ISynthetixAdapter` {#DhedgeOptionMarketWrapperForLyra-getSynthetixAdapter--}
No description






# Function `tryCloseAndForceClosePosition(struct LyraOptionMarketWrapperContractGuard.OptionPosition dhedgeStoredPosition, uint256 portion, address recipient)` {#DhedgeOptionMarketWrapperForLyra-tryCloseAndForceClosePosition-struct-LyraOptionMarketWrapperContractGuard-OptionPosition-uint256-address-}
This function is to close lyra option position - called from PoolLogic contract


## Parameters:
- `dhedgeStoredPosition`: the position information dhedge stores

- `portion`: the portion of the withdrawer

- `recipient`: the recipient address for withdrawn funds



# Function `executeOperation(address[] assets, uint256[] amounts, uint256[] premiums, address originator, bytes params) → bool success` {#DhedgeOptionMarketWrapperForLyra-executeOperation-address---uint256---uint256---address-bytes-}
execute function of aave flash loan


## Parameters:
- `assets`: the loaned assets

- `amounts`: the loaned amounts per each asset

- `premiums`: the additional owed amount per each asset

- `originator`: the origin caller address of the flash loan

- `params`: Variadic packed params to pass to the receiver as extra information



# Function `getAmountOfQuoteToBorrow(struct IOptionMarketWrapper.OptionPositionParams closeParams) → uint256` {#DhedgeOptionMarketWrapperForLyra-getAmountOfQuoteToBorrow-struct-IOptionMarketWrapper-OptionPositionParams-}
No description




