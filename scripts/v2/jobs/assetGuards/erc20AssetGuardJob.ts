import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig } from "../../types";

export const erc20AssetGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: { assetGuardsFileName: string },
  addresses: {},
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
      config.execute,
      config.restartnonce,
    );

    const deployedGuard = {
      AssetType: 0,
      GuardName: "ERC20Guard",
      GuardAddress: erc20Guard.address,
      Description: "ERC20 tokens",
    };

    await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "GuardName");
  }
};
