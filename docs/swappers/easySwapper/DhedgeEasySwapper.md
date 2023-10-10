

# Functions:
- [`receive()`](#DhedgeEasySwapper-receive--)
- [`fallback()`](#DhedgeEasySwapper-fallback--)
- [`initialize(address payable _feeSink, uint256 _feeNumerator, uint256 _feeDenominator)`](#DhedgeEasySwapper-initialize-address-payable-uint256-uint256-)
- [`setWithdrawProps(struct EasySwapperStructs.WithdrawProps _withdrawProps)`](#DhedgeEasySwapper-setWithdrawProps-struct-EasySwapperStructs-WithdrawProps-)
- [`setSwapRouter(contract IUniswapV2RouterSwapOnly _swapRouter)`](#DhedgeEasySwapper-setSwapRouter-contract-IUniswapV2RouterSwapOnly-)
- [`setPoolAllowed(address pool, bool allowed)`](#DhedgeEasySwapper-setPoolAllowed-address-bool-)
- [`setFee(uint256 numerator, uint256 denominator)`](#DhedgeEasySwapper-setFee-uint256-uint256-)
- [`setFeeSink(address payable sink)`](#DhedgeEasySwapper-setFeeSink-address-payable-)
- [`setManagerFeeBypass(address manager, bool bypass)`](#DhedgeEasySwapper-setManagerFeeBypass-address-bool-)
- [`deposit(address pool, contract IERC20Extended depositAsset, uint256 amount, contract IERC20Extended poolDepositAsset, uint256 expectedLiquidityMinted)`](#DhedgeEasySwapper-deposit-address-contract-IERC20Extended-uint256-contract-IERC20Extended-uint256-)
- [`depositWithCustomCooldown(address pool, contract IERC20Extended depositAsset, uint256 amount, contract IERC20Extended poolDepositAsset, uint256 expectedLiquidityMinted)`](#DhedgeEasySwapper-depositWithCustomCooldown-address-contract-IERC20Extended-uint256-contract-IERC20Extended-uint256-)
- [`depositNative(address pool, contract IERC20Extended poolDepositAsset, uint256 expectedLiquidityMinted)`](#DhedgeEasySwapper-depositNative-address-contract-IERC20Extended-uint256-)
- [`depositNativeWithCustomCooldown(address pool, contract IERC20Extended poolDepositAsset, uint256 expectedLiquidityMinted)`](#DhedgeEasySwapper-depositNativeWithCustomCooldown-address-contract-IERC20Extended-uint256-)
- [`depositQuote(address pool, contract IERC20Extended depositAsset, uint256 amount, contract IERC20Extended poolDepositAsset, bool customCooldown)`](#DhedgeEasySwapper-depositQuote-address-contract-IERC20Extended-uint256-contract-IERC20Extended-bool-)
- [`withdraw(address pool, uint256 fundTokenAmount, contract IERC20Extended withdrawalAsset, uint256 expectedAmountOut)`](#DhedgeEasySwapper-withdraw-address-uint256-contract-IERC20Extended-uint256-)
- [`withdrawSUSD(address pool, uint256 fundTokenAmount, contract IERC20Extended intermediateAsset, uint256 expectedAmountSUSD)`](#DhedgeEasySwapper-withdrawSUSD-address-uint256-contract-IERC20Extended-uint256-)
- [`withdrawIntermediate(address pool, uint256 fundTokenAmount, contract IERC20Extended intermediateAsset, contract IERC20Extended finalAsset, uint256 expectedAmountFinalAsset)`](#DhedgeEasySwapper-withdrawIntermediate-address-uint256-contract-IERC20Extended-contract-IERC20Extended-uint256-)

# Events:
- [`Deposit(address pool, address depositor, address depositAsset, uint256 amount, address poolDepositAsset, uint256 liquidityMinted)`](#DhedgeEasySwapper-Deposit-address-address-address-uint256-address-uint256-)


# Function `receive()` {#DhedgeEasySwapper-receive--}
No description




# Function `fallback()` {#DhedgeEasySwapper-fallback--}
No description




# Function `initialize(address payable _feeSink, uint256 _feeNumerator, uint256 _feeDenominator)` {#DhedgeEasySwapper-initialize-address-payable-uint256-uint256-}
No description

## Parameters:
- `_feeSink`: Address of the fee recipient

- `_feeNumerator`: Fee numerator ie 1

- `_feeDenominator`: Fee denominator ie 100



# Function `setWithdrawProps(struct EasySwapperStructs.WithdrawProps _withdrawProps)` {#DhedgeEasySwapper-setWithdrawProps-struct-EasySwapperStructs-WithdrawProps-}
Sets the WithdrawProps


## Parameters:
- `_withdrawProps`: the new withdrawProps



# Function `setSwapRouter(contract IUniswapV2RouterSwapOnly _swapRouter)` {#DhedgeEasySwapper-setSwapRouter-contract-IUniswapV2RouterSwapOnly-}
Allows the swap router to be updated


## Parameters:
- `_swapRouter`: the address of a UniV2 compatible router



# Function `setPoolAllowed(address pool, bool allowed)` {#DhedgeEasySwapper-setPoolAllowed-address-bool-}
Sets if a pool is allowed to use the custom cooldown deposit functions


## Parameters:
- `pool`: the pool for the setting

- `allowed`: if the pool is allowed, can be used to remove pool



# Function `setFee(uint256 numerator, uint256 denominator)` {#DhedgeEasySwapper-setFee-uint256-uint256-}
Sets the deposit fee, thats charged to the user


## Parameters:
- `numerator`: the numerator ie 1

- `denominator`: he denominator ie 100



# Function `setFeeSink(address payable sink)` {#DhedgeEasySwapper-setFeeSink-address-payable-}
Sets where the deposit fee is sent


## Parameters:
- `sink`: the address of the fee receipient



# Function `setManagerFeeBypass(address manager, bool bypass)` {#DhedgeEasySwapper-setManagerFeeBypass-address-bool-}
Bypasses the fee for a pool manager


## Parameters:
- `manager`: Manager to bypass the fee for

- `bypass`: Enable / disable bypass



# Function `deposit(address pool, contract IERC20Extended depositAsset, uint256 amount, contract IERC20Extended poolDepositAsset, uint256 expectedLiquidityMinted) → uint256 liquidityMinted` {#DhedgeEasySwapper-deposit-address-contract-IERC20Extended-uint256-contract-IERC20Extended-uint256-}
deposit into underlying pool and receive tokens with normal lockup


## Parameters:
- `pool`: the pool to deposit into

- `depositAsset`: the asset the user wants to deposit

- `amount`: the amount of the deposit asset

- `poolDepositAsset`: the asset that the pool accepts

- `expectedLiquidityMinted`: the expected amount of pool tokens to receive (slippage protection)


## Return Values:
- liquidityMinted the number of wrapper tokens allocated


# Function `depositWithCustomCooldown(address pool, contract IERC20Extended depositAsset, uint256 amount, contract IERC20Extended poolDepositAsset, uint256 expectedLiquidityMinted) → uint256 liquidityMinted` {#DhedgeEasySwapper-depositWithCustomCooldown-address-contract-IERC20Extended-uint256-contract-IERC20Extended-uint256-}
deposit into underlying pool and receive tokens with 15 minutes lockup


## Parameters:
- `pool`: the pool to deposit into

- `depositAsset`: the asset the user wants to deposit

- `amount`: the amount of the deposit asset

- `poolDepositAsset`: the asset that the pool accepts

- `expectedLiquidityMinted`: the expected amount of pool tokens to receive (slippage protection)


## Return Values:
- liquidityMinted the number of wrapper tokens allocated


# Function `depositNative(address pool, contract IERC20Extended poolDepositAsset, uint256 expectedLiquidityMinted) → uint256 liquidityMinted` {#DhedgeEasySwapper-depositNative-address-contract-IERC20Extended-uint256-}
deposit native asset into underlying pool and receive tokens with normal lockup


## Parameters:
- `pool`: the pool to deposit into

- `poolDepositAsset`: the asset that the pool accepts

- `expectedLiquidityMinted`: the expected amount of pool tokens to receive (slippage protection)


## Return Values:
- liquidityMinted the number of wrapper tokens allocated


# Function `depositNativeWithCustomCooldown(address pool, contract IERC20Extended poolDepositAsset, uint256 expectedLiquidityMinted) → uint256 liquidityMinted` {#DhedgeEasySwapper-depositNativeWithCustomCooldown-address-contract-IERC20Extended-uint256-}
deposit native asset into underlying pool and receive tokens with 15 minutes lockup


## Parameters:
- `pool`: the pool to deposit into

- `poolDepositAsset`: the asset that the pool accepts

- `expectedLiquidityMinted`: the expected amount of pool tokens to receive (slippage protection)


## Return Values:
- liquidityMinted the number of wrapper tokens allocated




# Function `depositQuote(address pool, contract IERC20Extended depositAsset, uint256 amount, contract IERC20Extended poolDepositAsset, bool customCooldown) → uint256 expectedLiquidityMinted` {#DhedgeEasySwapper-depositQuote-address-contract-IERC20Extended-uint256-contract-IERC20Extended-bool-}
calculates how many tokens the user should receive on deposit based on current swap conditions


## Parameters:
- `pool`: the pool to deposit into

- `depositAsset`: the asset the user wants to deposit

- `amount`: the amount of the deposit asset

- `poolDepositAsset`: the asset that the pool accepts

- `customCooldown`: quote required for custom cooldown deposit method or not


## Return Values:
- expectedLiquidityMinted the expected amount of pool tokens to receive inclusive of slippage


# Function `withdraw(address pool, uint256 fundTokenAmount, contract IERC20Extended withdrawalAsset, uint256 expectedAmountOut)` {#DhedgeEasySwapper-withdraw-address-uint256-contract-IERC20Extended-uint256-}
withdraw underlying value of tokens in expectedWithdrawalAssetOfUser


## Parameters:
- `pool`: dhedgepool to withdraw from

- `fundTokenAmount`: the amount to withdraw

- `withdrawalAsset`: must have direct pair to all pool.supportedAssets on swapRouter

- `expectedAmountOut`: the amount of value in the withdrawalAsset expected (slippage protection)



# Function `withdrawSUSD(address pool, uint256 fundTokenAmount, contract IERC20Extended intermediateAsset, uint256 expectedAmountSUSD)` {#DhedgeEasySwapper-withdrawSUSD-address-uint256-contract-IERC20Extended-uint256-}
Withdraw underlying value of tokens into intermediate asset and then swap to susd


## Parameters:
- `pool`: dhedgepool to withdraw from

- `fundTokenAmount`: the dhedgepool amount to withdraw

- `intermediateAsset`: must have direct pair to all pool.supportedAssets on swapRouter and to SUSD

- `expectedAmountSUSD`: the amount of value in susd expected (slippage protection)



# Function `withdrawIntermediate(address pool, uint256 fundTokenAmount, contract IERC20Extended intermediateAsset, contract IERC20Extended finalAsset, uint256 expectedAmountFinalAsset)` {#DhedgeEasySwapper-withdrawIntermediate-address-uint256-contract-IERC20Extended-contract-IERC20Extended-uint256-}
Withdraw underlying value of tokens into intermediate asset and then swap to final asset


## Parameters:
- `pool`: dhedgepool to withdraw from

- `fundTokenAmount`: the dhedgepool amount to withdraw

- `intermediateAsset`: must have direct pair to all pool.supportedAssets on swapRouter

- `finalAsset`: must have direct pair to intermediate asset

- `expectedAmountFinalAsset`: the amount of value in final asset expected (slippage protection)



