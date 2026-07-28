import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const ondoAttestationOracleJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ondoAttestationOracleProxy = versions[config.newTag].contracts.OndoAttestationOracleProxy;

  if (config.execute) {
    if (ondoAttestationOracleProxy) {
      await upgradeOndoAttestationOracle(hre, config, versions, addresses, ondoAttestationOracleProxy);
    } else {
      await deployOndoAttestationOracle(hre, config, versions, addresses);
    }
  }
};

const deployOndoAttestationOracle = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Deploying OndoAttestationOracle");

  if (!addresses.ondo?.gmTokenManager) return console.warn("ondo.gmTokenManager not configured... skipping.");

  const { gmTokenManager } = addresses.ondo;

  const attestationConfig = addresses.ondo?.attestationOracle;

  if (!attestationConfig) return console.warn("ondo.attestationOracle not configured... skipping.");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;

  const OndoAttestationOracle = await ethers.getContractFactory("OndoAttestationOracle");
  const initParams = [
    addresses.protocolDaoAddress, // owner
    gmTokenManager,
    attestationConfig.allowedUserId,
    [
      attestationConfig.maxProofAge,
      attestationConfig.sanityDeviationBps,
      attestationConfig.minQuoteValue,
      attestationConfig.maxQuoteValue,
    ], // ProofConfig
  ];
  const ondoAttestationOracle = await upgrades.deployProxy(OndoAttestationOracle, initParams);
  await ondoAttestationOracle.deployed();
  const proxyAddress = ondoAttestationOracle.address;

  const implementationAddress = await getImplementationAddress(provider, proxyAddress);

  await tryVerify(hre, implementationAddress, "contracts/oracles/OndoAttestationOracle.sol:OndoAttestationOracle", []);

  versions[config.newTag].contracts.OndoAttestationOracleProxy = proxyAddress;
  versions[config.newTag].contracts.OndoAttestationOracle = implementationAddress;

  console.log("OndoAttestationOracleProxy deployed to: ", proxyAddress);
  console.log("OndoAttestationOracle implementation: ", implementationAddress);
};

const upgradeOndoAttestationOracle = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
  proxy: string,
) => {
  console.log("Upgrading OndoAttestationOracle");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const OndoAttestationOracle = await ethers.getContractFactory("OndoAttestationOracle");
  const newLogic = await upgrades.prepareUpgrade(proxy, OndoAttestationOracle);
  console.log("New OndoAttestationOracle logic deployed to: ", newLogic);

  await tryVerify(hre, newLogic, "contracts/oracles/OndoAttestationOracle.sol:OndoAttestationOracle", []);

  const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [proxy, newLogic]);
  await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade OndoAttestationOracle", config, addresses);

  versions[config.newTag].contracts.OndoAttestationOracle = newLogic;

  console.log("OndoAttestationOracle upgraded. New implementation: ", newLogic);
};
