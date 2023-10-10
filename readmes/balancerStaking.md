Balancer Rewards Gauges (staking)

# Asset Guard

Each Balancer Pair has a separate staking contract for instance the matic/StMatic pool has:
B-stMATIC-STABLE-gauge Reward Guage asset https://polygonscan.com/token/0x9928340f9e1aaad7df1d95e27bd9a5c715202a56

You call `deposit` (https://polygonscan.com/tx/0x30186cd3c33f08b2a41983f43768c0927d904b6620b42d663a34919eaff84aa5) then you receive back equal tokens in that gauge contract.

Each Pool needs to have an additional asset enabled (the gauge contract).

The gauge assets has its own AssetGuard to calculate the value of the staked tokens (including unclaimed rewards) and withdraw processing.

# Contract Guard

Each Gauge similarly to Arrakis is configured with a contract guard that enables the `deposit`, `withdraw`, `claim_rewards`.


