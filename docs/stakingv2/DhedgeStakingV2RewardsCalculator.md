

# Functions:
- [`calculateDhtRewardAmount(uint256 vDHTAmount, uint256 poolTokensStaked, uint256 tokenPriceStart, uint256 tokenPriceFinish, uint256 stakeStartTime, uint256 stakeFinishTime, uint256 stakeEmissionsRate, struct IDhedgeStakingV2Storage.RewardParams rewardParams)`](#DhedgeStakingV2RewardsCalculator-calculateDhtRewardAmount-uint256-uint256-uint256-uint256-uint256-uint256-uint256-struct-IDhedgeStakingV2Storage-RewardParams-)
- [`calculateMaxVDHTAllowed(uint256 vDHTAmount, uint256 totalValue, uint256 stakingRatio)`](#DhedgeStakingV2RewardsCalculator-calculateMaxVDHTAllowed-uint256-uint256-uint256-)
- [`calculatePerformanceFactor(uint256 tokenPriceStart, uint256 tokenPriceFinish, uint256 maxPerformanceBoostNumerator, uint256 maxPerformanceBoostDenominator)`](#DhedgeStakingV2RewardsCalculator-calculatePerformanceFactor-uint256-uint256-uint256-uint256-)
- [`calculateStakeDurationFactor(uint256 stakeStartTime, uint256 stakeFinishTime, uint256 maxDurationBoostSeconds)`](#DhedgeStakingV2RewardsCalculator-calculateStakeDurationFactor-uint256-uint256-uint256-)



# Function `calculateDhtRewardAmount(uint256 vDHTAmount, uint256 poolTokensStaked, uint256 tokenPriceStart, uint256 tokenPriceFinish, uint256 stakeStartTime, uint256 stakeFinishTime, uint256 stakeEmissionsRate, struct IDhedgeStakingV2Storage.RewardParams rewardParams) → uint256` {#DhedgeStakingV2RewardsCalculator-calculateDhtRewardAmount-uint256-uint256-uint256-uint256-uint256-uint256-uint256-struct-IDhedgeStakingV2Storage-RewardParams-}
Calculates how many DHT a staker should recieve


## Parameters:
- `vDHTAmount`: the amount of dht staked

- `poolTokensStaked`: the number of pool tokens staked

- `tokenPriceStart`: the price of the dhedge pool when the stake started

- `tokenPriceFinish`: the price of the dhedge pool when the stake finished (unstaked)

- `stakeStartTime`: when the DHPT stake started

- `stakeFinishTime`: when the DHPT stake finished

- `stakeEmissionsRate`: the emissions rate when the stake was created

- `rewardParams`: current rewards configuration



# Function `calculateMaxVDHTAllowed(uint256 vDHTAmount, uint256 totalValue, uint256 stakingRatio) → uint256` {#DhedgeStakingV2RewardsCalculator-calculateMaxVDHTAllowed-uint256-uint256-uint256-}
Calculates the max vDHT a staker can receive based on the amount of DHPT value staked


## Parameters:
- `vDHTAmount`: the amount of dht staked

- `totalValue`: the number of pool tokens staked

- `stakingRatio`: the price of the dhedge pool when the stake started



# Function `calculatePerformanceFactor(uint256 tokenPriceStart, uint256 tokenPriceFinish, uint256 maxPerformanceBoostNumerator, uint256 maxPerformanceBoostDenominator) → uint256` {#DhedgeStakingV2RewardsCalculator-calculatePerformanceFactor-uint256-uint256-uint256-uint256-}
Calculates the performance factor


## Parameters:
- `tokenPriceStart`: the price of the dhedge pool when the stake started

- `tokenPriceFinish`: the price of the dhedge pool when the stake finished (unstaked)

- `maxPerformanceBoostNumerator`: The change in tokenPrice to acheive the maximum factor denominated by maxPerformanceBoostDenominator

- `maxPerformanceBoostDenominator`: the denominator of factor



# Function `calculateStakeDurationFactor(uint256 stakeStartTime, uint256 stakeFinishTime, uint256 maxDurationBoostSeconds) → uint256` {#DhedgeStakingV2RewardsCalculator-calculateStakeDurationFactor-uint256-uint256-uint256-}
Calculates the DHPT stake duration factor


## Parameters:
- `stakeStartTime`: when the DHPT stake started

- `stakeFinishTime`: when the DHPT stake finished

- `maxDurationBoostSeconds`: The amount of time to stake to acheive the maximum factor



