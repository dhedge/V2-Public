# VelodromeCL (slipstream)

This document outlines the integration process for Velodrome Slipstream.

The contracts for Slipstream are derived from both UniswapV3's core and periphery contracts. They also include gauge contracts tailored to function within the Velodrome ecosystem.

This integration facilitates support for a dhedge vault to LP and Stake the NFT position via the related Gauge, enabling the dhedge vault to mint up to 3 NFT positions.

## Resources

Key information regarding this integration can be found in the Slipstream repository:

- [GitHub Repository](https://github.com/velodrome-finance/slipstream)
- [Paragraph Article](https://paragraph.xyz/@velodrome/slipstream)

The general workflow for a Slipstream user is as follows:

1. Mint an NFT position.
2. Stake the NFT to the gauge.
3. Claim rewards via the gauge.

## ContractGuard

### VelodromeNonfungiblePositionGuard

This component is responsible for creating or managing the un-staked NFT position. The following operations are supported:

- [mint](https://github.com/velodrome-finance/slipstream/blob/main/contracts/periphery/NonfungiblePositionManager.sol#L143)
- [increaseLiquidity](https://github.com/velodrome-finance/slipstream/blob/main/contracts/periphery/NonfungiblePositionManager.sol#L217): Transfer token0 and token1 from the caller to the pool, recording the increased LP within the NonfungiblePositionManager contract.
- [decreaseLiquidity](https://github.com/velodrome-finance/slipstream/blob/main/contracts/periphery/NonfungiblePositionManager.sol#L278): Account for the decrease in LP within the NonfungiblePositionManager contract; no token0 or token1 transfers occur.
- [collect](https://github.com/velodrome-finance/slipstream/blob/main/contracts/periphery/NonfungiblePositionManager.sol#L339): gathering the decreased LP tokens for both token0 and token1.
- [burn](https://github.com/velodrome-finance/slipstream/blob/main/contracts/periphery/NonfungiblePositionManager.sol#L420)

Note: Ensure to call collect after calling decreaseLiquidity to redeem the LP for token0 and token1.

### VelodromeCLGaugeContractGuard

This component manages the staked NFT position, supporting the following operations:

- [increaseStakedLiquidity](<https://github.com/velodrome-finance/slipstream/blob/main/contracts/gauge/CLGauge.sol#L243>)
- [decreaseStakedLiquidity](<https://github.com/velodrome-finance/slipstream/blob/main/contracts/gauge/CLGauge.sol#L323>)
- [withdraw](https://github.com/velodrome-finance/slipstream/blob/main/contracts/gauge/CLGauge.sol#L214C14-L214C22): Unstake the NFT position.
- [deposit](https://github.com/velodrome-finance/slipstream/blob/main/contracts/gauge/CLGauge.sol#L183): Stake the NFT position.
- [getReward](<https://github.com/velodrome-finance/slipstream/blob/main/contracts/gauge/CLGauge.sol#L163>)

Note: Both increaseStakedLiquidity and decreaseStakedLiquidity will handle the token0 and token1 transfers.

## AssetGuard

### VelodromeCLAssetGuard

Note: In getBalance, the reward value is accounted for regardless of whether the rewardAsset is a supported asset or not. To ensure correct withdrawal processing, if the rewardAsset is a non-supported asset, VelodromeCLAssetGuard will manage the reward asset transfer to the withdrawer.
