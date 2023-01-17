import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

// ERC20Guard is used for the following asset types
const Erc20 = 0;
const SynthetixErc20 = 1;
const BalancerLPErc20 = 6;

const erc20AssetTypes = [Erc20, SynthetixErc20, BalancerLPErc20];

export const erc20GuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: { assetGuardsFileName: string },
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy erc20guard");
  if (config.execute) {
    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    await erc20Guard.deployed();
    console.log("ERC20Guard deployed at", erc20Guard.address);

    versions[config.newTag].contracts.ERC20Guard = erc20Guard.address;

    await tryVerify(hre, erc20Guard.address, "contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard", []);

    for (const assetType of erc20AssetTypes) {
      const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [assetType, erc20Guard.address]);

      await proposeTx(
        versions[config.oldTag].contracts.Governance,
        setAssetGuardABI,
        `setAssetGuard for ERC20Guard AssetType ${assetType}`,
        config,
        addresses,
      );

      const deployedGuard = {
        assetType: assetType,
        guardName: "ERC20Guard",
        guardAddress: erc20Guard.address,
        description: "ERC20 tokens",
      };

      await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
    }
  }
};
