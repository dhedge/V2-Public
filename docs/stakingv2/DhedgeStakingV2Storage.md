

# Functions:
- [`setMaxVDurationTimeSeconds(uint256 newMaxVDurationTimeSeconds)`](#DhedgeStakingV2Storage-setMaxVDurationTimeSeconds-uint256-)
- [`setStakeDurationDelaySeconds(uint256 newStakeDurationDelaySeconds)`](#DhedgeStakingV2Storage-setStakeDurationDelaySeconds-uint256-)
- [`setMaxDurationBoostSeconds(uint256 newMaxDurationBoostSeconds)`](#DhedgeStakingV2Storage-setMaxDurationBoostSeconds-uint256-)
- [`setMaxPerformanceBoostNumerator(uint256 newMaxPerformanceBoostNumerator)`](#DhedgeStakingV2Storage-setMaxPerformanceBoostNumerator-uint256-)
- [`setStakingRatio(uint256 newStakingRatio)`](#DhedgeStakingV2Storage-setStakingRatio-uint256-)
- [`setEmissionsRate(uint256 newEmissionsRate)`](#DhedgeStakingV2Storage-setEmissionsRate-uint256-)
- [`setDHTCap(uint256 newDHTCap)`](#DhedgeStakingV2Storage-setDHTCap-uint256-)
- [`setRewardStreamingTime(uint256 newRewardStreamingTime)`](#DhedgeStakingV2Storage-setRewardStreamingTime-uint256-)
- [`configurePool(address pool, uint256 cap)`](#DhedgeStakingV2Storage-configurePool-address-uint256-)
- [`setTokenUriGenerator(contract IDhedgeStakingV2NFTJson newTokenUriGenerator)`](#DhedgeStakingV2Storage-setTokenUriGenerator-contract-IDhedgeStakingV2NFTJson-)

# Events:
- [`OwnerOperation(string operation)`](#DhedgeStakingV2Storage-OwnerOperation-string-)


# Function `setMaxVDurationTimeSeconds(uint256 newMaxVDurationTimeSeconds)` {#DhedgeStakingV2Storage-setMaxVDurationTimeSeconds-uint256-}
Allows the owner to adjust the maxVDurationTimeSeconds


## Parameters:
- `newMaxVDurationTimeSeconds`: time to reach max VHDT for a staker



# Function `setStakeDurationDelaySeconds(uint256 newStakeDurationDelaySeconds)` {#DhedgeStakingV2Storage-setStakeDurationDelaySeconds-uint256-}
Allows the owner to adjust the setStakeDurationDelaySeconds


## Parameters:
- `newStakeDurationDelaySeconds`: delay before a staker starts to receive rewards



# Function `setMaxDurationBoostSeconds(uint256 newMaxDurationBoostSeconds)` {#DhedgeStakingV2Storage-setMaxDurationBoostSeconds-uint256-}
Allows the owner to adjust the maxDurationBoostSeconds


## Parameters:
- `newMaxDurationBoostSeconds`: time to reach maximum stake duration boost



# Function `setMaxPerformanceBoostNumerator(uint256 newMaxPerformanceBoostNumerator)` {#DhedgeStakingV2Storage-setMaxPerformanceBoostNumerator-uint256-}
Allows the owner to adjust the maxPerformanceBoostNumerator


## Parameters:
- `newMaxPerformanceBoostNumerator`: the performance increase to reach max boost



# Function `setStakingRatio(uint256 newStakingRatio)` {#DhedgeStakingV2Storage-setStakingRatio-uint256-}
Allows the owner to adjust the stakingRatio


## Parameters:
- `newStakingRatio`: the amount of dht that can be staked per dollar of DHPT



# Function `setEmissionsRate(uint256 newEmissionsRate)` {#DhedgeStakingV2Storage-setEmissionsRate-uint256-}
Allows the owner to adjust the emissionsRate


## Parameters:
- `newEmissionsRate`: the current emissions rate



# Function `setDHTCap(uint256 newDHTCap)` {#DhedgeStakingV2Storage-setDHTCap-uint256-}
Allows the owner to adjust the dhtCap


## Parameters:
- `newDHTCap`: max amount of aggregate value of pool tokens that can be staked



# Function `setRewardStreamingTime(uint256 newRewardStreamingTime)` {#DhedgeStakingV2Storage-setRewardStreamingTime-uint256-}
Allows the owner to adjust the rewardStreamingTime


## Parameters:
- `newRewardStreamingTime`: max amount of aggregate value of pool tokens that can be staked



# Function `configurePool(address pool, uint256 cap)` {#DhedgeStakingV2Storage-configurePool-address-uint256-}
Allows configuring a pool for staking


## Parameters:
- `pool`: the dhedge pool address

- `cap`: The max amount of value in pooltokens that can be staked for this pool



# Function `setTokenUriGenerator(contract IDhedgeStakingV2NFTJson newTokenUriGenerator)` {#DhedgeStakingV2Storage-setTokenUriGenerator-contract-IDhedgeStakingV2NFTJson-}
Allows the owner to set the tokenUriGenerator contract


## Parameters:
- `newTokenUriGenerator`: the address of the deployed tokenUriGenerator



