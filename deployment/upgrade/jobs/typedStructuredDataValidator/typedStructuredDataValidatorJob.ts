import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const typedStructuredDataValidatorJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (versions[config.newTag].contracts.TypedStructuredDataValidatorProxy) {
    await upgradeTypedStructuredDataValidator(hre, config, versions, addresses);
  } else {
    await deployTypedStructuredDataValidator(hre, config, versions, addresses);
  }
};

const upgradeTypedStructuredDataValidator = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Upgrading TypedStructuredDataValidator");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const proxy = versions[config.oldTag].contracts.TypedStructuredDataValidatorProxy;

  const TypedStructuredDataValidator = await ethers.getContractFactory("TypedStructuredDataValidator");

  if (config.execute) {
    const newImplementation = await upgrades.prepareUpgrade(proxy, TypedStructuredDataValidator);
    console.log("New logic deployed to: ", newImplementation);

    await tryVerify(
      hre,
      newImplementation,
      "contracts/validators/TypedStructuredDataValidator.sol:TypedStructuredDataValidator",
      [],
    );

    const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [proxy, newImplementation]);
    await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade TypedStructuredDataValidator", config, addresses);

    versions[config.newTag].contracts.TypedStructuredDataValidator = newImplementation;

    console.log("TypedStructuredDataValidator upgraded. New Implementation address: ", newImplementation);
  }
};

const deployTypedStructuredDataValidator = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  console.log("Deploying TypedStructuredDataValidator");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;

  const poolFactoryProxy = versions[config.newTag].contracts.PoolFactoryProxy;

  const TypedStructuredDataValidator = await ethers.getContractFactory("TypedStructuredDataValidator");
  const initParams = [addresses.protocolDaoAddress, poolFactoryProxy];

  if (config.execute) {
    const typedStructuredDataValidator = await upgrades.deployProxy(TypedStructuredDataValidator, initParams);
    await typedStructuredDataValidator.deployed();
    const typedStructuredDataValidatorProxy = typedStructuredDataValidator.address;

    const typedStructuredDataValidatorImplementationAddress = await getImplementationAddress(
      provider,
      typedStructuredDataValidatorProxy,
    );

    await tryVerify(
      hre,
      typedStructuredDataValidatorImplementationAddress,
      "contracts/validators/TypedStructuredDataValidator.sol:TypedStructuredDataValidator",
      [],
    );

    versions[config.newTag].contracts.TypedStructuredDataValidatorProxy = typedStructuredDataValidatorProxy;
    versions[config.newTag].contracts.TypedStructuredDataValidator = typedStructuredDataValidatorImplementationAddress;

    console.log("TypedStructuredDataValidatorProxy deployed to: ", typedStructuredDataValidatorProxy);
    console.log("TypedStructuredDataValidator implementation: ", typedStructuredDataValidatorImplementationAddress);

    // Set the data validator in PoolFactory
    const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
    const setDataValidatorTxData = new ethers.utils.Interface(PoolFactory.abi).encodeFunctionData("setDataValidator", [
      typedStructuredDataValidatorProxy,
    ]);
    await proposeTx(
      poolFactoryProxy,
      setDataValidatorTxData,
      "Set TypedStructuredDataValidator in PoolFactory",
      config,
      addresses,
    );
  }
};
