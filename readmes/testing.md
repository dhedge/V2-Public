# Testing

Tests are written in Solidity and run with [Foundry](https://book.getfoundry.sh/). There are two
kinds: forkless unit tests and fork-based integration tests.

## Unit tests

Forkless tests live in `test/unit/` and build on `test/unit/PoolUnitTestSetup.t.sol`, which deploys
the whole dHEDGE core against locally minted tokens (`contracts/test/TestAssets.sol`) and
`vm.mockCall`'d price feeds. No fork, no RPC, no external state — they are fast and are suited to
core accounting and access-control rules that do not depend on any real protocol.

A single test should assert a single behaviour and must not depend on state left by another test;
each test sets up exactly what it asserts.

## Integration tests

Where our contracts integrate with third-party protocols we test against a fork of a real chain
(Polygon, Optimism, Arbitrum, Base, Ethereum, Plasma). These live under `test/integration/{chain}/`
and build on `test/integration/utils/foundry/BackboneSetup.t.sol` plus a chain setup (e.g.
`ArbitrumSetup`). The chain setup calls `vm.createSelectFork` with an RPC URL and a pinned block, so
each suite forks itself — you do **not** need to start a separate node. Provider URLs come from your
`.env` / `foundry.toml`. State is pinned at the fork block, so external updates
(e.g. Chainlink rounds) are frozen unless a test advances them.

Tests that need live off-chain data (aggregator swap quotes) live under `test/integration/ffi/{chainId}/`
and run under a separate profile.

## Running

```bash
# all tests except FFI
pnpm test

# FFI tests (needs the ffi-tests profile and network access)
pnpm test:ffi

# a single contract or test
forge test --match-contract CoreTestArbitrum
forge test --match-test test_can_supply_into_aave
```

Use `forge build --skip test` to check production code compiles without building the test suite.

## Skipping and excluding tests

Two mechanisms, with different visibility:

- `vm.skip(...)` marks a test as skipped and forge reports it as such in every run. Use it for tests
  that do not apply in some configurations (`vm.skip(shouldSkip)`), to opt out of inherited tests in an
  override, or in `setUp` to skip a whole suite while keeping it visible.
- A `Skip` suffix on the test contract name (e.g. `FlatMoneyV2PerpMarketDryRunOptimismSkip`) excludes
  the contract from every default run via `no_match_contract = "Skip"` in `foundry.toml`. Use it for
  on-demand harnesses such as deployment dry runs, and for suites that cannot pass until other work
  lands. The filter itself produces no output, so record the reason in the contract's NatSpec.

Running an excluded contract requires overriding the config exclusion explicitly:

```bash
forge test --match-contract HyperliquidWithdrawalManagerTestsSkip --no-match-contract '^$'
```

## CI

`test` runs on every push via `.github/workflows/basic-check.yml`. FFI tests are excluded from
that gate (they depend on external quote APIs); run them locally or on demand.
