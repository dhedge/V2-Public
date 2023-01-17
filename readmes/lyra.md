# Introduction
Lyra Finance is an options protocol on Optimism using Synthetix synths. The below refers to the Optimism Kovan testnet contracts which were used for the testnet competition.
These contracts are not yet live in production:

## Contracts
- [OptionMarketWrapper](https://github.com/lyra-finance/lyra-protocol/blob/avalon/contracts/periphery/Wrapper/OptionMarketWrapper.sol)
  This contract is used by Lyra frontend for executing all the transactions

## Example transactions
- [`openPosition`](https://polygonscan.com/tx/0x23fdede6386956973f83c7042371c6f55b12a7a3b31bd7b71358a6c096263dd0)
  This opens 1 ETH call option for $3250, expiry at 28th April

# Implementation

## Contract Guards

### LyraOptionMarketWrapperContractGuard
The Lyra Finance UI uses this contract for all the frontend transactions.
I believe for opening and closing the positions, the frontend only uses openPosition, closePosition (and I can see some transactions of forceClosePosition)
This contract guard will track positions opened by Pool Logic.

#### `openPosition`
This will create a NFT of position, if a position already exists, then it will increase the position amount.

Inputs: OptionPositionParams
uint strikeId; // The id of the relevant OptionListing
uint positionId;
uint iterations;
uint setCollateralTo;
uint currentCollateral;
OptionMarket.OptionType optionType; // Is the trade a long/short & call/put?
uint amount; // The amount the user has requested to close
uint minCost; // Min amount for the cost of the trade
uint maxCost; // Max amount for the cost of the trade
uint stableAmount; // Amount of stable coins the user can use
ERC20 stableAsset; // Address of coin user wants to open with

Guard implementation:
- Ensure quote asset is supported by the pool.
  ```
  synthQuoteKey = SynthetixAdapter.quoteKey(OptionMarket)
  synthQuote = SynthetixProxyAddressResolver.target.getAddress(synthQuoteKey)
  require(isValidAsset(synthQuote))
  ```
- Ensure base asset is supported by the pool.
  ```
  synthBaseKey = SynthetixAdapter.baseKey(OptionMarket)
  synthBase = SynthetixProxyAddressResolver.target.getAddress(synthBaseKey)
  require(isValidAsset(synthBase))
  ```

#### `closePosition` / `forceClosePosition`
This will reduce or close the existing position.

Inputs: OptionPositionParams
uint strikeId; // The id of the relevant OptionListing
uint positionId;
uint iterations;
uint setCollateralTo;
uint currentCollateral;
OptionMarket.OptionType optionType; // Is the trade a long/short & call/put?
uint amount; // The amount the user has requested to close
uint minCost; // Min amount for the cost of the trade
uint maxCost; // Max amount for the cost of the trade
uint stableAmount; // Amount of stable coins the user can use
ERC20 stableAsset; // Address of coin user wants to open with

Guard implementation:
- Ensure quote asset is supported by the pool.
  ```
  synthQuoteKey = SynthetixAdapter.quoteKey(OptionMarket)
  synthQuote = SynthetixProxyAddressResolver.target.getAddress(synthQuoteKey)
  require(isValidAsset(synthQuote))
  ```
- Ensure base asset is supported by the pool.
  ```
  synthBaseKey = SynthetixAdapter.baseKey(OptionMarket)
  synthBase = SynthetixProxyAddressResolver.target.getAddress(synthBaseKey)
  require(isValidAsset(synthBase))
  ```

## Asset Guard

### `LyraOptionMarketWrapperAssetGuard`
Asset guard for the lyra option market wrapper contract. (new Asset Type = 10)
The dHEDGE pool will receive the NFTs of option positions.

Similar to Uni v3 Asset Guard with NFT positions to get the user position NFTs.
Each NFT position needs to be priced (likely in sUSD, then converted to real USD).
We can enable a maximum of 2 positions in a dHEDGE pool. (this is configurable via constructor)

#### getBalance`

The balance will be similar to the UniswapV3AssetGuard, but it will calculate the value of the positions in sUSD.

- Query all available markets and owned positions.
- Check if exceeds the maxium position count.
- Calculate the value of a position.
  The position value calculation logic is different per each option type.
  Available option types are `LONG_CALL`, `LONG_PUT`, `SHORT_CALL_BASE`, `SHORT_CALL_QUOTE`, `SHORT_PUT_QUOTE`.
- Returns the value of total positions in sUSD

#### `withdrawProcessing`

- Clean up positions from LyraOptionMarketWrapperContractGuard storage
  First, it filters only active positions.
  Second, it triggers option settlement for expired positions.
  In most cases, the bot will settle expired positions - this settlement will burn position NFT and returns collateral asset back to the Pool Logic.
  So the this Lyra withdraw processing should be triggered before other collateral assets withdraw.
- Query all available markets and owned positions.
- Check if exceeds the maxium position count.
- Prepare following two transactions per each position
  
  First transactions is option token (NFT) `approve` transaction to our dHEDGE lyra wrapper contract.
  The LyraOptionMarketWrapper contract's forceClosePosition function doesn't accept any recipient parameter. We decided to build our own wrapper contract that accept the recipient parameter and transfers the withdrawn portion directly to user.
  BTW this approve transaction is required because the LyraOptionMarketWrapper's `forceClosePosition` requies the ownership of Option NFT.
  
  Second transaction is `forceClosePosition` transaction to our dHEDGE lyra wrapper contract.
  Our wrapper contract will receive Option NFT ownership and calls `forceClosePosition` function of LyraOptionMarketWrapper contract.
  It transfers the withdrawn portion assets to recipient address.
  It also returns the Option NFT back to the pool.

### Asset Aggregator
Use the chainlink price oracle for sUSD

### Current implementation status

1. Pricing option position (need to check if current GWAP price is safe to use)
   - first, we check if the price is stale (`liquidityPool.CBTimestamp <= block.timestamp`, `geekCache.isBoardCacheStale(strike.boardId)`)
   - second, we should set GWAV oracle for each option market.
   - third, we restrict the option position count per each pool logic.

2. Withdraw processing
   - first, we use our own wrapper contract to close option positions in withdraw processing. This is to accept the recipient address and transfer withdrawn liquidity directly to the user.
   - second, to close option position, we try-catch normal closePosition() function call first, if that fails, we try forceClosePosition() function call
   - third, in withdraw processing, because of `getBalance` function implementation (it has several revert cases), it can block users to withdraw funds by time.

3. We support `optionPosition`, `closePosition` and `forceClosePosition` functions in contract guard.

4. For integration tests, we are planning to use `@lyrafinance/protocol` npm package provided by Lyra team. This sdk provides some local test environments, this will help us to manipulate some test scenarios.
   BTW, we are also planning to have on-chain integration tests (integration tests with mainnet-deployed contracts). This will make sure (double check) if our contract implementation is correct.
