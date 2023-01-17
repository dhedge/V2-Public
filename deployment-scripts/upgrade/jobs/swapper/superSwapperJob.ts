import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const superSwapperJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy DhedgeSuperSwapper");
  if (config.execute) {
    const DhedgeSuperSwapper = await ethers.getContractFactory("DhedgeSuperSwapper");
    const v2Routers = [...(addresses.v2RouterAddresses || [])];

    if (versions[config.newTag].contracts.DhedgeVeloV2Router) {
      v2Routers.push(versions[config.newTag].contracts.DhedgeVeloV2Router);
    }
    if (versions[config.newTag].contracts.DhedgeUniV3V2Router) {
      v2Routers.push(versions[config.newTag].contracts.DhedgeUniV3V2Router);
    }

    console.log("Deploying SwapRouter with", v2Routers, addresses.swapRouterCurvePools || []);
    const dhedgeSwapRouter = await DhedgeSuperSwapper.deploy(v2Routers, addresses.swapRouterCurvePools || []);
    await dhedgeSwapRouter.deployed();

    console.log("DhedgeSuperSwapper deployed to: ", dhedgeSwapRouter.address);
    await tryVerify(hre, dhedgeSwapRouter.address, "contracts/DhedgeSuperSwapper.sol:DhedgeSuperSwapper", [
      v2Routers,
      addresses.swapRouterCurvePools || [],
    ]);

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
  }
};
