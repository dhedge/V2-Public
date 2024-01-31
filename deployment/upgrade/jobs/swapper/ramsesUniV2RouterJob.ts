import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const ramsesUniV2RouterJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const ramsesRouter = addresses.ramses?.router;

  if (!ramsesRouter) {
    return console.warn("DhedgeRamsesUniV2Router missing Ramses router config. Skipping...");
  }

  console.log("Will deploy DhedgeRamsesUniV2Router");
  if (config.execute) {
    const DhedgeRamsesUniV2Router = await ethers.getContractFactory("DhedgeRamsesUniV2Router");
    const args: [string] = [ramsesRouter];
    const dhedgeRamsesUniV2Router = await DhedgeRamsesUniV2Router.deploy(...args);
    await dhedgeRamsesUniV2Router.deployed();

    await tryVerify(
      hre,
      dhedgeRamsesUniV2Router.address,
      "contracts/routers/DhedgeRamsesUniV2Router.sol:DhedgeRamsesUniV2Router",
      args,
    );

    versions[config.newTag].contracts.DhedgeRamsesUniV2Router = dhedgeRamsesUniV2Router.address;
  }
};
