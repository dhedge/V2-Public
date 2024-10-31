# Easy Swapper Contract

## Brief Summary

EasySwapper was designed to mitigate several unfriendly flaws which affected user experience while using dHEDGE core contracts (PoolLogic, PoolFactory, etc.) Allows to safely bypass limitations imposed by core dHEDGE contracts without the need to refactor core logic. 

## Top Level Methods

### Depositing

- `deposit()` - Performs a deposit into arbitrary dHEDGE pool. The difference from PoolLogic.deposit() is that deposit token is not limited by tokens pool is set to accept. If caller's deposit token doesn't match pool deposit token, it makes a swap under the hood. Implements high slippage protection. Charges no fee. Received pool tokens have 24 hours lockup.

- `depositWithCustomCooldown()` - Same as `deposit()`, but can be called only on certain set of pools. Changes default time tokens are locked up after depositing from 24 hours to 60 minutes. Takes 0.1% entry fee (frontrunning protection). Current use cases are buying high volatility derivative products (ETHBULL3X, BTCBEAR2X), as well as bying Toros products inside dHEDGE pools not to block investors from exiting these pools.

- `depositNative()` - Performs a deposit into dHEDGE pool with chain native asset (e.g. ETH on Optimism, MATIC on Polygon). Wraps native asset under the hood and swaps it (if needed) to the asset accepted by the pool. Rest of behaviour is the same as `deposit()`.

- `depositNativeWithCustomCooldown()` - Same as `depositNative()`, but has peculiarities similar to `depositWithCustomCooldown()`.

### Withdrawing

- `withdraw()` - Makes a withdraw from a dhedge pool into a single asset, if conditions for the specified withdrawal asset are met. Unrolls LPs, aave positions, etc. inside the pool and then swaps everything into a single asset. See in-depth knowledge section below for details. Allows users to receive single asset after pool withdrawal instead of a bunch of assets pool was comprised of at the moment of withdrawal (which is default behaviour of PoolLogic.withdraw()). This was a big point of frustration for users before. Implements high slippage protection.

- `withdrawIntermediate()` - A helper function that allows a user to propose an intermediate asset. All assets in the pool are first swap to this intermediate asset and then this asset to the final exit asset.

- `withdrawSUSD()` - A helper function that allows a user to propose and intermidiate asset with the final asset being sUSD. First implemented specifically for dsnx.

- `withdrawNative()` - Same as `withdraw()`, but withdraws into chain native asset.

### Misc

- `depositQuote()` - Calculates how many tokens the user should receive on deposit through easy swapper based on current swap conditions.

## Different Storage Mappings for Deeper Dive

- `allowedPools` - mapping inside EasySwapper contract where pools which are allowed to have 60 minutes lockup are stored. (e.g. USDy, USDmny, Bull/Bear, etc.). `depositWithCustomCooldown()` and `depositNativeWithCustomCooldown()` check against this mapping before making deposits.

- `customCooldownWhitelist` - mapping inside PoolFactory contract where addresses which can call PoolLogic's `depositForWithCustomCooldown()` are stored (e.g. EasySwapper). This makes possible EasySwapper to have 60 minutes cooldown deposit functions.

- `receiverWhitelist` - mapping inside PoolFactory contract where addresses which can receive pool tokens under lockup are stored (e.g. DhedgeStakingV2 contract).

- `managerFeeBypass` - mapping inside EasySwapper contract where pool manager addresses which aren't charged with entry fee are stored. Usually, depositing through EasySwapper custom cooldown methods takes a 0.1% entry fee. This mapping is for cases like Toros pool manager wants to buy other Toros products (e.g. dSNX pool buys USDy).


## In-depth Knowledge

### The Interlude

The initial version of the EasySwapper was created for the Toros Leverage Pools because managing liquidity on dodo for those pools so that consumers could enter and exit in a single asset had issues.

The EasySwapper was conceived so that we wouldn't have to manage this liquidity. The original toros leverage pools consisted of usually 2 assets. Mainly a position in aave and some deposit asset. When withdrawing from those toros leverage pools a user would usually receive weth (the aave exit asset) + 1 other asset (usdc or btc).

So for these toros pools the EasySwapper was pretty straightforward, withdraw from the pool, find a swap* for the two assets, and execute those swaps to the exit asset. We also added a slippage check where we would get the value of the toros pool tokens and compare it to the value of the net amount of the exit asset. So we banged out the EasySwapper and it was pretty fit for purpose.

So TLDR, for these basic toros leverage pools (single asset short or long) the EasySwapper process and gas consumption was reasonable. Everything happens onchain, the withdrawing + the quoting + the swapping.

N.B *For swaps We created another contract called the DhedgeSuperSwapper. This contract basically can get onchain quotes from multiple Univ2 routers, uniV3 and ~~curve~~ (for some configured pairs). The more routers/pairs configured in the SuperSwapper the more gas it costs.

### The Metastasis

So dUSD was in balancer and withdrawers would receive Balancer LP tokens. This was a decent sized issue in the community and people would withdraw and then not be able to see the LP tokens or understand how to unwrap these LP tokens, so it was decided that we would add functionality to the Easyswapper to handle the unwrapping of these LP tokens, during this period we also added capabilities for unrolling univ2 lp's as well. This was the bulk of our asset types.

Once it was realised that the EasySwapper worked for dUSD it was brought up if it could be made to work for all Dhedge pools so it was updated again so that it could unwrap pools that held dUSD and toros pools (pools inside pools) and all other assetTypes that we supported. Around this period we also started supporting Arrakis so we added finding and swapping arrakis rewards tokens (the arrakis lp asset is unrolled by the pool).

So now the EasySwapper is doing a few things:

Withdrawing (sometimes withdrawing from sub pools - i.e pools that hold dusd or toros pools)
Unrolling LPs and/or detecting the assets inside an LP (so it knows what it received), detecting rewards tokens received.
Quoting via the SuperSwapper for each asset received after withdraw/unroll
Executing all the swaps
Slippage Check.
So for pools that have lots of assets or even a few assets this all adds up pretty quickly and consumes a fair bit of gas. This gas cost can be further compounded because managers use the EasySwapper from within pools that hold toros tokens. So the manager is executing a tx on behalf of the pool which is calling the easyswapper etc etc.

We then wanted the EasySwapper to support pools on OE which contain Synthetix so another functionality to the Swapper was added so that it swaps all synths to sUSD and then to the Exit asset as there is very little AMM liquidity for other synths.

### The Future

So for most people it should be pretty clear that some of this stuff we do onchain ala

A. Quoting
B. Detecting LP assets and reward assets

Could be gathered off chain and this information passed to the EasySwapper on execution.

There are a couple of reasons we didn't approach this earlier.

The main reason: We don't know exactly how much of each asset the EasySwapper will receive when calling withdraw on a pool. Particularly for pools that hold aave positions because these are collapsed onchain into a unknown amount of WETH (depends on the swap that happens on chain). This is even further complicated by Pools that hold a DhedgePool (Pool1 holds Toros BTC3x).
But whether or not we need to actually know the specific amount is up for debate an estimated amount would probably suffice for figuring out which router is going to give us the best swap and in most instances/branches uniswap v3 is going to be the answer for weth.

It breaks the current EasySwapper API. RN the front can just call Withdraw() and everything just works. No need to make any pre call to fetch information.

We need to know which router is going to give us the best price for each asset the EasySwapper receives after calling withdraw on a pool and pass this information in a timely manner to the EasySwapper.

TLDR: We need to know which assets and how much of each asset (after unrolls and including rewards) the swapper would receive and then which router to execute the swap for each of the assets on.

If we split the swapper into two parts - This would likely reduce the gas consumption of the easy swapper a fair bit because it would remove the onchain detection of underlying/reward assets and remove the onchain quoting. It would break the current api and require the frontend (consumer) to do 2 calls. One offchain to fetch the list of assets + routers and then pass that information to the EasySwapper withraw call.

This would be a pretty big refactor and take some time (especially refactoring and rewriting tests etc).
