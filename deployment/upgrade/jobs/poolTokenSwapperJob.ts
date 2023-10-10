import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";

import { proposeTx, tryVerify } from "../../deploymentHelpers";
import { Address, IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions, IVersion } from "../../types";
import { PoolTokenSwapper, PoolTokenSwapper__factory } from "../../../types";

type UpdateConfig = NonNullable<IAddresses["poolTokenSwapper"]>;

/**
 * Handles PoolTokenSwapper contract deployment, configuration changes and upgrades
 * @param config Configuration for Safe transaction proposals
 * @param hre Hardhat Runtime Environment
 * @param versions Deployed contracts
 * @param _ Configuration file names
 * @param addresses Configurated addresses on the chain
 */
export const poolTokenSwapperJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const version = versions[config.newTag];
  const deployedPoolTokenSwapperProxy = versions[config.newTag].contracts.PoolTokenSwapperProxy;
  const PoolTokenSwapper = await ethers.getContractFactory("PoolTokenSwapper");

  // If we've never deployed the proxy
  if (!deployedPoolTokenSwapperProxy) {
    console.log("Will deploy PoolTokenSwapper");

    if (!addresses.poolTokenSwapper) {
      console.warn("PoolTokenSwapper configuration is missing");
      return;
    }

    if (config.execute) {
      const poolTokenSwapper = await deployPoolTokenSwapper(hre, PoolTokenSwapper, addresses, version);

      if (!poolTokenSwapper) {
        console.warn("Invalid PoolTokenSwapper configuration");
        return;
      }

      version.contracts.PoolTokenSwapperProxy = poolTokenSwapper.proxy;
      version.contracts.PoolTokenSwapper = poolTokenSwapper.implementation;
    }
  }
  // Otherwise check for any configuration changes or upgrade the implementation
  else {
    console.log("Will upgrade PoolTokenSwapper");

    const configUpdates: UpdateConfig = await getConfigUpdates(hre, deployedPoolTokenSwapperProxy, addresses);

    if (config.execute) {
      if (
        configUpdates.manager ||
        configUpdates.assets.length ||
        configUpdates.pools.length ||
        configUpdates.swapWhitelist.length
      ) {
        // Configuration changed. Propose transactions to update it
        console.log("PoolTokenSwapper config changed");
        await updatePoolTokenSwapperConfig(
          config,
          PoolTokenSwapper,
          addresses,
          deployedPoolTokenSwapperProxy,
          configUpdates,
        );
      } else {
        // Otherwise upgrade the contract
        const poolTokenSwapperImplementation = await upgradePoolTokenSwapper(
          config,
          hre,
          PoolTokenSwapper,
          addresses,
          deployedPoolTokenSwapperProxy,
        );
        versions[config.newTag].contracts.PoolTokenSwapper = poolTokenSwapperImplementation;
      }
    }
  }
};

const deployPoolTokenSwapper = async (
  hre: HardhatRuntimeEnvironment,
  PoolTokenSwapper: PoolTokenSwapper__factory,
  addresses: IAddresses,
  version: IVersion,
) => {
  console.log("Creating a new deployment of PoolTokenSwapper");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  if (!addresses.poolTokenSwapper) {
    return;
  }

  const deployConfig = [
    version.contracts.PoolFactoryProxy,
    addresses.poolTokenSwapper.manager,
    addresses.poolTokenSwapper.assets,
    addresses.poolTokenSwapper.pools,
    addresses.poolTokenSwapper.swapWhitelist,
  ];

  const poolTokenSwapperProxy = <PoolTokenSwapper>await upgrades.deployProxy(PoolTokenSwapper, deployConfig);
  await poolTokenSwapperProxy.deployed();

  const poolTokenSwapperImplementationAddress = await getImplementationAddress(
    ethers.provider,
    poolTokenSwapperProxy.address,
  );
  const poolTokenSwapperImplementation = PoolTokenSwapper.attach(poolTokenSwapperImplementationAddress);

  await tryVerify(
    hre,
    poolTokenSwapperImplementation.address,
    "contracts/swappers/poolTokenSwapper/PoolTokenSwapper.sol:PoolTokenSwapper",
    [],
  );

  console.log("PoolTokenSwapper proxy deployed at ", poolTokenSwapperProxy.address);
  console.log("PoolTokenSwapper implementation deployed at ", poolTokenSwapperImplementationAddress);

  await poolTokenSwapperProxy.transferOwnership(addresses.protocolDaoAddress);
  console.log("Transferred ownership to Protocol DAO", addresses.protocolDaoAddress);

  return { proxy: poolTokenSwapperProxy.address, implementation: poolTokenSwapperImplementation.address };
};

const upgradePoolTokenSwapper = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  PoolTokenSwapper: PoolTokenSwapper__factory,
  addresses: IAddresses,
  poolTokenSwapperProxy: Address,
) => {
  console.log("Upgrading PoolTokenSwapper");

  const ethers = hre.ethers;
  const upgrades = hre.upgrades;

  const poolTokenSwapperImplementationAddress = await upgrades.prepareUpgrade(poolTokenSwapperProxy, PoolTokenSwapper);
  console.log("PoolTokenSwapper implementation deployed to: ", poolTokenSwapperImplementationAddress);

  console.log("Initializing implementation...");
  const poolTokenSwapperImplementation = PoolTokenSwapper.attach(poolTokenSwapperImplementationAddress);

  await tryVerify(
    hre,
    poolTokenSwapperImplementation.address,
    "contracts/swappers/poolTokenSwapper/PoolTokenSwapper.sol:PoolTokenSwapper",
    [],
  );

  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [
    poolTokenSwapperProxy,
    poolTokenSwapperImplementationAddress,
  ]);
  await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade PoolTokenSwapper", config, addresses);

  console.log("PoolTokenSwapper implementation deployed at ", poolTokenSwapperImplementation);

  return poolTokenSwapperImplementation.address;
};

const updatePoolTokenSwapperConfig = async (
  config: IUpgradeConfig,
  PoolTokenSwapper: PoolTokenSwapper__factory,
  addresses: IAddresses,
  poolTokenSwapperProxy: Address,
  updateConfig: UpdateConfig,
) => {
  console.log("Updating PoolTokenSwapper config");

  const poolTokenSwapper = PoolTokenSwapper.attach(poolTokenSwapperProxy);

  if (updateConfig.manager) {
    const setManagerData = poolTokenSwapper.interface.encodeFunctionData("setManager", [updateConfig.manager]);
    await proposeTx(poolTokenSwapperProxy, setManagerData, "Update PoolTokenSwapper manager", config, addresses);
    console.log("New PoolTokenSwapper manager proposed");
  }

  if (updateConfig.assets) {
    const setAssetsData = poolTokenSwapper.interface.encodeFunctionData("setAssets", [updateConfig.assets]);
    await proposeTx(poolTokenSwapperProxy, setAssetsData, "Update PoolTokenSwapper assets", config, addresses);
    console.log("New PoolTokenSwapper asset updates proposed");
  }

  if (updateConfig.pools) {
    const setPoolsData = poolTokenSwapper.interface.encodeFunctionData("setPools", [updateConfig.pools]);
    await proposeTx(poolTokenSwapperProxy, setPoolsData, "Update PoolTokenSwapper pools", config, addresses);
    console.log("New PoolTokenSwapper pools updates proposed");
  }

  if (updateConfig.swapWhitelist) {
    const setSwapWhitelistData = poolTokenSwapper.interface.encodeFunctionData("setSwapWhitelist", [
      updateConfig.swapWhitelist,
    ]);
    await proposeTx(
      poolTokenSwapperProxy,
      setSwapWhitelistData,
      "Update PoolTokenSwapper swap whitelist",
      config,
      addresses,
    );
    console.log("New PoolTokenSwapper swap whitelist updates proposed");
  }

  return true;
};

const getConfigUpdates = async (
  hre: HardhatRuntimeEnvironment,
  poolTokenSwapperProxy: Address,
  addresses: IAddresses,
) => {
  const PoolTokenSwapper = await hre.ethers.getContractFactory("PoolTokenSwapper");
  const poolTokenSwapper = PoolTokenSwapper.attach(poolTokenSwapperProxy);
  const configChanges: UpdateConfig = { manager: "", assets: [], pools: [], swapWhitelist: [] };

  if (addresses.poolTokenSwapper) {
    const configManager = addresses.poolTokenSwapper?.manager;
    const contractManager = await poolTokenSwapper.manager();

    if (configManager && configManager !== contractManager) {
      configChanges.manager = configManager;
    }

    for (const asset of addresses.poolTokenSwapper.assets) {
      const contractAssetEnabled = await poolTokenSwapper.assetConfiguration(asset.asset);

      if (asset.assetEnabled !== contractAssetEnabled) {
        configChanges.assets.push(asset);
      }
    }

    for (const pool of addresses.poolTokenSwapper.pools) {
      const { poolEnabled: contractPoolEnabled, poolSwapFee: contractPoolSwapFee } =
        await poolTokenSwapper.poolConfiguration(pool.pool);

      if (pool.poolEnabled !== contractPoolEnabled || pool.poolSwapFee !== contractPoolSwapFee.toNumber()) {
        configChanges.pools.push(pool);
      }
    }

    for (const element of addresses.poolTokenSwapper.swapWhitelist) {
      const swapWhilistStatus = await poolTokenSwapper.swapWhitelist(element.sender);

      if (element.status !== swapWhilistStatus) {
        configChanges.swapWhitelist.push(element);
      }
    }
  }

  return configChanges;
};
