import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { AssetType } from "../assetsJob";

// ERC20Guard is used for the following asset types
const Erc20 = AssetType["Chainlink direct USD price feed with 8 decimals"];
const SynthetixErc20 = AssetType["Synthetix synth with Chainlink direct USD price feed"];
const BalancerLPErc20 = AssetType["Balancer LP"];

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

  console.log("Will deploy erc20guard");
  if (config.execute) {
    let erc20GuardAddress = versions[config.newTag].contracts.ERC20Guard;

    if (!erc20GuardAddress) {
      const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
      const erc20Guard = await ERC20Guard.deploy();
      await erc20Guard.deployed();
      erc20GuardAddress = erc20Guard.address;
      console.log("ERC20Guard deployed at", erc20GuardAddress);
      versions[config.newTag].contracts.ERC20Guard = erc20GuardAddress;
      await tryVerify(hre, erc20GuardAddress, "contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard", []);
    }

    const { chainId } = await ethers.provider.getNetwork();
    // Use Synthetix synths only for Optimism chain
    const assetTypesToSetERC20Guard =
      chainId === 10 ? [Erc20, SynthetixErc20, BalancerLPErc20] : [Erc20, BalancerLPErc20];
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
