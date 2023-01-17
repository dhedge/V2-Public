# Deployed contract checks

These check scripts can be used to check for any deployment errors. They check the intended configuration vs onchain data.

## How to check deployments

Can run full checks on a chain deployment: `npx hardhat checkConfig --network polygon` (or `npm run check:polygon:all`)

This script will check the following:

- core contract ownership
- factory configuration
- assets configuration (including prices against Coingecko where available)
- governance configuration
- deployed contract bytecode vs local contract bytecode differences (any changes in contracts)

### How to check specific deployment configuration

For example, you may have only deployed a new asset and want to do just an assets check.

Here is the list of checks:

- npx hardhat checkConfig --specific true --factory true
- npx hardhat checkConfig --specific true --governance true
- npx hardhat checkConfig --specific true --assets true
- npx hardhat checkConfig --specific true --bytecode true
