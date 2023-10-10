import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const dhedgeOptionMarketWrapperForLyraJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  _filenames: { assetGuardsFileName: string },
  addresses: IAddresses,
) => {
  if (!addresses.lyra) {
    console.warn("Lyra config missing.. skipping.");
    return;
  }
  if (!addresses.synthetixProxyAddress) {
    console.warn("synthetixProxyAddress missing.. skipping.");
    return;
  }

  const ethers = hre.ethers;

  console.log("Will deploy DhedgeOptionMarketWrapperForLyra");
  if (config.execute) {
    console.log("deploying DhedgeOptionMarketWrapperForLyra");
    let aaveLendingPoolAddress = addresses.aaveV3?.aaveLendingPoolAddress;
    // This is for testnets where aave is not available
    if (!aaveLendingPoolAddress) {
      const AaveFlashloanMock = await ethers.getContractFactory("AaveFlashloanMock");
      const aaveFlashloanMock = await AaveFlashloanMock.deploy();
      await aaveFlashloanMock.deployed();

      aaveLendingPoolAddress = aaveFlashloanMock.address;
    }

    const DhedgeOptionMarketWrapperForLyra = await ethers.getContractFactory("DhedgeOptionMarketWrapperForLyra");
    const dhedgeOptionMarketWrapperForLyra = await DhedgeOptionMarketWrapperForLyra.deploy(
      addresses.lyra.lyraRegistry,
      aaveLendingPoolAddress,
    );
    await dhedgeOptionMarketWrapperForLyra.deployed();

    await tryVerify(
      hre,
      dhedgeOptionMarketWrapperForLyra.address,
      "contracts/utils/lyra/DhedgeOptionMarketWrapperForLyra.sol:DhedgeOptionMarketWrapperForLyra",
      [addresses.lyra.lyraRegistry, aaveLendingPoolAddress],
    );

    console.log("DhedgeOptionMarketWrapperForLyra deployed at", dhedgeOptionMarketWrapperForLyra.address);
    versions[config.newTag].contracts.DhedgeOptionMarketWrapperForLyra = dhedgeOptionMarketWrapperForLyra.address;

    console.log(
      "LyraOptionMarketWrapperAssetGuard relies on DhedgeOptionMarketWrapperForLyra, please redeploy LyraOptionMarketWrapperAssetGuard",
    );
  }
};
