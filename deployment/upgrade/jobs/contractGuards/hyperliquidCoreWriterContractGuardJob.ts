import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IDeployedContractGuard, IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

export const hyperliquidCoreWriterContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const hyperliquidPerpsConfig = addresses.hyperliquid;
  if (!hyperliquidPerpsConfig) {
    return console.warn("Hyperliquid Perps configuration not found: skipping.");
  }

  const { admin, whitelistedVaults, maxSlippage } = hyperliquidPerpsConfig;

  if (!admin) {
    return console.warn("Hyperliquid Perps admin not configured: skipping.");
  }

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  // Hyperliquid CoreWriter contract address (fixed system address)
  const hyperliquidCoreWriterAddress = "0x3333333333333333333333333333333333333333";

  if (config.execute) {
    const existingProxy = versions[config.oldTag].contracts.HyperliquidCoreWriterContractGuardProxy;

    if (existingProxy) {
      // Upgrade existing proxy
      console.log("Will upgrade HyperliquidCoreWriterContractGuard");

      const HyperliquidCoreWriterContractGuard = await ethers.getContractFactory("HyperliquidCoreWriterContractGuard");
      const newImplementation = await upgrades.prepareUpgrade(existingProxy, HyperliquidCoreWriterContractGuard);
      console.log("HyperliquidCoreWriterContractGuard new implementation deployed at", newImplementation);

      versions[config.newTag].contracts.HyperliquidCoreWriterContractGuard = newImplementation;

      try {
        await tryVerify(
          hre,
          newImplementation,
          "contracts/guards/contractGuards/hyperliquid/HyperliquidCoreWriterContractGuard.sol:HyperliquidCoreWriterContractGuard",
          [],
        );
      } catch (error) {
        console.error("May have failed to verify HyperliquidCoreWriterContractGuard:", error);
      }

      // Propose upgrade through ProxyAdmin
      const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
      const proxyAdminABI = new ethers.utils.Interface(ProxyAdmin.abi);
      const upgradeABI = proxyAdminABI.encodeFunctionData("upgrade", [existingProxy, newImplementation]);

      await proposeTx(
        addresses.proxyAdminAddress,
        upgradeABI,
        "Upgrade HyperliquidCoreWriterContractGuard",
        config,
        addresses,
      );
    } else {
      // Deploy new proxy
      console.log("Will deploy HyperliquidCoreWriterContractGuard as proxy");

      const HyperliquidCoreWriterContractGuard = await ethers.getContractFactory("HyperliquidCoreWriterContractGuard");
      const hyperliquidCoreWriterContractGuardProxy = await upgrades.deployProxy(HyperliquidCoreWriterContractGuard, [
        admin,
        maxSlippage,
      ]);
      await hyperliquidCoreWriterContractGuardProxy.deployed();
      const proxyAddress = hyperliquidCoreWriterContractGuardProxy.address;

      console.log("HyperliquidCoreWriterContractGuard proxy deployed at", proxyAddress);

      const implementationAddress = await getImplementationAddress(ethers.provider, proxyAddress);
      console.log("HyperliquidCoreWriterContractGuard implementation at", implementationAddress);

      versions[config.newTag].contracts.HyperliquidCoreWriterContractGuardProxy = proxyAddress;
      versions[config.newTag].contracts.HyperliquidCoreWriterContractGuard = implementationAddress;

      try {
        await tryVerify(
          hre,
          implementationAddress,
          "contracts/guards/contractGuards/hyperliquid/HyperliquidCoreWriterContractGuard.sol:HyperliquidCoreWriterContractGuard",
          [],
        );
      } catch (error) {
        console.error("May have failed to verify HyperliquidCoreWriterContractGuard:", error);
      }

      // Set whitelisted vaults if any
      if (whitelistedVaults && whitelistedVaults.length > 0) {
        const contractInterface = HyperliquidCoreWriterContractGuard.interface;
        const setWhitelistTxData = contractInterface.encodeFunctionData("setDhedgePoolsWhitelist", [whitelistedVaults]);

        await proposeTx(
          proxyAddress,
          setWhitelistTxData,
          "Set whitelisted vaults for HyperliquidCoreWriterContractGuard",
          config,
          addresses,
        );

        console.log("Proposed whitelisted vaults update");
      }

      // Set contract guard in Governance
      await proposeTx(
        versions[config.oldTag].contracts.Governance,
        governanceABI.encodeFunctionData("setContractGuard", [hyperliquidCoreWriterAddress, proxyAddress]),
        "setContractGuard for HyperliquidCoreWriterContractGuard",
        config,
        addresses,
      );

      const deployedGuard: IDeployedContractGuard = {
        contractAddress: hyperliquidCoreWriterAddress,
        guardName: "HyperliquidCoreWriterContractGuard",
        guardAddress: proxyAddress,
        description: "Hyperliquid CoreWriter Guard",
      };

      await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
    }
  }
};
