

# Functions:
- [`configurePool(address pool, uint256 cap)`](#IDhedgeStakingV2Storage-configurePool-address-uint256-)
- [`setDHTCap(uint256 newDHTCap)`](#IDhedgeStakingV2Storage-setDHTCap-uint256-)
- [`setMaxVDurationTimeSeconds(uint256 newMaxVDurationTimeSeconds)`](#IDhedgeStakingV2Storage-setMaxVDurationTimeSeconds-uint256-)
- [`setStakeDurationDelaySeconds(uint256 newStakeDurationDelaySeconds)`](#IDhedgeStakingV2Storage-setStakeDurationDelaySeconds-uint256-)
- [`setMaxDurationBoostSeconds(uint256 newMaxDurationBoostSeconds)`](#IDhedgeStakingV2Storage-setMaxDurationBoostSeconds-uint256-)
- [`setMaxPerformanceBoostNumerator(uint256 newMaxPerformanceBoostNumerator)`](#IDhedgeStakingV2Storage-setMaxPerformanceBoostNumerator-uint256-)
- [`setStakingRatio(uint256 newStakingRatio)`](#IDhedgeStakingV2Storage-setStakingRatio-uint256-)
- [`setEmissionsRate(uint256 newEmissionsRate)`](#IDhedgeStakingV2Storage-setEmissionsRate-uint256-)
- [`setRewardStreamingTime(uint256 newRewardStreamingTime)`](#IDhedgeStakingV2Storage-setRewardStreamingTime-uint256-)
- [`dhtAddress()`](#IDhedgeStakingV2Storage-dhtAddress--)
- [`numberOfPoolsConfigured()`](#IDhedgeStakingV2Storage-numberOfPoolsConfigured--)
- [`poolConfiguredByIndex(uint256 index)`](#IDhedgeStakingV2Storage-poolConfiguredByIndex-uint256-)
- [`setTokenUriGenerator(contract IDhedgeStakingV2NFTJson newTokenUriGenerator)`](#IDhedgeStakingV2Storage-setTokenUriGenerator-contract-IDhedgeStakingV2NFTJson-)



# Function `configurePool(address pool, uint256 cap)` {#IDhedgeStakingV2Storage-configurePool-address-uint256-}
Allows the owner to allow staking of a pool by setting a cap > 0





# Function `setDHTCap(uint256 newDHTCap)` {#IDhedgeStakingV2Storage-setDHTCap-uint256-}
Allows the owner to modify the dhtCap which controls the max staking value





# Function `setMaxVDurationTimeSeconds(uint256 newMaxVDurationTimeSeconds)` {#IDhedgeStakingV2Storage-setMaxVDurationTimeSeconds-uint256-}
Allows the owner to adjust the maxVDurationTimeSeconds


## Parameters:
- `newMaxVDurationTimeSeconds`: time to reach max VHDT for a staker



# Function `setStakeDurationDelaySeconds(uint256 newStakeDurationDelaySeconds)` {#IDhedgeStakingV2Storage-setStakeDurationDelaySeconds-uint256-}
Allows the owner to adjust the setStakeDurationDelaySeconds


## Parameters:
- `newStakeDurationDelaySeconds`: delay before a staker starts to receive rewards



# Function `setMaxDurationBoostSeconds(uint256 newMaxDurationBoostSeconds)` {#IDhedgeStakingV2Storage-setMaxDurationBoostSeconds-uint256-}
Allows the owner to adjust the maxDurationBoostSeconds


## Parameters:
- `newMaxDurationBoostSeconds`: time to reach maximum stake duration boost



# Function `setMaxPerformanceBoostNumerator(uint256 newMaxPerformanceBoostNumerator)` {#IDhedgeStakingV2Storage-setMaxPerformanceBoostNumerator-uint256-}
Allows the owner to adjust the maxPerformanceBoostNumerator


## Parameters:
- `newMaxPerformanceBoostNumerator`: the performance increase to reach max boost



# Function `setStakingRatio(uint256 newStakingRatio)` {#IDhedgeStakingV2Storage-setStakingRatio-uint256-}
Allows the owner to adjust the stakingRatio


## Parameters:
- `newStakingRatio`: the amount of dht that can be staked per dollar of DHPT



# Function `setEmissionsRate(uint256 newEmissionsRate)` {#IDhedgeStakingV2Storage-setEmissionsRate-uint256-}
Allows the owner to adjust the emissionsRate


## Parameters:
- `newEmissionsRate`: currently 1 not used



# Function `setRewardStreamingTime(uint256 newRewardStreamingTime)` {#IDhedgeStakingV2Storage-setRewardStreamingTime-uint256-}
Allows the owner to adjust the rewardStreamingTime


## Parameters:
- `newRewardStreamingTime`: max amount of aggregate value of pool tokens that can be staked



# Function `dhtAddress() → address` {#IDhedgeStakingV2Storage-dhtAddress--}
The contract address for DHT




# Function `numberOfPoolsConfigured() → uint256 numberOfPools` {#IDhedgeStakingV2Storage-numberOfPoolsConfigured--}
The total number of pools configured for staking





# Function `poolConfiguredByIndex(uint256 index) → address poolAddress` {#IDhedgeStakingV2Storage-poolConfiguredByIndex-uint256-}
Returns the poolAddress stored at the index


## Parameters:
- `index`: the index to look up


## Return Values:
- poolAddress the address at the index


# Function `setTokenUriGenerator(contract IDhedgeStakingV2NFTJson newTokenUriGenerator)` {#IDhedgeStakingV2Storage-setTokenUriGenerator-contract-IDhedgeStakingV2NFTJson-}
Allows the owner to set the tokenUriGenerator contract


## Parameters:
- `newTokenUriGenerator`: the address of the deployed tokenUriGenerator



