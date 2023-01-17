

# Functions:
- [`newStake(uint256 dhtAmount)`](#IDhedgeStakingV2-newStake-uint256-)
- [`addDhtToStake(uint256 tokenId, uint256 dhtAmount)`](#IDhedgeStakingV2-addDhtToStake-uint256-uint256-)
- [`unstakeDHT(uint256 tokenId, uint256 dhtAmount)`](#IDhedgeStakingV2-unstakeDHT-uint256-uint256-)
- [`stakePoolTokens(uint256 tokenId, address dhedgePoolAddress, uint256 dhedgePoolAmount)`](#IDhedgeStakingV2-stakePoolTokens-uint256-address-uint256-)
- [`unstakePoolTokens(uint256 tokenId)`](#IDhedgeStakingV2-unstakePoolTokens-uint256-)
- [`claim(uint256 tokenId)`](#IDhedgeStakingV2-claim-uint256-)
- [`canClaimAmount(uint256 tokenId)`](#IDhedgeStakingV2-canClaimAmount-uint256-)
- [`dhtBalanceOf(address staker)`](#IDhedgeStakingV2-dhtBalanceOf-address-)
- [`vDHTBalanceOf(address staker)`](#IDhedgeStakingV2-vDHTBalanceOf-address-)
- [`vDHTBalanceOfStake(uint256 tokenId)`](#IDhedgeStakingV2-vDHTBalanceOfStake-uint256-)
- [`getPoolConfiguration(address poolAddress)`](#IDhedgeStakingV2-getPoolConfiguration-address-)
- [`getStake(uint256 tokenId)`](#IDhedgeStakingV2-getStake-uint256-)
- [`currentRewardsForStake(uint256 tokenId)`](#IDhedgeStakingV2-currentRewardsForStake-uint256-)



# Function `newStake(uint256 dhtAmount) → uint256 tokenId` {#IDhedgeStakingV2-newStake-uint256-}
Create a new stake with DHT


## Parameters:
- `dhtAmount`: the amount of dht being staked



# Function `addDhtToStake(uint256 tokenId, uint256 dhtAmount)` {#IDhedgeStakingV2-addDhtToStake-uint256-uint256-}
Allows the user to add addtional amount of DHT to an existing stake


## Parameters:
- `tokenId`: The erc721 id of the existing stake

- `dhtAmount`: the amount of additional dht to be staked



# Function `unstakeDHT(uint256 tokenId, uint256 dhtAmount)` {#IDhedgeStakingV2-unstakeDHT-uint256-uint256-}
Allows the user to unstake all or some of their dht from a given stake


## Parameters:
- `tokenId`: The erc721 id of the existing stake

- `dhtAmount`: the amount of dht they want to unstaked



# Function `stakePoolTokens(uint256 tokenId, address dhedgePoolAddress, uint256 dhedgePoolAmount)` {#IDhedgeStakingV2-stakePoolTokens-uint256-address-uint256-}
Allows the user to stake dhedge pool tokens with an existing DHT Stake


## Parameters:
- `tokenId`: The erc721 id of the existing stake

- `dhedgePoolAddress`: the address of the pool being staked

- `dhedgePoolAmount`: the amount of pool tokens being staked



# Function `unstakePoolTokens(uint256 tokenId) → uint256 newTokenId` {#IDhedgeStakingV2-unstakePoolTokens-uint256-}
Allows the user to unstake their dhedge pool tokens, when called will be allocated rewards at this point.


## Parameters:
- `tokenId`: The erc721 id of the existing stake


## Return Values:
- newTokenId the tokenId where the dht were zapped to.


# Function `claim(uint256 tokenId)` {#IDhedgeStakingV2-claim-uint256-}
Allows the user to claim their unlocked rewards for a given stake. The rewards are unlocked over rewardStreamingTime


## Parameters:
- `tokenId`: The erc721 id of the existing stake



# Function `canClaimAmount(uint256 tokenId) → uint256` {#IDhedgeStakingV2-canClaimAmount-uint256-}
Returns the amount of rewards unlocked so far for a given stake


## Parameters:
- `tokenId`: The erc721 id of the existing stake



# Function `dhtBalanceOf(address staker) → uint256 dht` {#IDhedgeStakingV2-dhtBalanceOf-address-}
The aggregate DHT balance of the wallet


## Parameters:
- `staker`: The the wallet



# Function `vDHTBalanceOf(address staker) → uint256 vDHT` {#IDhedgeStakingV2-vDHTBalanceOf-address-}
The aggregate vDHT balance of the wallet


## Parameters:
- `staker`: The the wallet


## Return Values:
- vDHT the current vDHT for the given wallet


# Function `vDHTBalanceOfStake(uint256 tokenId) → uint256 vDHT` {#IDhedgeStakingV2-vDHTBalanceOfStake-uint256-}
Returns the current vDHT of a stake


## Parameters:
- `tokenId`: the id of the stake


## Return Values:
- vDHT the current vDHT for the given stake


# Function `getPoolConfiguration(address poolAddress) → struct IDhedgeStakingV2Storage.PoolConfiguration` {#IDhedgeStakingV2-getPoolConfiguration-address-}
Allows getting configuration of a pool


## Parameters:
- `poolAddress`: the dhedge pool address to get the configuration for


## Return Values:
- poolConfiguration the configuration for the given pool


# Function `getStake(uint256 tokenId) → struct IDhedgeStakingV2Storage.Stake` {#IDhedgeStakingV2-getStake-uint256-}
Allows getting stake info


## Parameters:
- `tokenId`: the erc721 id of the stake


## Return Values:
- stake the stake struct for the given tokenID


# Function `currentRewardsForStake(uint256 tokenId) → uint256 rewardsDHT` {#IDhedgeStakingV2-currentRewardsForStake-uint256-}
The rewards a staker would receive if they unstaked now


## Parameters:
- `tokenId`: the id of the stake


## Return Values:
- rewardsDHT the current aggregate DHT for the address


