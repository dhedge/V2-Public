

# Functions:
- [`constructor(address _collateral, uint128 _allowedLiquidityPoolId, address _snxUSD, address _nftTracker, address[] _whitelisteddHedgeVaults)`](#SynthetixV3ContractGuard-constructor-address-uint128-address-address-address---)
- [`getAccountNftTokenId(address _poolLogic, address _to)`](#SynthetixV3ContractGuard-getAccountNftTokenId-address-address-)
- [`txGuard(address _poolManagerLogic, address _to, bytes _data)`](#SynthetixV3ContractGuard-txGuard-address-address-bytes-)
- [`verifyERC721(address, address from, uint256, bytes)`](#SynthetixV3ContractGuard-verifyERC721-address-address-uint256-bytes-)
- [`afterTxGuard(address _poolManagerLogic, address _to, bytes _data)`](#SynthetixV3ContractGuard-afterTxGuard-address-address-bytes-)

# Events:
- [`SynthetixV3Event(address poolLogic, uint256 txType)`](#SynthetixV3ContractGuard-SynthetixV3Event-address-uint256-)


# Function `constructor(address _collateral, uint128 _allowedLiquidityPoolId, address _snxUSD, address _nftTracker, address[] _whitelisteddHedgeVaults)` {#SynthetixV3ContractGuard-constructor-address-uint128-address-address-address---}
No description

## Parameters:
- `_collateral`: Synthetix V3 collateral address we are going to support

- `_allowedLiquidityPoolId`: Synthetix V3 liquidity pool ID we are going to support

- `_snxUSD`: Synthetix V3 snxUSD address

- `_nftTracker`: dHEDGE system NFT tracker contract address

- `_whitelisteddHedgeVaults`: dHEDGE vaults that are allowed to use Synthetix V3



# Function `getAccountNftTokenId(address _poolLogic, address _to) → uint128 tokenId` {#SynthetixV3ContractGuard-getAccountNftTokenId-address-address-}
Returns Synthetix Account NFT ID associated with the pool stored in dHEDGE NFT Tracker contract


## Parameters:
- `_poolLogic`: Pool address

- `_to`: Synthetix V3 Core address


## Return Values:
- tokenId Synthetix Account NFT ID


# Function `txGuard(address _poolManagerLogic, address _to, bytes _data) → uint16 txType, bool` {#SynthetixV3ContractGuard-txGuard-address-address-bytes-}
Transaction guard for Synthetix V3


## Parameters:
- `_poolManagerLogic`: Pool manager logic address

- `_to`: Synthetix V3 Core address

- `_data`: Transaction data


## Return Values:
- txType Transaction type

- isPublic If the transaction is public or private


# Function `verifyERC721(address, address from, uint256, bytes) → bool verified` {#SynthetixV3ContractGuard-verifyERC721-address-address-uint256-bytes-}
No description






# Function `afterTxGuard(address _poolManagerLogic, address _to, bytes _data)` {#SynthetixV3ContractGuard-afterTxGuard-address-address-bytes-}
No description

## Parameters:
- `_poolManagerLogic`: Pool manager logic address

- `_to`: Synthetix V3 Core address

- `_data`: Transaction data







