# Guards

Guards allow us to safely interface with external protocols and assets. They also act as adapters, i.e exposing a common interface to our other logic (poolLogic, poolManagerLogic etc). There are currently two types of guards:

1. Contract Guards
2. Asset Guards

## Contract Guards

A contract guard ensures that a manager can only call functions on an external contract that we allow. For instance the AaveLending Guard ensures that the manager can `deposit`, `borrow`, `repay`, and `withdraw` through Aave. The manager can only call functions on the Aave contract we allow. As an example we would not want a manager to be able to call a function like `DepositAs(as: address)` with a `as` address other than the pool. This could allow the manager to steal funds. We can also control other functionality such as how many assets a manager can borrow through Aave, i.e we currently restrict it to 1.

A contract guard can also allow a function to be called by anyone (not just the manager) through a second return variable called `public`. For instance some protocols require rewards to be `claimed`, we allow anyone to call the `claim` function on the rewards contract.

## Asset Guards

Through asset guards we can allow pools to hold not only simple erc20 positions but also complex groups of assets. We can currently think of a `asset` as either a individual erc20 contract, a group of erc20 positions managed through a central contract like AaveLendingPool, or a group of erc721 LP positions like through the UniswapV3 NftPositionManager.

Some other examples:

- Plain erc20 token position (weth, susd, usdc, wbtc, sushi, etc, etc)
- Individual Uniswap V2 erc20 Automated Market Maker Liquidity Providing (uniswap, sushiswap, quickswap)
- Individual Balancer erc20 Automated Market Maker Liquidity Providing
- A group of Uniswap v3 erc721 Automated Market Liquidity Providing Positions
- A group of Lending and Borrowing positions through AaveLendingPool.

An asset guard is responsible for exposing an assets:

- Balance or Aggregate Balance for assets that hold multiple positions (i.e aave).
- Whether a Manager can remove that asset from the supported assets of the pool (i.e 0 balance, debts have been repayed etc).
- WithdrawProcessing - How an investor can claim and withdraw their portion of the asset (i.e lp position may need to be unrolled, aave debt position might need to be repayed etc).

Remember in some cases a single `asset` can represent multiple sub assets. I.E all loan and borrow positions within aave are represented by the AaveLendingPool asset even though underneath the pool holds aTokens and debtTokens.

Other examples to clarify:

- A pool can hold the SUSHI token. The SUSHI token is configured to use the ERC20Guard as it is a simple erc20 position. The balance of the position is simply the number of tokens. The chainlink usd price feed for that token is use to calculate the positions value.
- A pool can hold a Balancer ETH/USDC Liquidity Providing Position. The pool holds ETH/USDC LP Tokens which is an ERC20 position and that asset is configured to use ERC20Guard, the balance of the position is simply the number of lp tokens the pool holds. The BalancerV2LpAggregator is used to calculate the value of each of the tokens by looking at the assets the underly the lp tokens.
- A pool can hold multiple Aave lending(collateral) and debt positions. I.E it can loan Aave wbtc and dai, and borrow weth. The balance of the aaveLendingPool asset is the value in usdc of all the collateral assets in aggregate minus the value of all the debt assets in aggregate. The aaveLendingPoolAssetGuard returns the `balance` of the asset in USDC (and so it's balance is it's value) so a pass through 1:1 USDPriceAggregator is used for this asset.





