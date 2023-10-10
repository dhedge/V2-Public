

# Functions:
- [`constructor(address _rewardToken, uint256 _rewardAmountPerSecond)`](#RewardDistribution-constructor-address-uint256-)
- [`setRewardToken(address _rewardToken)`](#RewardDistribution-setRewardToken-address-)
- [`setRewardAmountPerSecond(uint256 _rewardAmountPerSecond)`](#RewardDistribution-setRewardAmountPerSecond-uint256-)
- [`setWhitelistedPools(address[] _whitelistedPools)`](#RewardDistribution-setWhitelistedPools-address---)
- [`launch(uint256 _rewardAmountPerSecond)`](#RewardDistribution-launch-uint256-)
- [`withdrawAdmin(contract IERC20 _token, uint256 _amount)`](#RewardDistribution-withdrawAdmin-contract-IERC20-uint256-)
- [`getWhitelistedPools()`](#RewardDistribution-getWhitelistedPools--)
- [`getEligiblePoolsWithTvl()`](#RewardDistribution-getEligiblePoolsWithTvl--)
- [`calculateTotalRewardsForPeriod(uint256 _rewardAmountPerSecond, uint256 _lastDistributionTime, uint256 _blockTimestamp)`](#RewardDistribution-calculateTotalRewardsForPeriod-uint256-uint256-uint256-)
- [`calculatePoolRewardAmount(uint256 _poolTvl, uint256 _eligiblePoolsTvl, uint256 _rewardsToDistribute)`](#RewardDistribution-calculatePoolRewardAmount-uint256-uint256-uint256-)
- [`calculateEligiblePoolsRewards()`](#RewardDistribution-calculateEligiblePoolsRewards--)
- [`getRewardsAPY()`](#RewardDistribution-getRewardsAPY--)
- [`distributeRewards()`](#RewardDistribution-distributeRewards--)

# Events:
- [`RewardsDistribution(struct RewardDistribution.RewardSummary[] distributedRewards, uint256 totalDistributedRewards)`](#RewardDistribution-RewardsDistribution-struct-RewardDistribution-RewardSummary---uint256-)
- [`OwnerOperation(string operation)`](#RewardDistribution-OwnerOperation-string-)


# Function `constructor(address _rewardToken, uint256 _rewardAmountPerSecond)` {#RewardDistribution-constructor-address-uint256-}
Contract starts accruing rewards right after deployment


## Parameters:
- `_rewardToken`: ERC20 compliant token address.

- `_rewardAmountPerSecond`: Mind precision of token from 1st param.



# Function `setRewardToken(address _rewardToken)` {#RewardDistribution-setRewardToken-address-}
Setter to change reward token. Mind token precision, resetting rewardAmountPerSecond most likely will be needed


## Parameters:
- `_rewardToken`: ERC20 compliant token address



# Function `setRewardAmountPerSecond(uint256 _rewardAmountPerSecond)` {#RewardDistribution-setRewardAmountPerSecond-uint256-}
Setter to change amount of reward token streamed per second


## Parameters:
- `_rewardAmountPerSecond`: Mind reward token precision



# Function `setWhitelistedPools(address[] _whitelistedPools)` {#RewardDistribution-setWhitelistedPools-address---}
Setter to change whitelisted for distribution pools


## Parameters:
- `_whitelistedPools`: Setting empty list will stop future distributions



# Function `launch(uint256 _rewardAmountPerSecond)` {#RewardDistribution-launch-uint256-}
Function to launch reward distribution process


## Parameters:
- `_rewardAmountPerSecond`: Mind reward token precision



# Function `withdrawAdmin(contract IERC20 _token, uint256 _amount)` {#RewardDistribution-withdrawAdmin-contract-IERC20-uint256-}
Allows the contract owner to withdraw any ERC20 token in the contract


## Parameters:
- `_token`: Token address. Usually should be rewardToken

- `_amount`: Amount of tokens for emergency withdraw



# Function `getWhitelistedPools() → address[]` {#RewardDistribution-getWhitelistedPools--}
Getter for pools whitelisted for rewards



## Return Values:
- List of whitelisted pools' addresses


# Function `getEligiblePoolsWithTvl() → uint256 tvl, struct RewardDistribution.EligiblePool[] eligiblePools` {#RewardDistribution-getEligiblePoolsWithTvl--}
Aggregates total usd value of all eligible pools



## Return Values:
- tvl Total value in usd

- eligiblePools List of eligible pools


# Function `calculateTotalRewardsForPeriod(uint256 _rewardAmountPerSecond, uint256 _lastDistributionTime, uint256 _blockTimestamp) → uint256 totalRewardsForPeriod` {#RewardDistribution-calculateTotalRewardsForPeriod-uint256-uint256-uint256-}
Utility function to calculate total amount of rewards ready for distribution at a specific time


## Parameters:
- `_rewardAmountPerSecond`: Amount of reward token streamed per second

- `_lastDistributionTime`: Unix timestamp when last distribution happened

- `_blockTimestamp`: Specific time, must be greater than last distribution time


## Return Values:
- totalRewardsForPeriod Total reward token amount ready for distribution for passed period


# Function `calculatePoolRewardAmount(uint256 _poolTvl, uint256 _eligiblePoolsTvl, uint256 _rewardsToDistribute) → uint256 amount` {#RewardDistribution-calculatePoolRewardAmount-uint256-uint256-uint256-}
Utility function to calculate amount of rewards pool can receive


## Parameters:
- `_poolTvl`: Pool's total value

- `_eligiblePoolsTvl`: All eligible pools' total value

- `_rewardsToDistribute`: Total amount of reward token ready to be distributed


## Return Values:
- amount Reward token amount for a pool


# Function `calculateEligiblePoolsRewards() → struct RewardDistribution.RewardSummary[] rewards, uint256 totalRewardsToDistribute` {#RewardDistribution-calculateEligiblePoolsRewards--}
Prepares list of pools and their corresponding rewards



## Return Values:
- rewards List of entities (pool address and reward amount)

- totalRewardsToDistribute Total reward amount for distribution to eligible pools


# Function `getRewardsAPY() → uint256 apy` {#RewardDistribution-getRewardsAPY--}
Get APY figure from the rewards distribution



## Return Values:
- apy APY figure (can be multiplied by 100 to get value in percents)


# Function `distributeRewards()` {#RewardDistribution-distributeRewards--}
Function to be called by anyone, distributes amount of reward tokens available since last distribution





