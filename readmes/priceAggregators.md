# Price Aggregators (aka Oracles)

Price aggregators are the backbone of dhedge. They allow us to understand the value of a pool's assets. This is important for enabling fair deposits and fair withdrawals.

Price aggregators must implement the ChainLink IAggregatorV3Interface. They are used to determine the USD value of an asset.
For most simple erc20 assets (i.e weth, wbtc, link, matic, sushi) we use the Chainlink price feed (aggregator). Chainlink is a decentralised system that pushes off chain information on chain. Chainlink price feeds usually consist of the given token's price on major exchanges averaged with other smaller exchanges.

For more complex assets such as Liquidity Positions we must do some logic to understand the value of the asset. For instance with a ETH/WBTC BalancerV2Lp Position we must look at the amount of ETH and WBTC (also known as the weight) that each lp token contains. Once we have the weight of ETH v BTC we can then use a special formula for devising the value of each lp token.

Other examples:

- The DhedgePoolAggregator allows dhedge pools to hold and value dhedge pools as assets. It is basically a proxy for PoolLogic.tokenPrice().
- ETHCrossAggregator allows us to support erc20 tokens that only have a Price feed that is denominated in ETH rather than USDC. It works by taking the ETH price of the token and then multiplying it by the value of ETH in USDC.
- USDPriceAggregator is really a FixedPriceAggregator that always returns $1. Used for assets with guards that return the balance already in USD (Aave).
- MedianTWAPAggregator - This allows us to support assets that do not have a chainlink feed. A TWAP (Time-Weighted Average Price) is calculated by consistently (at an interval) sampling the onchain price of an asset and average the most recent samples. TWAPs require offchain automation that call an update function so that it can sample the price. These can be expensive to operate over the long term.




