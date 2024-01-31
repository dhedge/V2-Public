

# Functions:
- [`initialize(address _dhtAddress)`](#DhedgeStakingV2-initialize-address-)
- [`newStake(uint256 dhtAmount)`](#DhedgeStakingV2-newStake-uint256-)
- [`addDhtToStake(uint256 tokenId, uint256 dhtAmount)`](#DhedgeStakingV2-addDhtToStake-uint256-uint256-)
- [`unstakeDHT(uint256 tokenId, uint256 dhtAmount)`](#DhedgeStakingV2-unstakeDHT-uint256-uint256-)
- [`stakePoolTokens(uint256 tokenId, address dhedgePoolAddress, uint256 dhedgePoolAmount)`](#DhedgeStakingV2-stakePoolTokens-uint256-address-uint256-)
- [`unstakePoolTokens(uint256 tokenId)`](#DhedgeStakingV2-unstakePoolTokens-uint256-)
- [`claim(uint256 tokenId)`](#DhedgeStakingV2-claim-uint256-)
- [`globalVDHT()`](#DhedgeStakingV2-globalVDHT--)
- [`getStake(uint256 tokenId)`](#DhedgeStakingV2-getStake-uint256-)
- [`maxStakingValue()`](#DhedgeStakingV2-maxStakingValue--)
- [`getPoolConfiguration(address dhedgePoolAddress)`](#DhedgeStakingV2-getPoolConfiguration-address-)
- [`canClaimAmount(uint256 tokenId)`](#DhedgeStakingV2-canClaimAmount-uint256-)
- [`vDHTBalanceOf(address staker)`](#DhedgeStakingV2-vDHTBalanceOf-address-)
- [`vDHTBalanceOfStake(uint256 tokenId)`](#DhedgeStakingV2-vDHTBalanceOfStake-uint256-)
- [`dhtBalanceOf(address staker)`](#DhedgeStakingV2-dhtBalanceOf-address-)
- [`currentRewardsForStake(uint256 tokenId)`](#DhedgeStakingV2-currentRewardsForStake-uint256-)
- [`tokenURI(uint256 tokenId)`](#DhedgeStakingV2-tokenURI-uint256-)
- [`checkEnoughDht(uint256 claimAmount)`](#DhedgeStakingV2-checkEnoughDht-uint256-)

# Events:
- [`NewStake(uint256 tokenId, uint256 dhtAmount)`](#DhedgeStakingV2-NewStake-uint256-uint256-)
- [`AddDHTToStake(uint256 tokenId, uint256 dhtAmount)`](#DhedgeStakingV2-AddDHTToStake-uint256-uint256-)
- [`StakePoolTokens(uint256 tokenId, address dhedgePoolAddress, uint256 poolTokenAmount)`](#DhedgeStakingV2-StakePoolTokens-uint256-address-uint256-)
- [`UnstakePoolTokens(uint256 tokenId, uint256 newTokedId)`](#DhedgeStakingV2-UnstakePoolTokens-uint256-uint256-)
- [`UnstakeDHT(uint256 tokenId)`](#DhedgeStakingV2-UnstakeDHT-uint256-)
- [`Claim(uint256 tokenId, uint256 claimAmount)`](#DhedgeStakingV2-Claim-uint256-uint256-)


# Function `initialize(address _dhtAddress)` {#DhedgeStakingV2-initialize-address-}
No description




# Function `newStake(uint256 dhtAmount) → uint256 tokenId` {#DhedgeStakingV2-newStake-uint256-}
Create a new stake


## Parameters:
- `dhtAmount`: the amount of dht being staked


## Return Values:
- tokenId the erc721 tokenId


# Function `addDhtToStake(uint256 tokenId, uint256 dhtAmount)` {#DhedgeStakingV2-addDhtToStake-uint256-uint256-}
Add additional DHT


## Parameters:
- `tokenId`: the erc721 tokenId

- `dhtAmount`: the amount of dht being staked



# Function `unstakeDHT(uint256 tokenId, uint256 dhtAmount)` {#DhedgeStakingV2-unstakeDHT-uint256-uint256-}
Returns a users staked DHT and if empty burns the nft


## Parameters:
- `tokenId`: the tokenId that represents the Stake



# Function `stakePoolTokens(uint256 tokenId, address dhedgePoolAddress, uint256 dhedgePoolAmount)` {#DhedgeStakingV2-stakePoolTokens-uint256-address-uint256-}
No description

## Parameters:
- `dhedgePoolAddress`: the address of pool that is being staked

- `dhedgePoolAmount`: Amount of Pool tokens being staked



# Function `unstakePoolTokens(uint256 tokenId) → uint256 newTokenId` {#DhedgeStakingV2-unstakePoolTokens-uint256-}
Allows the user to unstake their dhedge pool tokens, when called will be allocated rewards at this point.


## Parameters:
- `tokenId`: The erc721 id of the existing stake


## Return Values:
- newTokenId the tokenId where the dht were zapped to.


# Function `claim(uint256 tokenId)` {#DhedgeStakingV2-claim-uint256-}
Used to claim rewards for an unstaked position


## Parameters:
- `tokenId`: the tokenId that represents the Stake that has been unstaked







# Function `globalVDHT() → uint256` {#DhedgeStakingV2-globalVDHT--}
No description










# Function `getStake(uint256 tokenId) → struct IDhedgeStakingV2Storage.Stake` {#DhedgeStakingV2-getStake-uint256-}
Allows getting stake info


## Parameters:
- `tokenId`: the erc721 id of the stake


## Return Values:
- stake the stake struct for the given tokenID


# Function `maxStakingValue() → uint256 maximumStakingValue` {#DhedgeStakingV2-maxStakingValue--}
Calculates the max amount of DHPT value that can be currently staked



## Return Values:
- maximumStakingValue The max amount of DHPT value that should currently be staked


# Function `getPoolConfiguration(address dhedgePoolAddress) → struct IDhedgeStakingV2Storage.PoolConfiguration` {#DhedgeStakingV2-getPoolConfiguration-address-}
Allows getting configuration of a pool


## Parameters:
- `dhedgePoolAddress`: the dhedge pool address to get the configuration for



# Function `canClaimAmount(uint256 tokenId) → uint256 claimAmount` {#DhedgeStakingV2-canClaimAmount-uint256-}
Returns the token holder amount can claim based on the time passed since they unstaked


## Parameters:
- `tokenId`: the tokenId that represents the Stake that has been unstaked


## Return Values:
- claimAmount the amount the staker can claim


# Function `vDHTBalanceOf(address staker) → uint256 vDHT` {#DhedgeStakingV2-vDHTBalanceOf-address-}
Returns the current vDHT of an address


## Parameters:
- `staker`: the stakers address


## Return Values:
- vDHT the current aggregate vDHT for the staker


# Function `vDHTBalanceOfStake(uint256 tokenId) → uint256 vDHT` {#DhedgeStakingV2-vDHTBalanceOfStake-uint256-}
Returns the current vDHT of a stake


## Parameters:
- `tokenId`: the id of the stake


## Return Values:
- vDHT the current vDHT for the given stake


# Function `dhtBalanceOf(address staker) → uint256 dht` {#DhedgeStakingV2-dhtBalanceOf-address-}
Returns the aggregate DHT staked of an address


## Parameters:
- `staker`: the stakers address


## Return Values:
- dht the current aggregate DHT for the address


# Function `currentRewardsForStake(uint256 tokenId) → uint256 rewardsDHT` {#DhedgeStakingV2-currentRewardsForStake-uint256-}
The rewards a stake would receive if unstaked now


## Parameters:
- `tokenId`: the id of the stake


## Return Values:
- rewardsDHT the current aggregate DHT for the address


# Function `tokenURI(uint256 tokenId) → string` {#DhedgeStakingV2-tokenURI-uint256-}
No description










# Function `checkEnoughDht(uint256 claimAmount)` {#DhedgeStakingV2-checkEnoughDht-uint256-}
Check here we don't distribute any staked DHT as rewards


## Parameters:
- `claimAmount`: the amount of dht attempting to be claimed



