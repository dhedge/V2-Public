# FFI-Dependent Tests

This directory contains tests that require Foundry's FFI (Foreign Function Interface) to be enabled. These tests are separated from the regular test suite to allow running non-FFI tests efficiently without needing to enable FFI.

## Running FFI Tests

To run FFI-dependent tests:

```bash
pnpm test:forge:ffi
```

This command uses the dedicated `ffi-tests` profile in foundry.toml which enables FFI and sets necessary permissions.

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
