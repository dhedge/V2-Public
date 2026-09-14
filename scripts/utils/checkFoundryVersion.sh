#!/usr/bin/env bash
# Fails if the installed forge version doesn't match .foundry-version (the repo-wide pin,
# also installed by CI workflows).
set -euo pipefail

cd "$(dirname "$0")/../.."

expected=$(<.foundry-version)
# the version line is "forge Version: 1.7.1", with a "-stable"-style suffix on some builds
actual="v$(forge --version | sed -n 's/^forge Version: \([0-9][0-9.]*\).*/\1/p')"

if [[ "$actual" != "$expected" ]]; then
  echo "Foundry $expected is required, but 'forge --version' reports $actual." >&2
  echo "Run: foundryup --install $expected" >&2
  exit 1
fi
