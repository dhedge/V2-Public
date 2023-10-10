Logic implementation for pool

# Functions:
- [`initialize(address _factory, bool _privatePool, string _fundName, string _fundSymbol)`](#PoolLogic-initialize-address-bool-string-string-)
- [`setPoolPrivate(bool _privatePool)`](#PoolLogic-setPoolPrivate-bool-)
- [`deposit(address _asset, uint256 _amount)`](#PoolLogic-deposit-address-uint256-)
- [`depositFor(address _recipient, address _asset, uint256 _amount)`](#PoolLogic-depositFor-address-address-uint256-)
- [`depositForWithCustomCooldown(address _recipient, address _asset, uint256 _amount, uint256 _cooldown)`](#PoolLogic-depositForWithCustomCooldown-address-address-uint256-uint256-)
- [`withdraw(uint256 _fundTokenAmount)`](#PoolLogic-withdraw-uint256-)
- [`withdrawTo(address _recipient, uint256 _fundTokenAmount)`](#PoolLogic-withdrawTo-address-uint256-)
- [`execTransaction(address to, bytes data)`](#PoolLogic-execTransaction-address-bytes-)
- [`execTransactions(struct PoolLogic.TxToExecute[] txs)`](#PoolLogic-execTransactions-struct-PoolLogic-TxToExecute---)
- [`getFundSummary()`](#PoolLogic-getFundSummary--)
- [`tokenPrice()`](#PoolLogic-tokenPrice--)
- [`tokenPriceWithoutManagerFee()`](#PoolLogic-tokenPriceWithoutManagerFee--)
- [`availableManagerFee()`](#PoolLogic-availableManagerFee--)
- [`availableManagerFeeAndTotalFundValue()`](#PoolLogic-availableManagerFeeAndTotalFundValue--)
- [`mintManagerFee()`](#PoolLogic-mintManagerFee--)
- [`calculateCooldown(uint256 currentBalance, uint256 liquidityMinted, uint256 newCooldown, uint256 lastCooldown, uint256 lastDepositTime, uint256 blockTimestamp)`](#PoolLogic-calculateCooldown-uint256-uint256-uint256-uint256-uint256-uint256-)
- [`getExitRemainingCooldown(address sender)`](#PoolLogic-getExitRemainingCooldown-address-)
- [`setPoolManagerLogic(address _poolManagerLogic)`](#PoolLogic-setPoolManagerLogic-address-)
- [`managerName()`](#PoolLogic-managerName--)
- [`isMemberAllowed(address member)`](#PoolLogic-isMemberAllowed-address-)
- [`executeOperation(address[] assets, uint256[] amounts, uint256[] premiums, address originator, bytes params)`](#PoolLogic-executeOperation-address---uint256---uint256---address-bytes-)
- [`onERC721Received(address operator, address from, uint256 tokenId, bytes data)`](#PoolLogic-onERC721Received-address-address-uint256-bytes-)

# Events:
- [`Deposit(address fundAddress, address investor, address assetDeposited, uint256 amountDeposited, uint256 valueDeposited, uint256 fundTokensReceived, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, uint256 time)`](#PoolLogic-Deposit-address-address-address-uint256-uint256-uint256-uint256-uint256-uint256-uint256-)
- [`Withdrawal(address fundAddress, address investor, uint256 valueWithdrawn, uint256 fundTokensWithdrawn, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, struct PoolLogic.WithdrawnAsset[] withdrawnAssets, uint256 time)`](#PoolLogic-Withdrawal-address-address-uint256-uint256-uint256-uint256-uint256-struct-PoolLogic-WithdrawnAsset---uint256-)
- [`TransactionExecuted(address pool, address manager, uint16 transactionType, uint256 time)`](#PoolLogic-TransactionExecuted-address-address-uint16-uint256-)
- [`PoolPrivacyUpdated(bool isPoolPrivate)`](#PoolLogic-PoolPrivacyUpdated-bool-)
- [`ManagerFeeMinted(address pool, address manager, uint256 available, uint256 daoFee, uint256 managerFee, uint256 tokenPriceAtLastFeeMint)`](#PoolLogic-ManagerFeeMinted-address-address-uint256-uint256-uint256-uint256-)
- [`PoolManagerLogicSet(address poolManagerLogic, address from)`](#PoolLogic-PoolManagerLogicSet-address-address-)


# Function `initialize(address _factory, bool _privatePool, string _fundName, string _fundSymbol)` {#PoolLogic-initialize-address-bool-string-string-}
Initialize the pool


## Parameters:
- `_factory`: address of the factory

- `_privatePool`: true if the pool is private, false otherwise

- `_fundName`: name of the fund

- `_fundSymbol`: symbol of the fund





# Function `setPoolPrivate(bool _privatePool)` {#PoolLogic-setPoolPrivate-bool-}
Set the pool privacy


## Parameters:
- `_privatePool`: true if the pool is private, false otherwise





# Function `deposit(address _asset, uint256 _amount) → uint256 liquidityMinted` {#PoolLogic-deposit-address-uint256-}
Deposit funds into the pool


## Parameters:
- `_asset`: Address of the token

- `_amount`: Amount of tokens to deposit


## Return Values:
- liquidityMinted Amount of liquidity minted


# Function `depositFor(address _recipient, address _asset, uint256 _amount) → uint256 liquidityMinted` {#PoolLogic-depositFor-address-address-uint256-}
No description




# Function `depositForWithCustomCooldown(address _recipient, address _asset, uint256 _amount, uint256 _cooldown) → uint256 liquidityMinted` {#PoolLogic-depositForWithCustomCooldown-address-address-uint256-uint256-}
No description




# Function `withdraw(uint256 _fundTokenAmount)` {#PoolLogic-withdraw-uint256-}
No description




# Function `withdrawTo(address _recipient, uint256 _fundTokenAmount)` {#PoolLogic-withdrawTo-address-uint256-}
Withdraw assets based on the fund token amount


## Parameters:
- `_fundTokenAmount`: the fund token amount





# Function `execTransaction(address to, bytes data) → bool success` {#PoolLogic-execTransaction-address-bytes-}
Exposed function to let pool talk to other protocol


## Parameters:
- `to`: The destination address for pool to talk to

- `data`: The data that going to send in the transaction


## Return Values:
- success A boolean for success or fail transaction


# Function `execTransactions(struct PoolLogic.TxToExecute[] txs) → bool success` {#PoolLogic-execTransactions-struct-PoolLogic-TxToExecute---}
Exposed function to let pool talk to other protocol


## Parameters:
- `txs`: Array of structs, each consisting of address and data


## Return Values:
- success A boolean indicating if all transactions succeeded


# Function `getFundSummary() → struct PoolLogic.FundSummary` {#PoolLogic-getFundSummary--}
Get fund summary of the pool



## Return Values:
- Fund summary of the pool


# Function `tokenPrice() → uint256 price` {#PoolLogic-tokenPrice--}
Get price of the asset adjusted for any unminted manager fees


## Parameters:
- `price`: A price of the asset



# Function `tokenPriceWithoutManagerFee() → uint256 price` {#PoolLogic-tokenPriceWithoutManagerFee--}
No description






# Function `availableManagerFee() → uint256 fee` {#PoolLogic-availableManagerFee--}
Get available manager fee of the pool



## Return Values:
- fee available manager fee of the pool


# Function `availableManagerFeeAndTotalFundValue() → uint256 fee, uint256 fundValue` {#PoolLogic-availableManagerFeeAndTotalFundValue--}
Get available manager fee of the pool and totalFundValue



## Return Values:
- fee available manager fee of the pool




# Function `mintManagerFee()` {#PoolLogic-mintManagerFee--}
Mint the manager fee of the pool






# Function `calculateCooldown(uint256 currentBalance, uint256 liquidityMinted, uint256 newCooldown, uint256 lastCooldown, uint256 lastDepositTime, uint256 blockTimestamp) → uint256 cooldown` {#PoolLogic-calculateCooldown-uint256-uint256-uint256-uint256-uint256-uint256-}
Calculate lockup cooldown applied to the investor after pool deposit


## Parameters:
- `currentBalance`: Investor's current pool tokens balance

- `liquidityMinted`: Liquidity to be minted to investor after pool deposit

- `newCooldown`: New cooldown lockup time

- `lastCooldown`: Last cooldown lockup time applied to investor

- `lastDepositTime`: Timestamp when last pool deposit happened

- `blockTimestamp`: Timestamp of a block


## Return Values:
- cooldown New lockup cooldown to be applied to investor address


# Function `getExitRemainingCooldown(address sender) → uint256 remaining` {#PoolLogic-getExitRemainingCooldown-address-}
Get exit remaining time of the pool



## Return Values:
- remaining The remaining exit time of the pool


# Function `setPoolManagerLogic(address _poolManagerLogic) → bool` {#PoolLogic-setPoolManagerLogic-address-}
Set address for pool manager logic








# Function `managerName() → string _managerName` {#PoolLogic-managerName--}
Get name of the manager



## Return Values:
- _managerName The name of the manager


# Function `isMemberAllowed(address member) → bool` {#PoolLogic-isMemberAllowed-address-}
Return boolean if the address is a member of the list


## Parameters:
- `member`: The address of the member


## Return Values:
- True if the address is a member of the list, false otherwise


# Function `executeOperation(address[] assets, uint256[] amounts, uint256[] premiums, address originator, bytes params) → bool success` {#PoolLogic-executeOperation-address---uint256---uint256---address-bytes-}
execute function of aave flash loan


## Parameters:
- `assets`: the loaned assets

- `amounts`: the loaned amounts per each asset

- `premiums`: the additional owed amount per each asset

- `originator`: the origin caller address of the flash loan

- `params`: Variadic packed params to pass to the receiver as extra information





# Function `onERC721Received(address operator, address from, uint256 tokenId, bytes data) → bytes4 magicSelector` {#PoolLogic-onERC721Received-address-address-uint256-bytes-}
Support safeTransfers from ERC721 asset contracts





