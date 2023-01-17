

# Functions:
- [`initialize(address _factory, bool _privatePool, string _fundName, string _fundSymbol)`](#PoolLogicV24-initialize-address-bool-string-string-)
- [`setPoolPrivate(bool _privatePool)`](#PoolLogicV24-setPoolPrivate-bool-)
- [`deposit(address _asset, uint256 _amount)`](#PoolLogicV24-deposit-address-uint256-)
- [`withdraw(uint256 _fundTokenAmount)`](#PoolLogicV24-withdraw-uint256-)
- [`execTransaction(address to, bytes data)`](#PoolLogicV24-execTransaction-address-bytes-)
- [`getFundSummary()`](#PoolLogicV24-getFundSummary--)
- [`tokenPrice()`](#PoolLogicV24-tokenPrice--)
- [`availableManagerFee()`](#PoolLogicV24-availableManagerFee--)
- [`mintManagerFee()`](#PoolLogicV24-mintManagerFee--)
- [`getExitCooldown()`](#PoolLogicV24-getExitCooldown--)
- [`getExitRemainingCooldown(address sender)`](#PoolLogicV24-getExitRemainingCooldown-address-)
- [`setPoolManagerLogic(address _poolManagerLogic)`](#PoolLogicV24-setPoolManagerLogic-address-)
- [`managerName()`](#PoolLogicV24-managerName--)
- [`isMemberAllowed(address member)`](#PoolLogicV24-isMemberAllowed-address-)
- [`executeOperation(address[] assets, uint256[] amounts, uint256[] premiums, address originator, bytes params)`](#PoolLogicV24-executeOperation-address---uint256---uint256---address-bytes-)

# Events:
- [`Deposit(address fundAddress, address investor, address assetDeposited, uint256 amountDeposited, uint256 valueDeposited, uint256 fundTokensReceived, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, uint256 time)`](#PoolLogicV24-Deposit-address-address-address-uint256-uint256-uint256-uint256-uint256-uint256-uint256-)
- [`Withdrawal(address fundAddress, address investor, uint256 valueWithdrawn, uint256 fundTokensWithdrawn, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, struct PoolLogicV24.WithdrawnAsset[] withdrawnAssets, uint256 time)`](#PoolLogicV24-Withdrawal-address-address-uint256-uint256-uint256-uint256-uint256-struct-PoolLogicV24-WithdrawnAsset---uint256-)
- [`TransactionExecuted(address pool, address manager, uint16 transactionType, uint256 time)`](#PoolLogicV24-TransactionExecuted-address-address-uint16-uint256-)
- [`PoolPrivacyUpdated(bool isPoolPrivate)`](#PoolLogicV24-PoolPrivacyUpdated-bool-)
- [`ManagerFeeMinted(address pool, address manager, uint256 available, uint256 daoFee, uint256 managerFee, uint256 tokenPriceAtLastFeeMint)`](#PoolLogicV24-ManagerFeeMinted-address-address-uint256-uint256-uint256-uint256-)
- [`PoolManagerLogicSet(address poolManagerLogic, address from)`](#PoolLogicV24-PoolManagerLogicSet-address-address-)


# Function `initialize(address _factory, bool _privatePool, string _fundName, string _fundSymbol)` {#PoolLogicV24-initialize-address-bool-string-string-}
No description






# Function `setPoolPrivate(bool _privatePool)` {#PoolLogicV24-setPoolPrivate-bool-}
No description






# Function `deposit(address _asset, uint256 _amount) → uint256` {#PoolLogicV24-deposit-address-uint256-}
No description




# Function `withdraw(uint256 _fundTokenAmount)` {#PoolLogicV24-withdraw-uint256-}
Withdraw assets based on the fund token amount


## Parameters:
- `_fundTokenAmount`: the fund token amount





# Function `execTransaction(address to, bytes data) → bool success` {#PoolLogicV24-execTransaction-address-bytes-}
Function to let pool talk to other protocol


## Parameters:
- `to`: The destination address for pool to talk to

- `data`: The data that going to send in the transaction


## Return Values:
- success A boolean for success or fail transaction


# Function `getFundSummary() → string, uint256, uint256, address, string, uint256, bool, uint256, uint256` {#PoolLogicV24-getFundSummary--}
No description




# Function `tokenPrice() → uint256` {#PoolLogicV24-tokenPrice--}
No description






# Function `availableManagerFee() → uint256` {#PoolLogicV24-availableManagerFee--}
No description






# Function `mintManagerFee()` {#PoolLogicV24-mintManagerFee--}
No description






# Function `getExitCooldown() → uint256` {#PoolLogicV24-getExitCooldown--}
No description




# Function `getExitRemainingCooldown(address sender) → uint256` {#PoolLogicV24-getExitRemainingCooldown-address-}
No description




# Function `setPoolManagerLogic(address _poolManagerLogic) → bool` {#PoolLogicV24-setPoolManagerLogic-address-}
No description








# Function `managerName() → string` {#PoolLogicV24-managerName--}
No description




# Function `isMemberAllowed(address member) → bool` {#PoolLogicV24-isMemberAllowed-address-}
No description




# Function `executeOperation(address[] assets, uint256[] amounts, uint256[] premiums, address originator, bytes params) → bool success` {#PoolLogicV24-executeOperation-address---uint256---uint256---address-bytes-}
execute function of aave flash loan


## Parameters:
- `assets`: the loaned assets

- `amounts`: the loaned amounts per each asset

- `premiums`: the additional owed amount per each asset

- `originator`: the origin caller address of the flash loan

- `params`: Variadic packed params to pass to the receiver as extra information



