import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const veloV2UniV2RouterJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  const velodromeV2Router = addresses.velodrome?.routerV2;
  const velodromeV2Factory = addresses.velodrome?.factoryV2;

  if (!velodromeV2Router || !velodromeV2Factory) {
    return console.warn("DhedgeVeloV2UniV2Router missing Velodrome v2 router/factory config. Skipping...");
  }

  console.log("Will deploy DhedgeVeloV2UniV2Router");
  if (config.execute) {
    const DhedgeVeloV2UniV2Router = await ethers.getContractFactory("DhedgeVeloV2UniV2Router");
    const args: [string, string] = [velodromeV2Router, velodromeV2Factory];
    const dhedgeVeloV2UniV2Router = await DhedgeVeloV2UniV2Router.deploy(...args);
    await dhedgeVeloV2UniV2Router.deployed();

    await tryVerify(
      hre,
      dhedgeVeloV2UniV2Router.address,
      "contracts/routers/DhedgeVeloV2UniV2Router.sol:DhedgeVeloV2UniV2Router",
      args,
    );

    versions[config.newTag].contracts.DhedgeVeloV2UniV2Router = dhedgeVeloV2UniV2Router.address;
  }
};
