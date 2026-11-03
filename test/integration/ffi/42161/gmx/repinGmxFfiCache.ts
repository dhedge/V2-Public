import { spawnSync } from "node:child_process";

export function repinGmxFfiCache(repositoryRoot: string): number {
  if (!process.env.ARBITRUM_URL) {
    process.stderr.write("ARBITRUM_URL is not set; add it to .env\n");
    return 1;
  }

  const result = spawnSync("forge", ["test", "--match-path", "test/integration/ffi/42161/gmx/*.t.sol"], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      FOUNDRY_PROFILE: "ffi-tests",
      USE_CACHED_GMX_DATA: "false",
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
  return result.status ?? 1;
}
