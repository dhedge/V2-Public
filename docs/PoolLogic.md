## `PoolLogic`





### `onlyPrivate()`





### `onlyManager()`





### `onlyManagerOrTrader()`





### `whenNotPaused()`






### `initialize(address _factory, bool _privatePool, string _fundName, string _fundSymbol)` (public)





### `_beforeTokenTransfer(address from, address to, uint256 amount)` (internal)





### `setPoolPrivate(bool _privatePool)` (public)





### `_setPoolPrivacy(bool _privacy)` (internal)





### `deposit(address _asset, uint256 _amount) → uint256` (public)





### `withdraw(uint256 _fundTokenAmount)` (public)





### `_withdrawProcessing(address asset, address to, uint256 portion) → bool success` (internal)

Perform any additional processing on withdrawal of asset


Checks for staked tokens and withdraws them to the investor account


### `execTransaction(address to, bytes data) → bool success` (public)

Function to let pool talk to other protocol


execute transaction for the pool


### `getFundSummary() → string, uint256, uint256, address, string, uint256, bool, uint256, uint256` (public)





### `tokenPrice() → uint256` (public)





### `_tokenPrice(uint256 _fundValue, uint256 _tokenSupply) → uint256` (internal)





### `availableManagerFee() → uint256` (public)





### `_availableManagerFee(uint256 _fundValue, uint256 _tokenSupply, uint256 _lastFeeMintPrice, uint256 _feeNumerator, uint256 _feeDenominator) → uint256` (internal)





### `mintManagerFee()` (public)





### `_mintManagerFee() → uint256 fundValue` (internal)





### `getExitCooldown() → uint256` (public)





### `getExitRemainingCooldown(address sender) → uint256` (public)





### `setPoolManagerLogic(address _poolManagerLogic) → bool` (external)





### `manager() → address` (internal)





### `trader() → address` (internal)





### `managerName() → string` (public)





### `isMemberAllowed(address member) → bool` (public)






### `Deposit(address fundAddress, address investor, address assetDeposited, uint256 amountDeposited, uint256 valueDeposited, uint256 fundTokensReceived, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, uint256 time)`





### `Withdrawal(address fundAddress, address investor, uint256 valueWithdrawn, uint256 fundTokensWithdrawn, uint256 totalInvestorFundTokens, uint256 fundValue, uint256 totalSupply, struct PoolLogic.WithdrawnAsset[] withdrawnAssets, uint256 time)`





### `TransactionExecuted(address pool, address manager, uint8 transactionType, uint256 time)`





### `PoolPrivacyUpdated(bool isPoolPrivate)`





### `ManagerFeeMinted(address pool, address manager, uint256 available, uint256 daoFee, uint256 managerFee, uint256 tokenPriceAtLastFeeMint)`





### `PoolManagerLogicSet(address poolManagerLogic, address from)`





