import { HardhatRuntimeEnvironment } from "hardhat/types";
import { tryVerify } from "../../../deploymentHelpers";
import { IJob, IUpgradeConfig, IVersions } from "../../../types";

export const erc721ContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
) => {
  if (!versions[config.oldTag].contracts.Governance) {
    console.warn("Governance not does not exist in versions: skipping.");
    return;
  }

  const ethers = hre.ethers;

  console.log("Will deploy erc721guard");
  if (config.execute) {
    const ERC721ContractGuard = await ethers.getContractFactory("ERC721ContractGuard");
    const erc721guard = await ERC721ContractGuard.deploy();
    await erc721guard.deployed();
    console.log("ERC721ContractGuard deployed at", erc721guard.address);

    versions[config.newTag].contracts.ERC721ContractGuard = erc721guard.address;

    await tryVerify(
      hre,
      erc721guard.address,
      "contracts/guards/contractGuards/ERC721ContractGuard.sol:ERC721ContractGuard",
      [],
    );
  }
};
