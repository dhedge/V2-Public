import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

export const erc20AssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
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

    const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [0, erc20Guard.address]);
    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setAssetGuardABI,
      "setAssetGuard for ERC20Guard",
      config,
      addresses,
    );

    const deployedGuard = {
      assetType: 0,
      guardName: "ERC20Guard",
      guardAddress: erc20Guard.address,
      description: "ERC20 tokens",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
  }
};
