

# Functions:
- [`constructor(address _rewardToken)`](#AaveIncentivesControllerGuard-constructor-address-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#AaveIncentivesControllerGuard-txGuard-address-address-bytes-)

# Events:
- [`Claim(address fundAddress, address stakingContract, uint256 time)`](#AaveIncentivesControllerGuard-Claim-address-address-uint256-)


# Function `constructor(address _rewardToken)` {#AaveIncentivesControllerGuard-constructor-address-}
No description




# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType` {#AaveIncentivesControllerGuard-txGuard-address-address-bytes-}
Transaction guard for Aave incentives controller


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type


