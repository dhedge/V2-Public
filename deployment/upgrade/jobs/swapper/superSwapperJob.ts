import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";
import { RouteHintStruct } from "../../../../types/DhedgeSuperSwapper";

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
  const { DhedgeUniV3V2Router, DhedgeVeloV2UniV2Router, DhedgeRamsesUniV2Router } = versions[config.newTag].contracts;
  const v2Routers = [
    ...(addresses.v2RouterAddresses ?? []),
    ...[DhedgeUniV3V2Router, DhedgeVeloV2UniV2Router, DhedgeRamsesUniV2Router].filter(
      (router): router is Address => !!router,
    ),
  ];

  console.log("Deploying SwapRouter with", v2Routers);

  const args: [Address[], RouteHintStruct[]] = [v2Routers, addresses.superSwapper?.routeHints ?? []];

  if (config.execute) {
    const dhedgeSwapRouter = await DhedgeSuperSwapper.deploy(...args);
    await dhedgeSwapRouter.deployed();

    console.log("DhedgeSuperSwapper deployed to: ", dhedgeSwapRouter.address);
    await tryVerify(hre, dhedgeSwapRouter.address, "contracts/routers/DhedgeSuperSwapper.sol:DhedgeSuperSwapper", args);

    versions[config.newTag].contracts.DhedgeSuperSwapper = dhedgeSwapRouter.address;
  }
};
