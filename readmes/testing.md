# Testing

There are two main types of tests contained in this folder. Unit & Integration.

## Unit Tests

Unit tests should be written for all new logic. Generally unit tests take more mocking setup than integration tests, but they easier and faster to run locally. They also allow the setting up to specific testing edge cases.

Generally a single test should only try to assert a single behaviour. Test's should not depend on the state left by a previous test. We try to use nested describe, before, beforeEach blocks effectively.

Unit tests run against a evm blockchain simulated by hardhat with not prior state.

```
npm run test:unit
```

## Integration Tests

In lots of cases our contracts integrate with other third party contracts. To ensure that they interact effectively we use integration tests. Integrations tests run against a fork of the real blockchain (i.e polygon, ethereum, ovm) and include the state from which point you fork.

You can read more about how this works here: https://hardhat.org/hardhat-network/guides/mainnet-forking.html

Before running your integration tests you must first fork the chain you which to tests against, for instance to fork OVM you would run. You need provider credentials setup in your .env for this to work (see ../.env.md).

```
npm run fork:ovm
```

This process needs to start and run in the background while you run your integration tests. Do note that once your fork is started, no outside updates are included in your chain, for instance chainlink oracles won't we updated on your fork. You can also fork from a specific block in the past. Any state changes your make to your fork in tests are persisted until you stop the fork process.

To run an individual integration test:

```
npx hardhat test test/integration/ovm/SynthetixTest.ts
```

To run multiple

```
npx hardhat test test/integration/ovm/*.ts
```


## CI

All tests unit and integration should be added to the requisite github workflow. Unit tests should execute on every commit and integration 
