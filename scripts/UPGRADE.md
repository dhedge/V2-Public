# How to upgrade Polygon

First the most important thing to understand, upgrading is not for the faint of heart, and that both polygon `staging` and polygon `production` are deployed on the same chain `polgyon` mainnet.

To upgrade, upgradable contracts, the transactions that do the upgrades need to be submitted through the gnosis safe (multisig). So the upgrade script is responsible for proposing those upgrade transactions to gnosis https://gnosis-safe.io/app/matic:0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4/transactions/queue.

New immutable contracts, for example, new implementations or guards, can and are deployed by the upgrade script directly onchain and then ownership is transferred to the gnosis safe address. A tx is then proposed to the gnosis safe that updates the implementation, or sets the guard in governance.

## Openzepplin

We use `Openzepplin` tooling that helps us ensure our upgradable contracts remaining upgradable by following the expected storage patterns. To do this Openzepplin stores information about our deployments in the .openzepplin folder, there is unfortunately one file per chain for polygon it is `unknown-137. json`, https://docs.openzeppelin.com/cli/2.6/configuration#network.json this means our staging and production deployments can collide unless we do some clever switching. When the upgrade script starts it will rename `polygon-production.json` or `polygon-staging.json` to `unknown-137.json` depending on the environment we are executing the upgrade on.

**NOTE**: If you force exit the script early it may not switch the name back - this would need to be reverted.

## Gnosis

Once the upgrade script has run - transactions that needs to be signed by multiple signatories will be visible on https://gnosis-safe.io/app/matic:0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4/transactions/queue.

These need to be signed and submitted in order. Be aware the sometimes the gnosis ui only shows the first 5 or so of the pending tx. Not all of them.

## Polyscan | Contract Verification

Each new deployed contract should be successfully verified on polygonscan. This is done via `tryVerify`.

## Executing Upgrades

Upgrades are done via custom hardhat tasks.

```
npx hardhat upgrade-polygon --network polygon --execute true --production true
```

`upgrade-polgyon` is a task that is registered with hardhat in `hardhat.config.ts` by importing `upgrade-polygon.ts`.

`execute` is a task parameter. In the case of this task, if `--execute true` is not included, a dry-run will happen.

### --Production

`--production` is a task parameter that execute the upgrade against the existing production contracts. By leaving out this parameter it will execute against the existing staging deployments.

```
npx hardhat upgrade-polygon --network polygon --execute true
```

The above will execute an upgrade of all contracts against staging.

### --Specific

By default all contracts will be upgraded unless `--specific` contracts are specified


```
npx hardhat upgrade-polygon --network polygon --execute true --specific true --poolperformance true
```

The above will `execute` an upgrade for `poolPerformance` only. Multiple specific contract upgrades can be executed at the same time.

```
npx hardhat upgrade-polygon --network polygon --execute true --specific true --poolperformance true --poolfactory true
```

The above will `execute` an upgrade for both `poolPerformance` and `poolFactory`. We use all lowercase `task` parameters as using camelcase requires hyphenation.

If you want to see a list of all available tasks run


```
npx hardhat upgrade-polygon --network polygon
```

### --restartNonce

Each time the upgrade script is run it will check to see if there are any pending transactions in the `gnosis safe` queue. If there are it will automatically add any new transactions with a nonce greater than the last one in the queue. If you want to overwrite these transactions, for instance if there a mistake, you can pass the `--restartNonce true` parameter

```
npx hardhat upgrade-polygon --network polygon --execute true --production true --restart-nonce true
```





