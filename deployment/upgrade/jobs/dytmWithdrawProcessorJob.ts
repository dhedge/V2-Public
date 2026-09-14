import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../types";

// Reuse the versions.json PoolLogicLib even if its bytecode differs from source. False = deploy fresh on mismatch.
const REUSE_EXISTING_POOL_LOGIC_LIB = true;

// Normalise a library's runtime bytecode before comparing it to the compiled artifact:
//  - strip the leading PUSH20 <self-address> guard — a deployed lib embeds its own address, so it
//    always differs from the artifact in those 20 bytes.
//  - strip the trailing CBOR metadata — differs across compiler settings/source paths.
// Caveat: a mismatch (not byte-identical) can be stale logic OR just a different compile, so only an
// exact match proves "up to date"; a mismatch warrants a human look.
const normalizeLibCode = (code: string): string => {
  let c = code.toLowerCase().replace(/^0x/, "");
  if (c.startsWith("73")) c = c.slice(42);
  const metaLen = parseInt(c.slice(-4), 16) * 2;
  if (metaLen && metaLen + 4 <= c.length) c = c.slice(0, c.length - metaLen - 4);
  return c;
};

export const dytmWithdrawProcessorJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.dytm) {
    return console.warn("dytm config not found for dytmWithdrawProcessorJob: skipping.");
  }

  if (!addresses.assets?.usdc) {
    return console.warn("assets.usdc not configured for dytmWithdrawProcessorJob: skipping.");
  }

  if (config.execute) {
    console.log("Will deploy DytmWithdrawProcessor");

    const ethers = hre.ethers;
    const poolFactoryAddress = versions[config.oldTag].contracts.PoolFactoryProxy;
    const easySwapperV2Address = versions[config.oldTag].contracts.EasySwapperV2Proxy;

    if (!poolFactoryAddress) {
      return console.warn("PoolFactoryProxy could not be found: skipping.");
    }
    if (!easySwapperV2Address) {
      return console.warn("EasySwapperV2Proxy could not be found: skipping.");
    }

    // Reuse the deployed PoolLogicLib if it matches source or the override is set; else deploy fresh.
    const { deployedBytecode } = await hre.artifacts.readArtifact("PoolLogicLib");
    const existingPoolLogicLib = versions[config.oldTag].contracts.PoolLogicLib;
    const matchesSource =
      !!existingPoolLogicLib &&
      normalizeLibCode(await ethers.provider.getCode(existingPoolLogicLib)) === normalizeLibCode(deployedBytecode);
    const reuseExistingPoolLogicLib = !!existingPoolLogicLib && (matchesSource || REUSE_EXISTING_POOL_LOGIC_LIB);

    let poolLogicLibAddress: string;
    if (reuseExistingPoolLogicLib) {
      poolLogicLibAddress = existingPoolLogicLib as string;
      console.log(
        matchesSource
          ? `Reusing existing PoolLogicLib (matches source) at ${poolLogicLibAddress}`
          : `Reusing existing PoolLogicLib at ${poolLogicLibAddress} via REUSE override (bytecode differs from source)`,
      );
    } else {
      console.log("PoolLogicLib missing or out of date with source; deploying a fresh one");
      const PoolLogicLib = await ethers.getContractFactory("PoolLogicLib");
      const poolLogicLib = await PoolLogicLib.deploy();
      await poolLogicLib.deployed();
      poolLogicLibAddress = poolLogicLib.address;
      console.log("PoolLogicLib deployed at:", poolLogicLibAddress);
      versions[config.newTag].contracts.PoolLogicLib = poolLogicLibAddress;
      await tryVerify(hre, poolLogicLibAddress, "contracts/utils/PoolLogicLib.sol:PoolLogicLib", []);
    }

    const DytmWithdrawProcessor = await ethers.getContractFactory("DytmWithdrawProcessor", {
      libraries: { PoolLogicLib: poolLogicLibAddress },
    });
    const args: [string, string, string] = [easySwapperV2Address, poolFactoryAddress, addresses.assets.usdc];
    const dytmWithdrawProcessor = await DytmWithdrawProcessor.deploy(...args);
    await dytmWithdrawProcessor.deployed();
    console.log("DytmWithdrawProcessor deployed at", dytmWithdrawProcessor.address);

    await tryVerify(
      hre,
      dytmWithdrawProcessor.address,
      "contracts/swappers/easySwapperV2/DytmWithdrawProcessor.sol:DytmWithdrawProcessor",
      args,
    );

    await dytmWithdrawProcessor.transferOwnership(addresses.protocolDaoAddress);

    versions[config.newTag].contracts.DytmWithdrawProcessor = dytmWithdrawProcessor.address;

    // Surface the address: add it to ondo.ondoGMSwap.authorizedCallers, then run --ondogmswapconfig.
    console.log(
      `ACTION: add ${dytmWithdrawProcessor.address} to ondo.ondoGMSwap.authorizedCallers, then run --ondogmswapconfig`,
    );

    // DytmOfficeAssetGuard stores the processor as an immutable, so it must be re-deployed (and its
    // setAssetGuard(106, ...) re-proposed) to point at this new processor.
    console.log(
      `ACTION: re-deploy DytmOfficeAssetGuard (stores processor ${dytmWithdrawProcessor.address} as immutable) via --dytmofficeassetguard`,
    );
  }
};
