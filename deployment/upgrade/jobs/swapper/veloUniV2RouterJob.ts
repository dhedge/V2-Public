import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const veloUniV2RouterJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  const veloRouter = addresses.velodrome?.router;
  if (!veloRouter) {
    console.warn("DhedgeVeloUniV2Router missing velo router config. Skipping...");
    return;
  }

  console.log("Will deploy DhedgeVeloUniV2Router");
  if (config.execute) {
    const DhedgeVeloUniV2Router = await ethers.getContractFactory("DhedgeVeloUniV2Router");
    const dhedgeVeloUniV2Router = await DhedgeVeloUniV2Router.deploy(veloRouter);
    await dhedgeVeloUniV2Router.deployed();

    await tryVerify(
      hre,
      dhedgeVeloUniV2Router.address,
      "contracts/routers/DhedgeVeloUniV2Router.sol:DhedgeVeloUniV2Router",
      [veloRouter],
    );

    versions[config.newTag].contracts.DhedgeVeloUniV2Router = dhedgeVeloUniV2Router.address;
  }
};
