# Staking V2

- Users can create multiple stakes which are returned to them as an Erc721 token (NFT).
- Users create stakes by staking 0 or more DHT.
- Users accrue vDHT for each stake linearly overtime (maxVDurationTime, currently 9 months) calculated by DhedgeVDHTCalculator.
- A Users net vDHT balance (for voting) is an aggregate of vDHT accrued over all stakes.
- Users can stake DHPT alongside their DHT stakes.
- Users that stake both DHT and DHPT receive staking rewards denominated in DHT based on several factors
	a. vDHT accrued for the stake
	b. Total DHPT Value Staked
	c. How long the DHPT have been staked (currently capped at 9 months year)
	d. DHPT Performance (currently capped at 50%)
	e. The Emissions rate that was set when the stake was created

- Users can unstake DHT and or DHPT at anytime.
- Users can stake additional DHT at anytime.
- Users CANNOT stake additional DHPT in an existing stake (they can create a new stake or unstake and stake again).
- When a User unstakes DHPT, rewards are calculated (DhedgeStakingRewardsCalculator) and can be claimed linearly over rewardStreamingTime (currently 7 days), that tokenId/stake is marked as finished.
- The Users staked DHT (and vDHT) are automatically moved to a new stake with no vDHT penalty and the User can stake DHPT again or unstake their DHT.
- Users should be able to see their stakes from any wallet that supports ERC721.

# Pool Whitelisting

Each pool that can participate in staking must be whitelisted, each needs to be configured with a cap denominated in $$ value of pool tokens that can be staked.

# Notes on maxStakingValue

- The dhtCap effective controls how much DHPT we allow to be staked at one given time. This is a crude safe guard to limit the max emissions. MaxStakingValue = `dhtCap / stakingRatio / emissionsRate`
