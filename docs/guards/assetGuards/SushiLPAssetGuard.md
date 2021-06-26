## `SushiLPAssetGuard`



Asset type = 2


### `constructor(address _sushiStaking, struct SushiLPAssetGuard.SushiPool[] sushiPools)` (public)





### `getWithdrawStakedTx(address pool, address asset, uint256 withdrawPortion, address to) → address stakingContract, bytes txData` (external)

Creates transaction data for withdrawing staked tokens


The same interface can be used for other types of stakeable tokens


### `getBalance(address pool, address asset) → uint256 balance` (external)

Returns the balance of the managed asset


May include any external balance in staking contracts


### `WithdrawStaked(address fundAddress, address asset, address to, uint256 withdrawAmount, uint256 time)`





