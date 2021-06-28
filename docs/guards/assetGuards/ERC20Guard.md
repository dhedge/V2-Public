Asset type = 0
A generic ERC20 guard asset is Not stakeable ie. no 'getWithdrawStakedTx()' function

# Functions:
- [`txGuard(address _poolManagerLogic, address, bytes data)`](#ERC20Guard-txGuard-address-address-bytes-)
- [`getWithdrawStakedTx(address, address, uint256, address)`](#ERC20Guard-getWithdrawStakedTx-address-address-uint256-address-)
- [`getBalance(address pool, address asset)`](#ERC20Guard-getBalance-address-address-)

# Events:
- [`Approve(address fundAddress, address manager, address spender, uint256 amount, uint256 time)`](#ERC20Guard-Approve-address-address-address-uint256-uint256-)

# Function `txGuard(address _poolManagerLogic, address, bytes data) → uint8 txType` {#ERC20Guard-txGuard-address-address-bytes-}
Parses the manager transaction data to ensure transaction is valid

## Parameters:
- `_poolManagerLogic`: Pool address

- `data`: Transaction call data attempt by manager

## Return Values:
- txType transaction type described in PoolLogic
# Function `getWithdrawStakedTx(address, address, uint256, address) → address stakingContract, bytes txData` {#ERC20Guard-getWithdrawStakedTx-address-address-uint256-address-}
Withdrawal processing is not applicable for this guard

## Return Values:
- stakingContract and txData are used to execute the staked withdrawal transaction in PoolLogic
# Function `getBalance(address pool, address asset) → uint256 balance` {#ERC20Guard-getBalance-address-address-}
May include any external balance in staking contracts

# Event `Approve(address fundAddress, address manager, address spender, uint256 amount, uint256 time)` {#ERC20Guard-Approve-address-address-address-uint256-uint256-}
No description
