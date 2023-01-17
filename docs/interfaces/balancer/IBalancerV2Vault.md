

# Functions:
- [`getPool(bytes32 poolId)`](#IBalancerV2Vault-getPool-bytes32-)
- [`swap(struct IBalancerV2Vault.SingleSwap singleSwap, struct IBalancerV2Vault.FundManagement funds, uint256 limit, uint256 deadline)`](#IBalancerV2Vault-swap-struct-IBalancerV2Vault-SingleSwap-struct-IBalancerV2Vault-FundManagement-uint256-uint256-)
- [`batchSwap(enum IBalancerV2Vault.SwapKind kind, struct IBalancerV2Vault.BatchSwapStep[] swaps, address[] assets, struct IBalancerV2Vault.FundManagement funds, int256[] limits, uint256 deadline)`](#IBalancerV2Vault-batchSwap-enum-IBalancerV2Vault-SwapKind-struct-IBalancerV2Vault-BatchSwapStep---address---struct-IBalancerV2Vault-FundManagement-int256---uint256-)
- [`joinPool(bytes32 poolId, address sender, address recipient, struct IBalancerV2Vault.JoinPoolRequest request)`](#IBalancerV2Vault-joinPool-bytes32-address-address-struct-IBalancerV2Vault-JoinPoolRequest-)
- [`exitPool(bytes32 poolId, address sender, address payable recipient, struct IBalancerV2Vault.ExitPoolRequest request)`](#IBalancerV2Vault-exitPool-bytes32-address-address-payable-struct-IBalancerV2Vault-ExitPoolRequest-)
- [`getPoolTokens(bytes32 poolId)`](#IBalancerV2Vault-getPoolTokens-bytes32-)



# Function `getPool(bytes32 poolId) → address pool` {#IBalancerV2Vault-getPool-bytes32-}
No description




# Function `swap(struct IBalancerV2Vault.SingleSwap singleSwap, struct IBalancerV2Vault.FundManagement funds, uint256 limit, uint256 deadline) → uint256 amountCalculated` {#IBalancerV2Vault-swap-struct-IBalancerV2Vault-SingleSwap-struct-IBalancerV2Vault-FundManagement-uint256-uint256-}
No description




# Function `batchSwap(enum IBalancerV2Vault.SwapKind kind, struct IBalancerV2Vault.BatchSwapStep[] swaps, address[] assets, struct IBalancerV2Vault.FundManagement funds, int256[] limits, uint256 deadline) → int256[]` {#IBalancerV2Vault-batchSwap-enum-IBalancerV2Vault-SwapKind-struct-IBalancerV2Vault-BatchSwapStep---address---struct-IBalancerV2Vault-FundManagement-int256---uint256-}
No description




# Function `joinPool(bytes32 poolId, address sender, address recipient, struct IBalancerV2Vault.JoinPoolRequest request)` {#IBalancerV2Vault-joinPool-bytes32-address-address-struct-IBalancerV2Vault-JoinPoolRequest-}
No description




# Function `exitPool(bytes32 poolId, address sender, address payable recipient, struct IBalancerV2Vault.ExitPoolRequest request)` {#IBalancerV2Vault-exitPool-bytes32-address-address-payable-struct-IBalancerV2Vault-ExitPoolRequest-}
No description




# Function `getPoolTokens(bytes32 poolId) → address[] tokens, uint256[] balances, uint256 lastChangeBlock` {#IBalancerV2Vault-getPoolTokens-bytes32-}
No description




