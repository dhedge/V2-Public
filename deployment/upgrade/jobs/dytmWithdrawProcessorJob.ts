import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../deploymentHelpers";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../types";

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

    const DytmWithdrawProcessor = await ethers.getContractFactory("DytmWithdrawProcessor");
    const args: [string, string, string] = [addresses.dytm.dytmOffice, poolFactoryAddress, easySwapperV2Address];
    const dytmWithdrawProcessor = await DytmWithdrawProcessor.deploy(...args);
    await dytmWithdrawProcessor.deployed();
    console.log("DytmWithdrawProcessor deployed at", dytmWithdrawProcessor.address);

    await tryVerify(
      hre,
      dytmWithdrawProcessor.address,
      "contracts/swappers/easySwapperV2/libraries/dytm/DytmWithdrawProcessor.sol:DytmWithdrawProcessor",
      args,
    );

    await dytmWithdrawProcessor.transferOwnership(addresses.protocolDaoAddress);

    versions[config.newTag].contracts.DytmWithdrawProcessor = dytmWithdrawProcessor.address;
  }
};
