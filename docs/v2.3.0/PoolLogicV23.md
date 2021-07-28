

# Functions:
- [`initialize(address _factory, bool _privatePool, string _fundName, string _fundSymbol)`](#PoolLogicV23-initialize-address-bool-string-string-)
- [`setPoolPrivate(bool _privatePool)`](#PoolLogicV23-setPoolPrivate-bool-)
- [`deposit(address _asset, uint256 _amount)`](#PoolLogicV23-deposit-address-uint256-)
- [`withdraw(uint256 _fundTokenAmount)`](#PoolLogicV23-withdraw-uint256-)
- [`execTransaction(address to, bytes data)`](#PoolLogicV23-execTransaction-address-bytes-)
- [`getFundSummary()`](#PoolLogicV23-getFundSummary--)
- [`tokenPrice()`](#PoolLogicV23-tokenPrice--)
- [`availableManagerFee()`](#PoolLogicV23-availableManagerFee--)
- [`mintManagerFee()`](#PoolLogicV23-mintManagerFee--)
- [`getExitCooldown()`](#PoolLogicV23-getExitCooldown--)
- [`getExitRemainingCooldown(address sender)`](#PoolLogicV23-getExitRemainingCooldown-address-)
- [`setPoolManagerLogic(address _poolManagerLogic)`](#PoolLogicV23-setPoolManagerLogic-address-)
- [`managerName()`](#PoolLogicV23-managerName--)
- [`isMemberAllowed(address member)`](#PoolLogicV23-isMemberAllowed-address-)

# Events:
- [`Deposit(address fundAddress, address investor, address assetDeposited, uint256 amountDeposited, uint256 valueDeposited, uint256 fundTokensReceived, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, uint256 time)`](#PoolLogicV23-Deposit-address-address-address-uint256-uint256-uint256-uint256-uint256-uint256-uint256-)
- [`Withdrawal(address fundAddress, address investor, uint256 valueWithdrawn, uint256 fundTokensWithdrawn, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, struct PoolLogicV23.WithdrawnAsset[] withdrawnAssets, uint256 time)`](#PoolLogicV23-Withdrawal-address-address-uint256-uint256-uint256-uint256-uint256-struct-PoolLogicV23-WithdrawnAsset---uint256-)
- [`TransactionExecuted(address pool, address manager, uint16 transactionType, uint256 time)`](#PoolLogicV23-TransactionExecuted-address-address-uint16-uint256-)
- [`PoolPrivacyUpdated(bool isPoolPrivate)`](#PoolLogicV23-PoolPrivacyUpdated-bool-)
- [`ManagerFeeMinted(address pool, address manager, uint256 available, uint256 daoFee, uint256 managerFee, uint256 tokenPriceAtLastFeeMint)`](#PoolLogicV23-ManagerFeeMinted-address-address-uint256-uint256-uint256-uint256-)
- [`PoolManagerLogicSet(address poolManagerLogic, address from)`](#PoolLogicV23-PoolManagerLogicSet-address-address-)


# Function `initialize(address _factory, bool _privatePool, string _fundName, string _fundSymbol)` {#PoolLogicV23-initialize-address-bool-string-string-}
No description






# Function `setPoolPrivate(bool _privatePool)` {#PoolLogicV23-setPoolPrivate-bool-}
No description






# Function `deposit(address _asset, uint256 _amount) → uint256` {#PoolLogicV23-deposit-address-uint256-}
No description




# Function `withdraw(uint256 _fundTokenAmount)` {#PoolLogicV23-withdraw-uint256-}
No description






# Function `execTransaction(address to, bytes data) → bool success` {#PoolLogicV23-execTransaction-address-bytes-}
Function to let pool talk to other protocol


## Parameters:
- `to`: The destination address for pool to talk to

- `data`: The data that going to send in the transaction


## Return Values:
- success A boolean for success or fail transaction


# Function `getFundSummary() → string, uint256, uint256, address, string, uint256, bool, uint256, uint256` {#PoolLogicV23-getFundSummary--}
No description




# Function `tokenPrice() → uint256` {#PoolLogicV23-tokenPrice--}
No description






# Function `availableManagerFee() → uint256` {#PoolLogicV23-availableManagerFee--}
No description






# Function `mintManagerFee()` {#PoolLogicV23-mintManagerFee--}
No description






# Function `getExitCooldown() → uint256` {#PoolLogicV23-getExitCooldown--}
No description




# Function `getExitRemainingCooldown(address sender) → uint256` {#PoolLogicV23-getExitRemainingCooldown-address-}
No description




# Function `setPoolManagerLogic(address _poolManagerLogic) → bool` {#PoolLogicV23-setPoolManagerLogic-address-}
No description








# Function `managerName() → string` {#PoolLogicV23-managerName--}
No description




# Function `isMemberAllowed(address member) → bool` {#PoolLogicV23-isMemberAllowed-address-}
No description




