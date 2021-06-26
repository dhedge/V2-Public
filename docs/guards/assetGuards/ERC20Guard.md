## `ERC20Guard`



Asset type = 0
A generic ERC20 guard asset is Not stakeable ie. no 'getWithdrawStakedTx()' function


### `txGuard(address _poolManagerLogic, address, bytes data) → uint8 txType` (external)

Transaction guard for approving assets


Parses the manager transaction data to ensure transaction is valid


### `getWithdrawStakedTx(address, address, uint256, address) → address stakingContract, bytes txData` (external)

Creates transaction data for withdrawing staked tokens


Withdrawal processing is not applicable for this guard


### `getBalance(address pool, address asset) → uint256 balance` (external)

Returns the balance of the managed asset


May include any external balance in staking contracts


### `Approve(address fundAddress, address manager, address spender, uint256 amount, uint256 time)`





