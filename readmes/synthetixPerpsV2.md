# Synthetix PerpsV2

From the Synthetix Docs:

>Futures markets allow users leveraged exposure to an asset, long or short. A user must post some margin in order to open a futures account, and profits/losses are continually tallied against this margin. If a user's margin runs out, then their position is closed by a liquidation keeper, which is rewarded with a flat fee extracted from the margin.

N.B.
- For each Market there is a Proxy in PerpsV2 (PerpsV2MarketProxy) - only some public functions are routed by the proxy (see: PerpsV2MarketProxy.addRoute)
- The value of a future is calculate: (priceNow-underlyingPriceAtOpen*positionSize)-fundingRate
- There are fees for opening a future.
- There are fees for closing a future.
- There is a funding rate that is charge on a future.
- Fee's are massively reduced for using Delayed or Offchain orders
- Offchain orders are only initially supported for the Eth market

## Resources

Most of the information for this integration is contained in the following:

https://rattle-ticket-183.notion.site/PUBLIC-Perps-V1-V2-Integration-Guide-2e8e16fc6c08408289a5cfd9c215a721
https://github.com/Synthetixio/synthetix/blob/develop/contracts/PerpsV2MarketBase.sol
https://github.com/Synthetixio/synthetix/blob/develop/contracts/PerpsV2MarketViews.sol
https://github.com/Synthetixio/synthetix/blob/develop/contracts/PerpsV2MarketDelayedOrdersBase.sol
https://github.com/Synthetixio/synthetix/blob/develop/contracts/PerpsV2MarketDelayedOrdersOffchain.sol



# AssetGuard - SynthetixPerpsV2MarketAssetGuard

Each futures market is configured as an asset. This asset is assetType 102.
The SynthetixPerpsV2MarketAssetGuard can be shared by all PerpsV2 Markets.

`getBalance()` Calculates the value of the future by combining `remainingMargin()` minus `orderFee(int sizeDelta, IPerpsV2MarketBaseTypes.OrderType orderType)` the cost to close the future.
`withdrawProcessing()` Investors are able to take their portion of any future. We reduce the size of the future by the investors share using `modifyPosition()`,  and directly transfer the withdrawers portion of the margin to them. It subtracts the orderFee for closing the portion from the margin sent to the withdrawer. Because this needs to be atomic - the withdrawer will pay a higher fee than if the manager closed the position asyncronously.

# ContractGuard - SynthetixFuturesMarketContractGuard

Currently supports:

- transferMargin
- modifyPosition
- modifyPositionWithTracking
- submitDelayedOrder
- submitDelayedOrderWithTracking
- submitOffchainDelayedOrder
- submitOffchainDelayedOrderWithTracking
- closePosition
- closePositionWithTracking
- withdrawAllMargin

All these functions can only be called as the owner of the future so makes things nice and tidy.

This contractGuard needs to be configured for each PerpsV2MarketProxy.

## Investigation Txs

1. Transfer Margin https://optimistic.etherscan.io/tx/0x3169feec2764459d7cc5498dcbd6a62e21dfb4354a08b24850a39570895bc873
2. submitOffchainDelayedOrderWithTracking (open) - https://optimistic.etherscan.io/tx/0x1e84e09ef0bfc1286c6a39116bb945b7dbc05fb861efcf21aaca114bc8252a46
3. submitOffchainDelayedOrderWithTracking (close) https://optimistic.etherscan.io/tx/0x17d4e374a45b270ceb8db4f449b6531bfc5129e41388d6a239ca2a21d5b72fc3
4. transferMargin (withdraw margin) - https://optimistic.etherscan.io/tx/0xcbfd1e6a407668f721a46b4aca8b93c98212d68468bf22a6c22542eb9112cae2


# Delayed orders

If the manager has a submitted a delayed order and then an investor goes to withdraw - we reject the withdraw until the delayed order has been processed. This should ordinarily be very rarely.

The `Market` contract following capabilities:

```
IPerpsV2Market.DelayedOrder memory dlo = IPerpsV2Market(asset).delayedOrders(pool);
```

We then can check if the delayed order exists

```
require(dlo.sizeDelta == 0, "delayed order in progress");
```

During withdraw processing we could cancel the delayed order using `cancelDelayedOrder()` || `cancelOffchainDelayedOrder()`, but for now we think this is the best course of action
