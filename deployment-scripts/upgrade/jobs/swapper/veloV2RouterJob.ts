import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const veloV2RouterJob: IJob<void> = async (
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
    console.warn("DhedgeVeloV2Router missing velo config skipping...");
    return;
  }

  console.log("Will deploy DhedgeVeloV2Router");
  if (config.execute) {
    const DhedgeVeloV2Router = await ethers.getContractFactory("DhedgeVeloV2Router");
    const dhedgeVeloV2Router = await DhedgeVeloV2Router.deploy(veloRouter);
    await dhedgeVeloV2Router.deployed();

    await tryVerify(hre, dhedgeVeloV2Router.address, "contracts/DhedgeVeloV2Router.sol:DhedgeVeloV2Router", [
      veloRouter,
    ]);

    versions[config.newTag].contracts.DhedgeVeloV2Router = dhedgeVeloV2Router.address;
  }
};
