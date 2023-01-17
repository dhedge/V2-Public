

# Functions:
- [`tokenJson(uint256 tokenId, struct IDhedgeStakingV2Storage.Stake stake, uint256 vDHT, uint256 rewards, string poolSymbol, uint256 currentTokenPrice, address dhtAddress, address owner)`](#DhedgeStakingV2NFTJson-tokenJson-uint256-struct-IDhedgeStakingV2Storage-Stake-uint256-uint256-string-uint256-address-address-)
- [`addressToString(address _addr)`](#DhedgeStakingV2NFTJson-addressToString-address-)
- [`substring(string str, uint256 startIndex, uint256 endIndex)`](#DhedgeStakingV2NFTJson-substring-string-uint256-uint256-)



# Function `tokenJson(uint256 tokenId, struct IDhedgeStakingV2Storage.Stake stake, uint256 vDHT, uint256 rewards, string poolSymbol, uint256 currentTokenPrice, address dhtAddress, address owner) → string` {#DhedgeStakingV2NFTJson-tokenJson-uint256-struct-IDhedgeStakingV2Storage-Stake-uint256-uint256-string-uint256-address-address-}
Generates the tokenUri base64 including the svg


## Parameters:
- `tokenId`: the erc721 tokenId

- `stake`: the stake struct

- `vDHT`: the amount of accrued vdht for the stake

- `rewards`: the amount of rewards accrued for the stake

- `poolSymbol`: the symbol of the staked pool tokens

- `currentTokenPrice`: the price of the pool tokens staked

- `dhtAddress`: the address of dht

- `owner`: the owner of the stake


## Return Values:
- tokenJson base64 encoded json payload




# Function `addressToString(address _addr) → string` {#DhedgeStakingV2NFTJson-addressToString-address-}
No description






# Function `substring(string str, uint256 startIndex, uint256 endIndex) → string` {#DhedgeStakingV2NFTJson-substring-string-uint256-uint256-}
No description




