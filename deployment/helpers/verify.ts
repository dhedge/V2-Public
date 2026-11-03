import { HardhatRuntimeEnvironment } from "hardhat/types";
import { retryWithDelay } from "./retry";
import { verifyViaApi } from "./verifyViaApi";

/** Set true to use the Etherscan V2 API instead of Hardhat verification on supported chains. */
const USE_API_VERIFY = false;

export const tryVerify = async (
  hre: HardhatRuntimeEnvironment,
  address: string,
  path: string,
  constructorArguments: unknown[],
) => {
  if (USE_API_VERIFY) {
    // A pending verification returns as queued, so deployment can continue without retrying it.
    const result = await retryWithDelay(
      () => verifyViaApi(hre, { address, contract: path, constructorArguments }),
      "Try Verify Failed: " + address,
      10,
    );
    if (result.status === "queued") {
      console.warn(`Verification queued for ${path} at ${address} (guid ${result.guid}); not yet verified.`);
    }
    return;
  }

  await retryWithDelay(
    async () => {
      try {
        await hre.run("verify:verify", {
          address: address,
          contract: path,
          constructorArguments: constructorArguments,
        });
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
      } catch (e: any) {
        if (e.message.toLowerCase().includes("constructor arguments exceeds max accepted")) {
          // Etherscan rejects very large verification payloads ("constructor arguments exceeds max accepted (10k chars) length")
          console.warn(`Couldn't verify contract at ${address}. Error: ${e.message}, skipping verification`);
          return;
        }
        if (!e.message.toLowerCase().includes("already verified")) {
          throw e;
        }
      }
    },
    "Try Verify Failed: " + address,
    10,
  );
};
