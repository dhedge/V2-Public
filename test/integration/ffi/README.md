# FFI-Dependent Tests

This directory contains tests that require Foundry's FFI (Foreign Function Interface) to be enabled. These tests are separated from the regular test suite to allow running non-FFI tests efficiently without needing to enable FFI.

## Running FFI Tests

To run FFI-dependent tests:

```bash
pnpm test:ffi
```

This command uses the dedicated `ffi-tests` profile in foundry.toml which enables FFI and sets necessary permissions.

## Maintaining FFI Targets

`pnpm test-freshness:repin` refreshes everything that ages out, in one run:

- Fork block pins in `test/integration/utils/foundry/config/ForkBlocks.sol` (see `readmes/testing.md`).
- GMX: the committed signed-price fixture used by tests under `test/integration/ffi/42161/gmx/`.
- CoW: the live hash-validation canary at
  `test/integration/ffi/8453/cowSwap/CowSwapHashValidationTest_FFI_Base.t.sol`.

```bash
pnpm test-freshness:repin
```

The command loads `.env` and needs network access plus the `*_URL` variable of every chain it re-pins. Neither public
API requires a key. `pnpm test-freshness:check` warns when any of the three is stale; it runs from the pre-commit
hook and never fails.

GMX runs its FFI suite against one live snapshot and atomically updates `swapdatas-cache/gmx/arbitrum.json`. The
snapshot is reused for 30 minutes so every test shares the same block and reports.

CoW checks the local EIP-712 hash against its live API on the latest Base state. A successful run updates
`swapdatas-cache/cow-swap/base.json`; the freshness check warns after seven days. Each run submits a short-lived presign
order to CoW's public API.

Verify the refreshed GMX fixture in cached mode:

```bash
FOUNDRY_PROFILE=ffi-tests forge test --match-path "test/integration/ffi/42161/gmx/*.t.sol"
```

To add a target, keep its check and repin logic beside its FFI tests and register it in `scripts/testFreshness/check.ts`
and `scripts/testFreshness/repin.ts`.

## Adding New FFI Tests

When adding new tests that require FFI:

1. Place the test files in an appropriate subdirectory under `test/integration/ffi/`
2. Name your test files with a clear indicator that they require FFI, e.g. `*_FFI_*.t.sol`
3. Make sure your test files inherit from the appropriate base test classes

## Why Separate FFI Tests?

FFI-dependent tests:

- Require special permissions to run (security implications)
- May make external API calls which can slow down the test suite
- May require specific environment setup

By separating these tests, we can run the majority of tests quickly and without FFI enabled.
