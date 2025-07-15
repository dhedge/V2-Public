import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { AssetType } from "../assetsJob";

export const erc20GuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy ERC20Guard");

  if (config.execute) {
    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    await erc20Guard.deployed();
    const erc20GuardAddress = erc20Guard.address;
    console.log("ERC20Guard deployed at", erc20GuardAddress);
    versions[config.newTag].contracts.ERC20Guard = erc20GuardAddress;
    await tryVerify(hre, erc20GuardAddress, "contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard", []);

    const assetTypesToSetERC20Guard = [AssetType["Chainlink direct USD price feed with 8 decimals"]];

    const governance = await ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);

    for (const assetType of assetTypesToSetERC20Guard) {
      const existingAssetGuardAddress = await governance.assetGuards(assetType);

      // If the asset guard is not set, set it
      if (existingAssetGuardAddress.toLowerCase() !== erc20GuardAddress.toLowerCase()) {
        console.log(`Setting ERC20Guard for assetType ${assetType}`);
        const setAssetGuardTxData = governanceABI.encodeFunctionData("setAssetGuard", [assetType, erc20GuardAddress]);

        await proposeTx(
          versions[config.oldTag].contracts.Governance,
          setAssetGuardTxData,
          `setAssetGuard for ERC20Guard AssetType ${assetType}`,
          config,
          addresses,
        );
      }

      const deployedGuard = {
        assetType,
        guardName: "ERC20Guard",
        guardAddress: erc20GuardAddress,
        description: "ERC20 tokens",
      };

      await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
    }
  }
};
