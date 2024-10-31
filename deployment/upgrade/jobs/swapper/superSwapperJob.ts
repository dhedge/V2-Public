import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";
import { governanceNamesJob } from "../governanceNamesJob";

export const superSwapperJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy DhedgeSuperSwapper");
  if (config.execute) {
    const DhedgeSuperSwapper = await ethers.getContractFactory("DhedgeSuperSwapper");
    const v2Routers = [...addresses.v2RouterAddresses];

    if (versions[config.newTag].contracts.DhedgeUniV3V2Router) {
      v2Routers.push(versions[config.newTag].contracts.DhedgeUniV3V2Router);
    }
    if (versions[config.newTag].contracts.DhedgeVeloV2UniV2Router) {
      v2Routers.push(versions[config.newTag].contracts.DhedgeVeloV2UniV2Router);
    }
    if (versions[config.newTag].contracts.DhedgeRamsesUniV2Router) {
      v2Routers.push(versions[config.newTag].contracts.DhedgeRamsesUniV2Router);
    }

    console.log("Deploying SwapRouter with", v2Routers);

    const args: [Address[], IAddresses["superSwapper"]["routeHints"]] = [v2Routers, addresses.superSwapper.routeHints];

    const dhedgeSwapRouter = await DhedgeSuperSwapper.deploy(...args);
    await dhedgeSwapRouter.deployed();

    console.log("DhedgeSuperSwapper deployed to: ", dhedgeSwapRouter.address);
    await tryVerify(hre, dhedgeSwapRouter.address, "contracts/routers/DhedgeSuperSwapper.sol:DhedgeSuperSwapper", args);

    versions[config.newTag].contracts.DhedgeSuperSwapper = dhedgeSwapRouter.address;

    const DhedgeEasySwapper = await hre.artifacts.readArtifact("DhedgeEasySwapper");
    const DhedgeEasySwapperAbi = new ethers.utils.Interface(DhedgeEasySwapper.abi);
    try {
      const setSwapRouterAbi = DhedgeEasySwapperAbi.encodeFunctionData("setSwapRouter", [dhedgeSwapRouter.address]);

      await proposeTx(
        versions[config.newTag].contracts.DhedgeEasySwapperProxy,
        setSwapRouterAbi,
        "Add new SuperSwapper to EasySwapper",
        config,
        addresses,
      );
    } catch {
      console.warn("Deployed successfully, but unable to propose whitelist tx");
    }

    await addOrReplaceGuardInFile(
      filenames.governanceNamesFileName,
      {
        name: "swapRouter",
        destination: dhedgeSwapRouter.address,
      },
      "name",
    );

    await governanceNamesJob(config, hre, versions, filenames, addresses);
  }
};
