

# Functions:
- [`initialize(address _poolFactory)`](#DhedgeNftTrackerStorage-initialize-address-)
- [`addData(address _guardedContract, bytes32 _nftType, address _pool, bytes _data)`](#DhedgeNftTrackerStorage-addData-address-bytes32-address-bytes-)
- [`removeData(address _guardedContract, bytes32 _nftType, address _pool, uint256 _index)`](#DhedgeNftTrackerStorage-removeData-address-bytes32-address-uint256-)
- [`getData(bytes32 _nftType, address _pool, uint256 _index)`](#DhedgeNftTrackerStorage-getData-bytes32-address-uint256-)
- [`getAllData(bytes32 _nftType, address _pool)`](#DhedgeNftTrackerStorage-getAllData-bytes32-address-)
- [`getDataCount(bytes32 _nftType, address _pool)`](#DhedgeNftTrackerStorage-getDataCount-bytes32-address-)
- [`getAllUintIds(bytes32 _nftType, address _pool)`](#DhedgeNftTrackerStorage-getAllUintIds-bytes32-address-)
- [`addUintId(address _guardedContract, bytes32 _nftType, address _pool, uint256 _nftID, uint256 _maxPositions)`](#DhedgeNftTrackerStorage-addUintId-address-bytes32-address-uint256-uint256-)
- [`removeUintId(address _guardedContract, bytes32 _nftType, address _pool, uint256 _nftID)`](#DhedgeNftTrackerStorage-removeUintId-address-bytes32-address-uint256-)
- [`removeDataByUintId(bytes32 _nftType, address _pool, uint256 _nftID)`](#DhedgeNftTrackerStorage-removeDataByUintId-bytes32-address-uint256-)
- [`removeDataByIndex(bytes32 _nftType, address _pool, uint256 _index)`](#DhedgeNftTrackerStorage-removeDataByIndex-bytes32-address-uint256-)
- [`addDataByUintId(bytes32 _nftType, address _pool, uint256 _nftID)`](#DhedgeNftTrackerStorage-addDataByUintId-bytes32-address-uint256-)



# Function `initialize(address _poolFactory)` {#DhedgeNftTrackerStorage-initialize-address-}
No description




# Function `addData(address _guardedContract, bytes32 _nftType, address _pool, bytes _data)` {#DhedgeNftTrackerStorage-addData-address-bytes32-address-bytes-}
record new NFT data


## Parameters:
- `_guardedContract`: the address of contract using nftStorage

- `_nftType`: keccak of NFT_TYPE

- `_pool`: the poolLogic address

- `_data`: the nft track data to be recorded in storage



# Function `removeData(address _guardedContract, bytes32 _nftType, address _pool, uint256 _index)` {#DhedgeNftTrackerStorage-removeData-address-bytes32-address-uint256-}
delete NFT data


## Parameters:
- `_guardedContract`: the address of contract using nftStorage

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


# Function `getAllUintIds(bytes32 _nftType, address _pool) → uint256[] tokenIds` {#DhedgeNftTrackerStorage-getAllUintIds-bytes32-address-}
returns all tracked nft ids by NFT_TYPE & poolLogic if stored as uint256


## Parameters:
- `_nftType`: keccak of NFT_TYPE

- `_pool`: the poolLogic address


## Return Values:
- tokenIds all tracked nfts of given NFT_TYPE & poolLogic


# Function `addUintId(address _guardedContract, bytes32 _nftType, address _pool, uint256 _nftID, uint256 _maxPositions)` {#DhedgeNftTrackerStorage-addUintId-address-bytes32-address-uint256-uint256-}
record new NFT uint256 id


## Parameters:
- `_guardedContract`: the address of contract using nftStorage

- `_nftType`: keccak of NFT_TYPE

- `_pool`: the poolLogic address

- `_nftID`: the nft id recorded in storage



# Function `removeUintId(address _guardedContract, bytes32 _nftType, address _pool, uint256 _nftID)` {#DhedgeNftTrackerStorage-removeUintId-address-bytes32-address-uint256-}
record new NFT uint256 id


## Parameters:
- `_guardedContract`: the address of contract using nftStorage

- `_nftType`: keccak of NFT_TYPE

- `_pool`: the poolLogic address

- `_nftID`: the nft id recorded in storage



# Function `removeDataByUintId(bytes32 _nftType, address _pool, uint256 _nftID)` {#DhedgeNftTrackerStorage-removeDataByUintId-bytes32-address-uint256-}
No description




# Function `removeDataByIndex(bytes32 _nftType, address _pool, uint256 _index)` {#DhedgeNftTrackerStorage-removeDataByIndex-bytes32-address-uint256-}
No description




# Function `addDataByUintId(bytes32 _nftType, address _pool, uint256 _nftID)` {#DhedgeNftTrackerStorage-addDataByUintId-bytes32-address-uint256-}
No description




