import fs from "node:fs";
import path from "node:path";

const STALE_AFTER_DAYS = 30;
const GMX_FIXTURE_PATH = "swapdatas-cache/gmx/arbitrum.json";

type FixtureMetadata = {
  forkBlockNumber?: unknown;
  forkBlockTimestamp?: unknown;
};

function warnInvalidFixture(): void {
  process.stderr.write(
    `GMX FFI fixture metadata is missing or invalid in ${GMX_FIXTURE_PATH}. Run: pnpm test-freshness:repin\n`,
  );
}

export function checkGmxFfiCache(repositoryRoot: string): void {
  try {
    const fixture = JSON.parse(fs.readFileSync(path.join(repositoryRoot, GMX_FIXTURE_PATH), "utf8")) as FixtureMetadata;
    if (
      typeof fixture.forkBlockTimestamp !== "number" ||
      !Number.isSafeInteger(fixture.forkBlockTimestamp) ||
      fixture.forkBlockTimestamp < 0 ||
      typeof fixture.forkBlockNumber !== "string" ||
      !/^\d+$/.test(fixture.forkBlockNumber)
    ) {
      warnInvalidFixture();
      return;
    }

    const ageDays = Math.floor((Date.now() / 1_000 - fixture.forkBlockTimestamp) / 86_400);
    if (ageDays > STALE_AFTER_DAYS) {
      process.stderr.write(
        `GMX FFI fixture is ${ageDays} days old (block ${fixture.forkBlockNumber}). Run: pnpm test-freshness:repin\n`,
      );
    }
  } catch {
    warnInvalidFixture();
  }
}
