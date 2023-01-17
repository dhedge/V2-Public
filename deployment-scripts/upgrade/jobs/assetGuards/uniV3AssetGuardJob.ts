import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const uniV3AssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { assetGuardsFileName: string },
  addresses: IProposeTxProperties,
) => {
  console.log("Will deploy univ3assetguard");
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);

    const UniswapV3AssetGuard = await ethers.getContractFactory("UniswapV3AssetGuard");
    const uniV3AssetGuard = await UniswapV3AssetGuard.deploy();
    await uniV3AssetGuard.deployed();
    console.log("UniswapV3AssetGuard deployed at", uniV3AssetGuard.address);

    versions[config.newTag].contracts.UniswapV3AssetGuard = uniV3AssetGuard.address;

    await tryVerify(
      hre,
      uniV3AssetGuard.address,
      "contracts/guards/assetGuards/UniswapV3AssetGuard.sol:UniswapV3AssetGuard",
      [],
    );
    const assetHandlerAssetType = 7;
    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
      assetHandlerAssetType,
      uniV3AssetGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for UniswapV3AssetGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: 7,
      guardName: "UniswapV3AssetGuard",
      guardAddress: uniV3AssetGuard.address,
      description: "Uniswap V3 LP positions",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
