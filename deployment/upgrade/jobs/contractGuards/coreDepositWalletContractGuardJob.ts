import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IDeployedContractGuard, IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";

export const coreDepositWalletContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy CoreDepositWalletContractGuard");

  if (config.execute) {
    const coreDepositWallet = "0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24"; // USDC Core Deposit Wallet

    const CoreDepositWalletContractGuard = await ethers.getContractFactory("HyperliquidCoreDepositWalletContractGuard");
    const coreDepositWalletContractGuard = await CoreDepositWalletContractGuard.deploy();
    await coreDepositWalletContractGuard.deployed();

    console.log("HyperliquidCoreDepositWalletContractGuard deployed at", coreDepositWalletContractGuard.address);
    versions[config.newTag].contracts.HyperliquidCoreDepositWalletContractGuard =
      coreDepositWalletContractGuard.address;

    try {
      await tryVerify(
        hre,
        coreDepositWalletContractGuard.address,
        "contracts/guards/contractGuards/hyperliquid/HyperliquidCoreDepositWalletContractGuard.sol:HyperliquidCoreDepositWalletContractGuard",
        [],
      );
    } catch (error) {
      console.warn("Verification may have failed:", error);
    }

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      coreDepositWallet,
      coreDepositWalletContractGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for CoreDepositWalletContractGuard",
      config,
      addresses,
    );

    const deployedGuard: IDeployedContractGuard = {
      contractAddress: coreDepositWallet,
      guardName: "HyperliquidCoreDepositWalletContractGuard",
      guardAddress: coreDepositWalletContractGuard.address,
      description: "Hyperliquid CoreDepositWallet Guard",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
