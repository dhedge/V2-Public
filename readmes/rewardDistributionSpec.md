# Reward Distribution Contract Spec

The idea of this contract is to hold a tranche of OP rewards and the logic to calculate and distribute those awards to participating pools. A public function would be called approximately every 24hours.

## Storage

- address rewardsToken (eg OP)
- address[] participatingPools
- uint lastDistributionTime
- rewardsPerSecond (how much OP per second)

## Public Functions

- distributeRewards()
This function can keep being called until the rewards added to the contract run out.
Calls _getRewardsPerPool() and _distributeRewards()
Ideally we would have a keeper setup that calls this function every 24 hours.

- getTotalTvl() returns (uint) - This loops through all participating pools and using their `totalFundValue` function and aggregates the value

- getRewardForPool(totalTvl, poolFundValue) returns (rewardAmount)
math.min(balanceOfContract, rewardsPerSecond * (lastDistributionTime - currentTime) * poolFundValue / totalTvl

## Owner Only Functions

- setRewardsPerSecond returns (bool) - This sets the reward token distribution rate per second.

- setParticipatingPools returns (bool) - This sets the pools participating in the rewards distribution. Can be used for adding or removing pools as necessary.

## Private Functions

- _getRewardsPerPool returns ({poolAddress, rewardAmount}[]) - calls calculateTotalTvl() and getRewardForPool() and creates the return array

- _distributeRewards({poolAddress, rewardAmount}[]) - for each record transfers the rewardAmount to the poolAddress and updates lastDistribution to current timestamp.
