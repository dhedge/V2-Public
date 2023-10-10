# Synthetix Futures

From the Synthetix Docs:

>Futures markets allow users leveraged exposure to an asset, long or short. A user must post some margin in order to open a futures account, and profits/losses are continually tallied against this margin. If a user's margin runs out, then their position is closed by a liquidation keeper, which is rewarded with a flat fee extracted from the margin.

N.B.

- A futures positions has finite upside which is margin * leverage.
- There are fees for opening a future.
- There are fees for closing a future.
- There is a funding rate that is charge on a future.
- Its the future.

## Resources

Most of the information for this integration is contained in the following:

https://github.com/Synthetixio/synthetix/blob/master/contracts/FuturesMarketBase.sol
https://github.com/Synthetixio/synthetix/blob/master/contracts/MixinFuturesViews.sol

# AssetGuard - SynthetixFuturesMarketAssetGuard

Each futures market is configured as an asset. This asset is assetType 101.
The SynthetixFuturesMarketAssetGuard can be shared by all Futures Markets.

`getBalance()` Calculates the value of the future by combining `remainingMargin()` minus `orderFee()` (the cost to close the future).
`withdrawProcessing()` Investors are able to take their portion of any future. We reduce the size of the future by the investors share using `modifyPosition()`,  and directly transfer the withdrawers portion of the margin to them. It subtracts the orderFee for closing the portion from the margin sent to the withdrawer.

# ContractGuard - SynthetixFuturesMarketContractGuard

Currently supports:

- transferMargin
- modifyPositionWithTracking
- closePositionWithTracking
- withdrawAllMargin

All these function can only be called as the owner of the future so makes things nice and tidy.

This contractGuard needs to be configured for each FutureMarket.

Does not currently support:

- submitNextPriceOrderWithTracking (more on that at the bottom of this document)


## Investigation Txs

1. Transfer Margin https://optimistic.etherscan.io/tx/0x69092b350757b9173a686340236f0c55e8cf87f93e1a12db7e9eace98432edfb
2. Withdraw All Margin https://optimistic.etherscan.io/tx/0x22dc8064c9bb4b795b4038e42d3d581252b6352d2460f17f37d523e9cea78db2
3. ModifyPositionWithTracking https://optimistic.etherscan.io/tx/0xd28fcf5192f07d59f5254a4ff9a7cee86c949ccf689439524f630b0d6caeda3f
4. CloseWithTracking https://optimistic.etherscan.io/tx/0xae3e931e121f92b6418e9247458c6eec6b64847a20e620489500b98a66c1dcc3
5. ModifyPositionWithTracking https://optimistic.etherscan.io/tx/0xe9d0bd53b76f6f6440e9a29ab78b1c7b4b713e80d986fb9df84534985b2343ff


# NextPrice Orders (Not Supported)

Futures supports what are called NextPrice orders which are executed by a keeper at the next price update. In the docs:

> Specifically, this should serve funding rate arbitrageurs, such that funding rate arb is profitable for smaller skews. This in turn serves the protocol by reducing the skew, and so the risk to the debt pool, and funding rate for traders.

This has not been implemented for the first iteration of this integration. It increases the complexity because it effectively introduces a 2 stage process of buying a future. It is possible to implement `submitNextPriceOrderWithTracking` but some care needs to be taken to cancel any pending order during withdrawProcessing and calculate the margin correctly, as the fee is taken when the order is placed not executed. I decided because of the additional complexity we could determine the desire from managers once the initial version is deployed.

More information: https://github.com/Synthetixio/synthetix/blob/master/contracts/MixinFuturesNextPriceOrders.sol
