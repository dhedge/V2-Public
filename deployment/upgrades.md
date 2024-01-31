# Upgrading Contracts

Note: When doing an upgrade it's advisable to pause the PoolFactory (this pauses withdrawals/deposits etc for pools), do the upgrade, does some checks (i.e the value of the pool tokens is correct), then unpause.
If we intend to be paused for an extended amount of time, we should announce this to the community.


## How to upgrade contracts for an Environment

First the most important thing to understand, upgrading is not for the faint of heart, and that both polygon `staging` and polygon `production` are deployed on the same chain `polygon` mainnet.

To upgrade, upgradable contracts, the transactions that do the upgrades need to be submitted through the gnosis safe (multisig). So the upgrade script is responsible for proposing those upgrade transactions to gnosis
For each chain they will be seen here:

- Polygon(staging/prod): https://app.safe.global/home?safe=matic:0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4
- Optimism(prod): https://app.safe.global/home?safe=oeth:0x90b1a66957914EbbE7a8df254c0c1E455972379C
- Arbitrum(prod): https://app.safe.global/home?safe=arb1:0x13471A221D6A346556723842A1526C603Dc4d36B
- Base(prod): https://app.safe.global/home?safe=base:0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100

New immutable contracts, for example, new implementations or guards, can and are deployed by the upgrade script directly onchain and if they are ownable the ownership is transferred to the gnosis safe address. A tx is then proposed to the gnosis safe that updates the implementation, or sets the guard in governance.

## Openzepplin

We use `Openzepplin` tooling that helps us ensure our upgradable contracts remaining upgradable by following the expected storage patterns. To do this Openzepplin stores information about our deployments in the .openzepplin folder, there is unfortunately one file per chain for polygon it is `polygon.json`, https://docs.openzeppelin.com/cli/2.6/configuration#network.json this means our staging and production deployments can collide unless we do some clever switching. When the upgrade script starts it will rename `polygon-production.json` or `polygon-staging.json` to `unknown-137.json` depending on the environment we are executing the upgrade on.

**NOTE**: If you force exit the script early it may not switch the name back - this would need to be reverted.

## Gnosis

Once the upgrade script has run - transactions that needs to be signed by multiple signatories will be visible on the gnosis link that can be found above.

These need to be signed and submitted in order. Be aware the sometimes the gnosis ui only shows the first 5 or so of the pending tx. Not all of them.

## Blockchain Explorer Contract Verification (optimistic.etherscan/polygonscan)

Each new deployed contract should be successfully verified on polygonscan. This is done via `tryVerify` function in the upgrade scripts. There is also a `explorer-verify` standalone hardhat task that can be used.

## Executing Upgrades

Upgrades are done via custom hardhat tasks.

```
npx hardhat upgrade --network polygon --production true --execute true
```

`upgrade` is a task that is registered with hardhat in `hardhat.config.ts` by importing `upgrade-polygon.ts`.

`execute` is a task parameter. In the case of this task, if `--execute true` is not included, a dry-run will happen.

`pause` and `unpause` are jobs that can be used to pause the contracts while doing an upgrade, examples below.

### --Production

`--production` is a task parameter that execute the upgrade against the existing production contracts. Setting this to false will execute against the existing staging deployment for that chain.

```
npx hardhat upgrade --network polygon --production false --execute true
```

The above will execute an upgrade of all contracts against polygon staging.

### --Specific

By default all contracts will be upgraded unless `--specific` contracts are specified


```
npx hardhat upgrade --network polygon --execute true --specific true --poolperformance true
```

The above will `execute` an upgrade for `poolPerformance` only. Multiple specific contract upgrades can be executed at the same time.

```
npx hardhat upgrade --network polygon --execute true --specific true --poolperformance true --poolfactory true
```

The above will `execute` an upgrade for both `poolPerformance` and `poolFactory`. We use all lowercase `task` parameters as using camelcase requires hyphenation.

If you want to pause during a upgrade you can:

```
npx hardhat upgrade --network polygon --execute true --specific true --pause true --poolperformance true --poolfactory true --unpause true
```

This will generate a pause tx at the start and a unpause tx at the end. You can submit the pause tx and the upgrade tx's, check, and then submit the unpause tx when happy.


If you want to see a list of all available tasks run

```
npx hardhat upgrade --network polygon
```

### --restartNonce

Each time the upgrade script is run it will check to see if there are any pending transactions in the `gnosis safe` queue. If there are it will automatically add any new transactions with a nonce greater than the last one in the queue. If you want to overwrite these transactions, for instance if there a mistake, you can pass the `--restartNonce true` parameter

```
npx hardhat upgrade --network polygon --execute true --production true --restart-nonce true
```
