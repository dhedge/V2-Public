

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#AaveIncentivesControllerV3Guard-txGuard-address-address-bytes-)

# Events:
- [`Claim(address fundAddress, address stakingContract, uint256 time)`](#AaveIncentivesControllerV3Guard-Claim-address-address-uint256-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType, bool isPublic` {#AaveIncentivesControllerV3Guard-txGuard-address-address-bytes-}
Transaction guard for Aave incentives v3 RewardController


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data

- isPublic if the transaction is public or private


