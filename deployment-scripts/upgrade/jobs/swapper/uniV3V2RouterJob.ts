import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../Helpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const uniV3V2RouterJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;

  console.log("Will deploy DhedgeUniV3V2Router");
  if (config.execute) {
    const DhedgeUniV3V2Router = await ethers.getContractFactory("DhedgeUniV3V2Router");
    const dhedgeUniV3V2Router = await DhedgeUniV3V2Router.deploy(
      addresses.uniV3.uniswapV3FactoryAddress,
      addresses.uniV3.uniswapV3RouterAddress,
    );
    await dhedgeUniV3V2Router.deployed();

    await tryVerify(hre, dhedgeUniV3V2Router.address, "contracts/DhedgeUniV3V2Router.sol:DhedgeUniV3V2Router", [
      addresses.uniV3.uniswapV3FactoryAddress,
      addresses.uniV3.uniswapV3RouterAddress,
    ]);

    versions[config.newTag].contracts.DhedgeUniV3V2Router = dhedgeUniV3V2Router.address;
  }
};
