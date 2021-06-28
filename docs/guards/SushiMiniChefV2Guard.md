

# Functions:
- [`constructor(address _rewardTokenA, address _rewardTokenB)`](#SushiMiniChefV2Guard-constructor-address-address-)
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#SushiMiniChefV2Guard-txGuard-address-address-bytes-)

# Events:
- [`Stake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time)`](#SushiMiniChefV2Guard-Stake-address-address-address-uint256-uint256-)
- [`Unstake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time)`](#SushiMiniChefV2Guard-Unstake-address-address-address-uint256-uint256-)
- [`Claim(address fundAddress, address stakingContract, uint256 time)`](#SushiMiniChefV2Guard-Claim-address-address-uint256-)

# Function `constructor(address _rewardTokenA, address _rewardTokenB)` {#SushiMiniChefV2Guard-constructor-address-address-}
No description
# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint8 txType` {#SushiMiniChefV2Guard-txGuard-address-address-bytes-}
It supports deposit, withdraw, harvest, withdrawAndHarvest functionalities

## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `to`: The contract to send transaction to

- `data`: The transaction data

## Return Values:
- txType the transaction type of a given transaction data. 5 for `Stake` type, 6 for `Unstake`, 7 for `Claim`, 8 for `UnstakeAndClaim`

# Event `Stake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time)` {#SushiMiniChefV2Guard-Stake-address-address-address-uint256-uint256-}
No description
# Event `Unstake(address fundAddress, address asset, address stakingContract, uint256 amount, uint256 time)` {#SushiMiniChefV2Guard-Unstake-address-address-address-uint256-uint256-}
No description
# Event `Claim(address fundAddress, address stakingContract, uint256 time)` {#SushiMiniChefV2Guard-Claim-address-address-uint256-}
No description
