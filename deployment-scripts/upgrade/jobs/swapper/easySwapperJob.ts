import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

const swapperFeeNumerator = 10; // 0.1% buy fee to enable Stablecoin Yield buys by managers at low cost and without need for secondary market
const swapperFeeDenominator = 10000;

export const easySwapperJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const network = await ethers.provider.getNetwork();
  console.log("Network:", network.name);
  console.log("Will deploy easySwapper");

  if (config.execute) {
    const latestVersion = config.newTag;
    const dhedgeEasySwapperProxy = versions[latestVersion].contracts.DhedgeEasySwapperProxy;
    if (dhedgeEasySwapperProxy) {
      // run upgrade
      console.log("Upgrading EasySwapper");
      const { implementation } = await upgradeEasySwapper(hre, config, versions, addresses);
      versions[latestVersion].contracts.DhedgeEasySwapper = implementation.address;
      console.log("DhedgeEasySwapper upgraded. New Implementation address: ", implementation.address);
    } else {
      // first time deploy
      console.log("Deploying new EasySwapper");
      const { proxy, implementation } = await deployEasySwapper(hre, config, versions, addresses);
      versions[latestVersion].contracts.DhedgeEasySwapperProxy = proxy.address;
      versions[latestVersion].contracts.DhedgeEasySwapper = implementation.address;
      console.log("DhedgeEasySwapper deployed to: ", proxy.address);
    }
  }
};

const deployEasySwapper = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;
  const latestVersion = config.newTag;
  const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
  const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
  const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);

  // Check config for Toros allowed pools to be used for easy swapper
  if (!addresses.torosEasySwapperAllowedPools) {
    throw new Error("torosEasySwapperAllowedPools not defined");
  }

  // Deploy
  await hre.run("compile:one", { contractName: "DhedgeEasySwapper" });
  const Contract = await ethers.getContractFactory("DhedgeEasySwapper");
  const contractInitParams = [
    poolFactoryProxy,
    addresses.protocolDaoAddress,
    {
      swapRouter: versions[latestVersion].contracts.DhedgeSuperSwapper,
      weth: addresses.assets.weth,
      assetType2Router: addresses.assetType2Router || "0x0000000000000000000000000000000000000000",
      assetType5Router: addresses.assetType5Router || "0x0000000000000000000000000000000000000000",
      synthetixProps: {
        snxProxy: addresses.synthetixProxyAddress || "0x0000000000000000000000000000000000000000",
        swapSUSDToAsset: addresses.assets.dai,
        sUSDProxy: addresses.assets.susd || "0x0000000000000000000000000000000000000000",
      },
      nativeAssetWrapper: addresses.assets.nativeAssetWrapper,
    },
    swapperFeeNumerator,
    swapperFeeDenominator,
  ];
  const deployment = await upgrades.deployProxy(Contract, contractInitParams);
  await deployment.deployed();

  const proxy = Contract.attach(deployment.address);
  const implementationAddress = ethers.utils.hexValue(
    await provider.getStorageAt(proxy.address, addresses.implementationStorageAddress),
  );
  const implementation = Contract.attach(implementationAddress);

  // Verify implementation
  await tryVerify(hre, implementation.address, "contracts/EasySwapper/DhedgeEasySwapper.sol:DhedgeEasySwapper", []);

  console.log("easySwapperProxy deployed to:", proxy.address);
  console.log("easySwapper implementation:", implementation.address);

  console.log("EasySwapper Setting Allowed Pools");
  for (const leveragePool of addresses.torosEasySwapperAllowedPools) {
    await proxy.setPoolAllowed(leveragePool, true);
  }

  console.log("EasySwapper Transferring ownership");
  await proxy.transferOwnership(addresses.protocolDaoAddress);

  try {
    const addCustomCooldownWhitelistData = PoolFactoryABI.encodeFunctionData("addCustomCooldownWhitelist", [
      proxy.address,
    ]);

    await proposeTx(
      poolFactoryProxy,
      addCustomCooldownWhitelistData,
      "Add new easy swapper to whitelist",
      config,
      addresses,
    );
  } catch {
    console.log("Deployed successfully, but unable to propose whitelist tx");
  }

  return { proxy, implementation };
};

const upgradeEasySwapper = async (
  hre: HardhatRuntimeEnvironment,
  config: IUpgradeConfig,
  versions: IVersions,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
  const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

  const proxy = versions[config.oldTag].contracts.DhedgeEasySwapperProxy;

  // Deploy
  await hre.run("compile:one", { contractName: "DhedgeEasySwapper" });

  const Contract = await ethers.getContractFactory("DhedgeEasySwapper");
  const newLogic = await upgrades.prepareUpgrade(proxy, Contract);
  console.log("New logic deployed to: ", newLogic);
  const implementation = await ethers.getContractAt("DhedgeEasySwapper", newLogic);

  await tryVerify(hre, newLogic, "contracts/EasySwapper/DhedgeEasySwapper.sol:DhedgeEasySwapper", []);

  const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [proxy, newLogic]);
  await proposeTx(addresses.proxyAdminAddress, upgradeABI, "Upgrade Easy Swapper", config, addresses);

  return { proxy, implementation };
};
