# Deployed contract checks

These check scripts can be used to check for any deployment errors. They check the intended configuration vs onchain data.

## How to check deployments

Can run full checks on a chain deployment: `pnpm hardhat checkConfig --network polygon` (or `pnpm check:polygon:all`)

This script will check the following:

- core contract ownership
- factory configuration
- assets configuration (including prices against Coingecko where available)
- governance configuration
- deployed contract bytecode vs local contract bytecode differences (any changes in contracts)

### How to check specific deployment configuration

For example, you may have only deployed a new asset and want to do just an assets check.

Here is the list of checks:

- pnpm hardhat checkConfig --specific true --factory true
- pnpm hardhat checkConfig --specific true --governance true
- pnpm hardhat checkConfig --specific true --assets true
- pnpm hardhat checkConfig --specific true --bytecode true
