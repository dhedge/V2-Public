import fs from "node:fs";
import path from "node:path";

const STALE_AFTER_SECONDS = 7 * 86_400;
const COW_SWAP_VALIDATION_PATH = "swapdatas-cache/cow-swap/base.json";

type ValidationMetadata = {
  validatedAt?: unknown;
};

function warnInvalidMetadata(): void {
  process.stderr.write(
    `CoW FFI hash-validation metadata is missing or invalid in ${COW_SWAP_VALIDATION_PATH}. Run: pnpm test-freshness:repin\n`,
  );
}

export function checkCowSwapFfiCache(repositoryRoot: string): void {
  try {
    const metadata = JSON.parse(
      fs.readFileSync(path.join(repositoryRoot, COW_SWAP_VALIDATION_PATH), "utf8"),
    ) as ValidationMetadata;
    if (
      typeof metadata.validatedAt !== "number" ||
      !Number.isSafeInteger(metadata.validatedAt) ||
      metadata.validatedAt < 0
    ) {
      warnInvalidMetadata();
      return;
    }

    const ageSeconds = Date.now() / 1_000 - metadata.validatedAt;
    if (ageSeconds > STALE_AFTER_SECONDS) {
      const ageDays = Math.floor(ageSeconds / 86_400);
      process.stderr.write(`CoW FFI hash validation is ${ageDays} days old. Run: pnpm test-freshness:repin\n`);
    }
  } catch {
    warnInvalidMetadata();
  }
}
