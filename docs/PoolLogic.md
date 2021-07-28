Logic implementation for pool

# Functions:
- [`initialize(address _factory, bool _privatePool, string _fundName, string _fundSymbol)`](#PoolLogic-initialize-address-bool-string-string-)
- [`setPoolPrivate(bool _privatePool)`](#PoolLogic-setPoolPrivate-bool-)
- [`deposit(address _asset, uint256 _amount)`](#PoolLogic-deposit-address-uint256-)
- [`withdraw(uint256 _fundTokenAmount)`](#PoolLogic-withdraw-uint256-)
- [`execTransaction(address to, bytes data)`](#PoolLogic-execTransaction-address-bytes-)
- [`getFundSummary()`](#PoolLogic-getFundSummary--)
- [`tokenPrice()`](#PoolLogic-tokenPrice--)
- [`availableManagerFee()`](#PoolLogic-availableManagerFee--)
- [`mintManagerFee()`](#PoolLogic-mintManagerFee--)
- [`getExitCooldown()`](#PoolLogic-getExitCooldown--)
- [`getExitRemainingCooldown(address sender)`](#PoolLogic-getExitRemainingCooldown-address-)
- [`setPoolManagerLogic(address _poolManagerLogic)`](#PoolLogic-setPoolManagerLogic-address-)
- [`managerName()`](#PoolLogic-managerName--)
- [`isMemberAllowed(address member)`](#PoolLogic-isMemberAllowed-address-)
- [`executeOperation(address[] assets, uint256[] amounts, uint256[] premiums, address originator, bytes params)`](#PoolLogic-executeOperation-address---uint256---uint256---address-bytes-)

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


# Function `withdraw(uint256 _fundTokenAmount)` {#PoolLogic-withdraw-uint256-}
Withdraw assets based on the fund token amount


## Parameters:
- `_fundTokenAmount`: the fund token amount





# Function `execTransaction(address to, bytes data) → bool success` {#PoolLogic-execTransaction-address-bytes-}
Function to let pool talk to other protocol


## Parameters:
- `to`: The destination address for pool to talk to

- `data`: The data that going to send in the transaction


## Return Values:
- success A boolean for success or fail transaction


# Function `getFundSummary() → string, uint256, uint256, address, string, uint256, bool, uint256, uint256` {#PoolLogic-getFundSummary--}
Get fund summary of the pool



## Return Values:
- Name of the pool

- Total supply of the pool

- Total fund value of the pool

- Address of the pool manager

- Name of the pool manager

- Time of the pool creation

- True if the pool is private, false otherwise

- Numberator of the manager fee

- Denominator of the manager fee


# Function `tokenPrice() → uint256 price` {#PoolLogic-tokenPrice--}
Get price of the asset


## Parameters:
- `price`: A price of the asset





# Function `availableManagerFee() → uint256 fee` {#PoolLogic-availableManagerFee--}
Get available manager fee of the pool



## Return Values:
- fee available manager fee of the pool




# Function `mintManagerFee()` {#PoolLogic-mintManagerFee--}
Mint the manager fee of the pool






# Function `getExitCooldown() → uint256 exitCooldown` {#PoolLogic-getExitCooldown--}
Get exit cooldown of the pool



## Return Values:
- exitCooldown The exit cooldown of the pool


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
Return true if member is allowed, false otherwise




# Function `executeOperation(address[] assets, uint256[] amounts, uint256[] premiums, address originator, bytes params) → bool success` {#PoolLogic-executeOperation-address---uint256---uint256---address-bytes-}
execute function of aave flash loan


## Parameters:
- `assets`: the loaned assets

- `amounts`: the loaned amounts per each asset

- `premiums`: the additional owed amount per each asset

- `originator`: the origin caller address of the flash loan

- `params`: Variadic packed params to pass to the receiver as extra information



