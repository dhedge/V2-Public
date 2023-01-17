

# Functions:
- [`initialize(address _poolFactory)`](#DhedgeNftTrackerStorage-initialize-address-)
- [`implInitializer()`](#DhedgeNftTrackerStorage-implInitializer--)
- [`addData(address _guardedContract, bytes32 _nftType, address _pool, bytes _data)`](#DhedgeNftTrackerStorage-addData-address-bytes32-address-bytes-)
- [`removeData(address _guardedContract, bytes32 _nftType, address _pool, uint256 _index)`](#DhedgeNftTrackerStorage-removeData-address-bytes32-address-uint256-)
- [`getData(bytes32 _nftType, address _pool, uint256 _index)`](#DhedgeNftTrackerStorage-getData-bytes32-address-uint256-)
- [`getAllData(bytes32 _nftType, address _pool)`](#DhedgeNftTrackerStorage-getAllData-bytes32-address-)
- [`getDataCount(bytes32 _nftType, address _pool)`](#DhedgeNftTrackerStorage-getDataCount-bytes32-address-)



# Function `initialize(address _poolFactory)` {#DhedgeNftTrackerStorage-initialize-address-}
No description




# Function `implInitializer()` {#DhedgeNftTrackerStorage-implInitializer--}
implementations should not be left unintialized




# Function `addData(address _guardedContract, bytes32 _nftType, address _pool, bytes _data)` {#DhedgeNftTrackerStorage-addData-address-bytes32-address-bytes-}
record new NFT data


## Parameters:
- `_nftType`: keccak of NFT_TYPE

- `_pool`: the poolLogic address

- `_data`: the nft track data to be recorded in storage



# Function `removeData(address _guardedContract, bytes32 _nftType, address _pool, uint256 _index)` {#DhedgeNftTrackerStorage-removeData-address-bytes32-address-uint256-}
delete NFT data


## Parameters:
- `_nftType`: keccak of NFT_TYPE

- `_pool`: the poolLogic address

- `_index`: the nft track data index to be removed from storage



# Function `getData(bytes32 _nftType, address _pool, uint256 _index) → bytes` {#DhedgeNftTrackerStorage-getData-bytes32-address-uint256-}
returns tracked nft by index


## Parameters:
- `_nftType`: keccak of NFT_TYPE

- `_pool`: the poolLogic address

- `_index`: the index of nft track data


## Return Values:
- data the nft track data of given NFT_TYPE & poolLogic & index


# Function `getAllData(bytes32 _nftType, address _pool) → bytes[]` {#DhedgeNftTrackerStorage-getAllData-bytes32-address-}
returns all tracked nfts by NFT_TYPE & poolLogic


## Parameters:
- `_nftType`: keccak of NFT_TYPE

- `_pool`: the poolLogic address


## Return Values:
- data all tracked nfts of given NFT_TYPE & poolLogic


# Function `getDataCount(bytes32 _nftType, address _pool) → uint256` {#DhedgeNftTrackerStorage-getDataCount-bytes32-address-}
returns all tracked nfts by NFT_TYPE & poolLogic


## Parameters:
- `_nftType`: keccak of NFT_TYPE

- `_pool`: the poolLogic address


## Return Values:
- count all tracked nfts count of given NFT_TYPE & poolLogic


