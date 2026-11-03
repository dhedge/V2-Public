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

### Fork blocks

Suites fork at one shared block per chain, `ForkBlocks.<CHAIN>` in
`test/integration/utils/foundry/config/ForkBlocks.sol`, so a new test should pass that constant rather
than a literal. Refresh all six with `pnpm test-freshness:repin` (reads the `*_URL` variables from `.env`),
then run `pnpm test`: a suite that fails at the fresh block has caught an on-chain change in the
integration it covers. The pre-commit hook prints a warning once the blocks are older than 30 days.

A suite that only makes sense at one block keeps its own literal: it replays a historical incident,
embeds data signed for that block (Merkle claims, attestations, Pyth updates, swap calldata), covers
an instrument that has since matured, or covers a deprecated integration. FFI suites keep their own
pins because their swap fixtures are keyed by block.

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

Use `pnpm build` (`forge build --skip test`) to check production code compiles without building the
test suite, and `pnpm build:sizes` to also list runtime sizes and fail on any over the EIP-170 limit.
Hardhat compiles nothing here; `pnpm compile:hardhat` only produces the artifacts and typechain types
the deployment tasks need, and those tasks run it themselves.

## Gas snapshots

Two committed snapshot suites turn a gas or bytecode-size change into a file diff. They are ordinary
tests: `pnpm test` runs them with everything else, and `pnpm test:gas` runs just them.

`test/unit/GasSnapshotTest.t.sol` records the user-paid paths on a clean vault (EasySwapperV2
deposits and the withdrawal flow, PoolLogic `deposit`, `withdrawSafe`, `withdrawToSafe`,
`execTransaction`, `mintManagerFee`, `totalFundValue`, `createFund`) into
`snapshots/GasSnapshotTest.json`, and the runtime size of the core contracts and PoolLogicLib into
`snapshots/ContractSizes.json`. After changing a contract:

```bash
pnpm test:gas
git diff snapshots/
```

Each changed line is one scenario, before and after. Commit the JSON together with the change: the
PR then shows the figures next to the code, and CI fails when a change lands without them. A moved
number on a pure refactor means behaviour moved too.

Two things to know:

- The suites run isolated (`forge-config: default.isolate = true`), so each measured call is its own
  transaction with cold storage, as it is paid for on-chain. Snapshots taken without isolation are
  not comparable.
- Forge rewrites a group file with only the entries it collected in that run, so regenerate with a
  whole contract (`pnpm test:gas`, or `--match-contract`), never with `--match-test`, before
  committing. Forge writes the JSON without a trailing newline; `pnpm test` and `pnpm test:gas` run
  prettier over `snapshots/` afterwards, and the commit hook does the same.

`foundry.toml` compiles with the same optimizer and EVM settings as the hardhat deployment config:
20 runs, cancun for 0.8.28, and istanbul for 0.7.6 (solc 0.7.6's own default, which is what hardhat
uses and what Etherscan shows as "default" on the deployed contracts; forge cannot hand a 0.7.6
compiler `cancun`, so it passes the newest target that compiler supports, which is the same
istanbul). So these figures, and `forge build --sizes`, are the ones that ship. When touching either
config or bumping solc, `pnpm check:compiler-parity` confirms every production contract still comes
out of hardhat and forge with the same settings and byte-identical runtime code.

### Mainnet figures

`test/integration/ethereum/core/EthereumGasSnapshotTest.t.sol` measures the same frontend paths on
production Ethereum vaults. A vault-agnostic base forks mainnet at `ForkBlocks.ETHEREUM`, swaps this
branch's PoolLogic, PoolManagerLogic, PoolFactory, AssetHandler and EasySwapperV2 in behind the live
proxies, and runs the same tests (deposit, native deposit, the withdrawal flow, `totalFundValue`,
`mintManagerFee`) against whichever vault a concrete contract names. Each vault records to
`snapshots/<ContractName>.json`; today Ethereum Bull 3X (leveraged) and mStable Pendled sUSDe (the
largest by value).
A test that does not apply to a vault (no native deposit asset, or a DYTM position whose withdrawal
needs frontend-built data) is `vm.skip`ped, so it stays visible.

An isolated snapshot equals the transaction's receipt gas (replaying a live
`depositWithCustomCooldown` reproduced its 751,298 gas exactly), so with the real asset mix these are
the numbers Ethereum users pay. After `pnpm test-freshness:repin`, run `pnpm test:gas` and commit
the regenerated files; small drifts there reflect vault state, not code. The unit suite stays the
fast, state-independent signal.

A protocol integration can add the same kind of `test_gas_*` snapshots to its fork suite (asset
guard `getBalance`, a withdrawal, the main `execTransaction` legs): a separate test contract carrying
the isolate config, the contract name as the group, and the resulting `snapshots/<Group>.json`
committed.

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

`test` runs on every push via `.github/workflows/basic-check.yml`, preceded by
`pnpm build:sizes` (fails on any production contract over the EIP-170 limit) and followed by `git diff --exit-code -- snapshots/` (the gas snapshots above must be
committed). FFI tests are excluded from that gate (they depend on external quote APIs); run them
locally or on demand.
