import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { Address, IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const uniV3AssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { assetGuardsFileName: string },
  addresses: {
    sushiMiniChefV2Address?: Address;
    uniSwapV3NonfungiblePositionManagerAddress?: Address;
  } & IProposeTxProperties,
) => {
  if (!addresses.uniSwapV3NonfungiblePositionManagerAddress) {
    throw new Error("No config for uniSwapV3NonfungiblePositionManagerAddress");
  }

  console.log("Will deploy univ3assetguard");
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const UniswapV3AssetGuard = await ethers.getContractFactory("UniswapV3AssetGuard");
    const uniV3AssetGuard = await UniswapV3AssetGuard.deploy(addresses.uniSwapV3NonfungiblePositionManagerAddress);
    await uniV3AssetGuard.deployed();
    console.log("UniswapV3AssetGuard deployed at", uniV3AssetGuard.address);

    versions[config.newTag].contracts.UniswapV3AssetGuard = uniV3AssetGuard.address;

    await tryVerify(
      hre,
      uniV3AssetGuard.address,
      "contracts/guards/assetGuards/UniswapV3AssetGuard.sol:UniswapV3AssetGuard",
      [addresses.uniSwapV3NonfungiblePositionManagerAddress],
    );

    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [7, uniV3AssetGuard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for UniswapV3AssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      AssetType: 7,
      GuardName: "UniswapV3AssetGuard",
      GuardAddress: uniV3AssetGuard.address,
      Description: "Uniswap V3 LP positions",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "GuardName");
  }
};
