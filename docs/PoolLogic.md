

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

# Events:
- [`Deposit(address fundAddress, address investor, address assetDeposited, uint256 amountDeposited, uint256 valueDeposited, uint256 fundTokensReceived, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, uint256 time)`](#PoolLogic-Deposit-address-address-address-uint256-uint256-uint256-uint256-uint256-uint256-uint256-)
- [`Withdrawal(address fundAddress, address investor, uint256 valueWithdrawn, uint256 fundTokensWithdrawn, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, struct PoolLogic.WithdrawnAsset[] withdrawnAssets, uint256 time)`](#PoolLogic-Withdrawal-address-address-uint256-uint256-uint256-uint256-uint256-struct-PoolLogic-WithdrawnAsset---uint256-)
- [`TransactionExecuted(address pool, address manager, uint8 transactionType, uint256 time)`](#PoolLogic-TransactionExecuted-address-address-uint8-uint256-)
- [`PoolPrivacyUpdated(bool isPoolPrivate)`](#PoolLogic-PoolPrivacyUpdated-bool-)
- [`ManagerFeeMinted(address pool, address manager, uint256 available, uint256 daoFee, uint256 managerFee, uint256 tokenPriceAtLastFeeMint)`](#PoolLogic-ManagerFeeMinted-address-address-uint256-uint256-uint256-uint256-)
- [`PoolManagerLogicSet(address poolManagerLogic, address from)`](#PoolLogic-PoolManagerLogicSet-address-address-)

# Function `initialize(address _factory, bool _privatePool, string _fundName, string _fundSymbol)` {#PoolLogic-initialize-address-bool-string-string-}
No description
# Function `setPoolPrivate(bool _privatePool)` {#PoolLogic-setPoolPrivate-bool-}
No description
# Function `deposit(address _asset, uint256 _amount) → uint256` {#PoolLogic-deposit-address-uint256-}
No description
# Function `withdraw(uint256 _fundTokenAmount)` {#PoolLogic-withdraw-uint256-}
No description
# Function `execTransaction(address to, bytes data) → bool success` {#PoolLogic-execTransaction-address-bytes-}
execute transaction for the pool

## Parameters:
- `to`: The destination address for pool to talk to

- `data`: The data that going to send in the transaction

## Return Values:
- success A boolean for success or fail transaction
# Function `getFundSummary() → string, uint256, uint256, address, string, uint256, bool, uint256, uint256` {#PoolLogic-getFundSummary--}
No description
# Function `tokenPrice() → uint256` {#PoolLogic-tokenPrice--}
No description
# Function `availableManagerFee() → uint256` {#PoolLogic-availableManagerFee--}
No description
# Function `mintManagerFee()` {#PoolLogic-mintManagerFee--}
No description
# Function `getExitCooldown() → uint256` {#PoolLogic-getExitCooldown--}
No description
# Function `getExitRemainingCooldown(address sender) → uint256` {#PoolLogic-getExitRemainingCooldown-address-}
No description
# Function `setPoolManagerLogic(address _poolManagerLogic) → bool` {#PoolLogic-setPoolManagerLogic-address-}
No description
# Function `managerName() → string` {#PoolLogic-managerName--}
No description
# Function `isMemberAllowed(address member) → bool` {#PoolLogic-isMemberAllowed-address-}
No description

# Event `Deposit(address fundAddress, address investor, address assetDeposited, uint256 amountDeposited, uint256 valueDeposited, uint256 fundTokensReceived, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, uint256 time)` {#PoolLogic-Deposit-address-address-address-uint256-uint256-uint256-uint256-uint256-uint256-uint256-}
No description
# Event `Withdrawal(address fundAddress, address investor, uint256 valueWithdrawn, uint256 fundTokensWithdrawn, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, struct PoolLogic.WithdrawnAsset[] withdrawnAssets, uint256 time)` {#PoolLogic-Withdrawal-address-address-uint256-uint256-uint256-uint256-uint256-struct-PoolLogic-WithdrawnAsset---uint256-}
No description
# Event `TransactionExecuted(address pool, address manager, uint8 transactionType, uint256 time)` {#PoolLogic-TransactionExecuted-address-address-uint8-uint256-}
No description
# Event `PoolPrivacyUpdated(bool isPoolPrivate)` {#PoolLogic-PoolPrivacyUpdated-bool-}
No description
# Event `ManagerFeeMinted(address pool, address manager, uint256 available, uint256 daoFee, uint256 managerFee, uint256 tokenPriceAtLastFeeMint)` {#PoolLogic-ManagerFeeMinted-address-address-uint256-uint256-uint256-uint256-}
No description
# Event `PoolManagerLogicSet(address poolManagerLogic, address from)` {#PoolLogic-PoolManagerLogicSet-address-address-}
No description
