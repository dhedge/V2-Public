

# Functions:
- [`balanceOf(address user)`](#IVelodromeV2Gauge-balanceOf-address-)
- [`rewardPerToken()`](#IVelodromeV2Gauge-rewardPerToken--)
- [`lastTimeRewardApplicable()`](#IVelodromeV2Gauge-lastTimeRewardApplicable--)
- [`earned(address _account)`](#IVelodromeV2Gauge-earned-address-)
- [`left()`](#IVelodromeV2Gauge-left--)
- [`isPool()`](#IVelodromeV2Gauge-isPool--)
- [`stakingToken()`](#IVelodromeV2Gauge-stakingToken--)
- [`rewardToken()`](#IVelodromeV2Gauge-rewardToken--)
- [`getReward(address _account)`](#IVelodromeV2Gauge-getReward-address-)
- [`deposit(uint256 _amount)`](#IVelodromeV2Gauge-deposit-uint256-)
- [`deposit(uint256 _amount, address _recipient)`](#IVelodromeV2Gauge-deposit-uint256-address-)
- [`withdraw(uint256 _amount)`](#IVelodromeV2Gauge-withdraw-uint256-)
- [`notifyRewardAmount(uint256 amount)`](#IVelodromeV2Gauge-notifyRewardAmount-uint256-)



# Function `balanceOf(address user) → uint256` {#IVelodromeV2Gauge-balanceOf-address-}
No description




# Function `rewardPerToken() → uint256 _rewardPerToken` {#IVelodromeV2Gauge-rewardPerToken--}
No description




# Function `lastTimeRewardApplicable() → uint256 _time` {#IVelodromeV2Gauge-lastTimeRewardApplicable--}
Returns the last time the reward was modified or periodFinish if the reward has ended




# Function `earned(address _account) → uint256 _earned` {#IVelodromeV2Gauge-earned-address-}
Returns accrued balance to date from last claim / first deposit.




# Function `left() → uint256 _left` {#IVelodromeV2Gauge-left--}
No description




# Function `isPool() → bool _isPool` {#IVelodromeV2Gauge-isPool--}
Returns if gauge is linked to a legitimate Velodrome pool




# Function `stakingToken() → address _pool` {#IVelodromeV2Gauge-stakingToken--}
No description




# Function `rewardToken() → address _token` {#IVelodromeV2Gauge-rewardToken--}
No description




# Function `getReward(address _account)` {#IVelodromeV2Gauge-getReward-address-}
Retrieve rewards for an address.


## Parameters:
- `_account`: .



# Function `deposit(uint256 _amount)` {#IVelodromeV2Gauge-deposit-uint256-}
Deposit LP tokens into gauge for msg.sender


## Parameters:
- `_amount`: .



# Function `deposit(uint256 _amount, address _recipient)` {#IVelodromeV2Gauge-deposit-uint256-address-}
Deposit LP tokens into gauge for any user


## Parameters:
- `_amount`: .

- `_recipient`: Recipient to give balance to



# Function `withdraw(uint256 _amount)` {#IVelodromeV2Gauge-withdraw-uint256-}
Withdraw LP tokens for user


## Parameters:
- `_amount`: .



# Function `notifyRewardAmount(uint256 amount)` {#IVelodromeV2Gauge-notifyRewardAmount-uint256-}
No description




