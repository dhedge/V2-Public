

# Functions:
- [`txGuard(address _poolManagerLogic, address, bytes data)`](#ERC721ContractGuard-txGuard-address-address-bytes-)

# Events:
- [`Approve(address fundAddress, address manager, address spender, uint256 tokenId, uint256 time)`](#ERC721ContractGuard-Approve-address-address-address-uint256-uint256-)
- [`ApproveForAll(address fundAddress, address manager, address spender, bool approved, uint256 time)`](#ERC721ContractGuard-ApproveForAll-address-address-address-bool-uint256-)


# Function `txGuard(address _poolManagerLogic, address, bytes data) → uint16 txType, bool` {#ERC721ContractGuard-txGuard-address-address-bytes-}
Transaction guard for approving assets


## Parameters:
- `_poolManagerLogic`: Pool address

- `data`: Transaction call data attempt by manager


## Return Values:
- txType transaction type described in PoolLogic

- isPublic if the transaction is public or private


