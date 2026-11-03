import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const COW_SWAP_TEST_PATH = "test/integration/ffi/8453/cowSwap/CowSwapHashValidationTest_FFI_Base.t.sol";
const COW_SWAP_VALIDATION_PATH = "swapdatas-cache/cow-swap/base.json";

function writeValidationMetadata(repositoryRoot: string): void {
  const validationFile = path.join(repositoryRoot, COW_SWAP_VALIDATION_PATH);
  const temporaryFile = `${validationFile}.${process.pid}.tmp`;
  const contents = `${JSON.stringify({ validatedAt: Math.floor(Date.now() / 1_000) }, null, 2)}\n`;

  fs.mkdirSync(path.dirname(validationFile), { recursive: true });
  try {
    fs.writeFileSync(temporaryFile, contents, { flag: "wx" });
    fs.renameSync(temporaryFile, validationFile);
  } catch (error) {
    fs.rmSync(temporaryFile, { force: true });
    throw error;
  }
}

export function repinCowSwapFfiCache(repositoryRoot: string): number {
  if (!process.env.BASE_URL) {
    process.stderr.write("BASE_URL is not set; add it to .env\n");
    return 1;
  }

  const result = spawnSync("forge", ["test", "--match-path", COW_SWAP_TEST_PATH], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      FOUNDRY_PROFILE: "ffi-tests",
    },
    stdio: "inherit",
  });

  if (result.error) {
    process.stderr.write(`Failed to start forge: ${result.error.message}\n`);
    return 1;
  }
  if (result.signal) {
    process.stderr.write(`forge terminated by ${result.signal}\n`);
    return 1;
  }
  if (result.status !== 0) {
    return result.status ?? 1;
  }

  try {
    writeValidationMetadata(repositoryRoot);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`Failed to update CoW FFI hash-validation metadata: ${message}\n`);
    return 1;
  }

  return 0;
}
