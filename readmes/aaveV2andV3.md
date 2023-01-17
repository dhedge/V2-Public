# We support both Aave v2 and Aave v3.

We designed contract/asset guard to suport both v2 and v3.

1. we have different lending pool assets type
We use `3` for Aave v2 lending pool asset, `8` for Aave v3 lending pool asset.
2. we have contract guards for v2 and v3.
Aave v3 contract guard is inherited from Aave v2 contract guard.
- `AaveLendingPoolGuardV2` is the basic contract guard that supports Aave v2.
- `AaveLendingPoolGuardV3` is inherited from AaveLendingPoolGuardV2 and supports Aave v3
- `AaveLendingPoolGuardV3L2Pool` is inherited from AaveLendingPoolGuardV3 and supports Aave v3 on L2 like optimism

# How Aave works

Aave is a decentralized lending protocol.

1. users deposit supported collateral tokens.
Each collateral token has its LTV (loan-to-value) which represent the percentage he can borrow against his collateral.
2. users can take loans against their collateral.
Therer are two types of borrow tokens - stable debt token / variable debt token.
- stable debt token represent the borrow type with stable interest APY.
- variable debt token represent the borrow type with variable interest APY.
3. users can repay their debt. both partial and full repayment is available.
4. if user's loan is worth than the certain percent of the collateral amount, then the liquidation happens.
5. aave supports multi-collateral which means users can deposit multiple collateral tokens and take loan against them.

# Differences between `Aave v2` and `Aave v3`

Both v2 nd v3 has the same interface and the main different is that v3 supports crosschain staff which we don't support.
This shows the contract functions change of Aave v2 and Aave v3

## deposit collateral
Deposits a certain amount of an asset into the protocol, minting the same amount of corresponding aTokens, and transferring them to the onBehalfOf address.

- Aave v2 (LendingPool)

```
function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
```

- Aave v3 (Pool)

```
function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
```

## withdraw collateral
Withdraws amount of the underlying asset, i.e. redeems the underlying token and burns the aTokens.

- Aave v2 (LendingPool)

```
function withdraw(address asset, uint256 amount, address to)
```

- Aave v3 (Pool)

```
function withdraw(address asset, uint256 amount, address to)
```

## use reserve as collateral
Sets the asset of msg.sender to be used as collateral or not.

- Aave v2 (LendingPool)

```
function setUserUseReserveAsCollateral(address asset, bool useAsCollateral)
```

- Aave v3 (Pool)

```
function setUserUseReserveAsCollateral(address asset, bool useAsCollateral)
```

## borrow
Borrows amount of asset with interestRateMode, sending the amount to msg.sender, with the debt being incurred by onBehalfOf.

- Aave v2 (LendingPool)

```
function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
```

- Aave v3 (Pool)

```
function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
```

## repay debt
Repays onBehalfOf's debt amount of asset which has a rateMode.

- Aave v2 (LendingPool)

```
function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf)
```

- Aave v3 (Pool)

```
function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf)
```

## swap borrow rate mode
Swaps msg.sender's borrow rate mode between stable and variable.

- Aave v2 (LendingPool)

```
function swapBorrowRateMode(address asset, uint256 rateMode)
```

- Aave v3 (Pool)

```
function swapBorrowRateMode(address asset, uint256 rateMode)
```

## rebalance stable borrow rate
Rebalances stable borrow rate of the user for given asset. In case of liquidity crunches on the protocol, stable rate borrows might need to be rebalanced to bring back equilibrium between the borrow and supply rates.

- Aave v2 (LendingPool)

```
function rebalanceStableBorrowRate(address asset, address user)
```

- Aave v3 (Pool)

```
function rebalanceStableBorrowRate(address asset, address user)
```

## calculate token balances

- Aave v2

```
// query token addresses
(address aToken, address stableDebtToken, address variableDebtToken) = aaveProtocolDataProvider.getReserveTokensAddresses(asset);

// query configuration
configuration = ILendingPool(aaveLendingPool).getConfiguration(asset)
```

- Aave v3

can use `Pool.getReserveData()`. it both returns aToken, debtToken addresses and configuration map.

## flashloan
Allows users to access liquidity of the pool for given list of assets for one transaction as long as the amount taken plus fee is returned or debt position is opened by the end of transaction.

- Aave v2 (LendingPool)

```
function flashLoan(address receiverAddress, address[] calldata assets, uint256[] calldata amounts, uint256[] modes, address onBehalfOf, bytes calldata params, uint16 referralCode)
```

- Aave v3 (Pool)

```
function flashLoan(address receiverAddress, address[] calldata assets, uint256[] calldata amounts, uint256[] interestRateModes, address onBehalfOf, bytes calldata params, uint16 referralCode)
```
