import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const superSwapperJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy DhedgeSuperSwapper");
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

  if (config.execute) {
    const dhedgeSwapRouter = await DhedgeSuperSwapper.deploy(...args);
    await dhedgeSwapRouter.deployed();

    console.log("DhedgeSuperSwapper deployed to: ", dhedgeSwapRouter.address);
    await tryVerify(hre, dhedgeSwapRouter.address, "contracts/routers/DhedgeSuperSwapper.sol:DhedgeSuperSwapper", args);

    versions[config.newTag].contracts.DhedgeSuperSwapper = dhedgeSwapRouter.address;
  }
};
