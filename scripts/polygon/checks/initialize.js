const { ethers } = require("hardhat");
const { use } = require("chai");
const chaiAlmost = require("chai-almost");
const ProxyAdmin = require("@openzeppelin/contracts/build/contracts/ProxyAdmin.json");

const { getTag } = require("../../Helpers");

use(chaiAlmost());

const init = async (environment, deployedVersion = "") => {
  console.log("Initializing contracts and variables..", environment);

  const {
    versionsFileName,
    balancerLpsFileName,
    assetsFileName,
    namesFileName,
    assetGuardsFileName,
    contractGuardsFileName,
  } = await getEnvironmentFiles(environment);

  const { proxyAdminOwner, proxyAdminAddress, protocolDao, protocolTreasury, balancerV2VaultAddress } =
    await getEnvironmentContracts(environment);

  const versions = require(versionsFileName);
  const balancerLps = balancerLpsFileName ? require(balancerLpsFileName) : [];
  let version;
  const signer = (await ethers.getSigners())[0];
  if (!deployedVersion) {
    version = await getTag();
  } else {
    version = deployedVersion;
  }

  const PoolFactoryProxy = await ethers.getContractFactory("PoolFactory");
  const PoolFactory = PoolFactoryProxy;
  const Governance = await ethers.getContractFactory("Governance");
  const AssetHandlerProxy = await ethers.getContractFactory("AssetHandler");
  const AssetHandler = AssetHandlerProxy;
  const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
  const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");

  let contracts;
  try {
    contracts = versions[version].contracts;
  } catch (error) {
    throw `Couldn't get version ${version} from the published versions JSON file. Try using "--v v2.X.Y" in the command to specify existing deployed version.`;
  }

  // create contract instances
  const proxyAdmin = new ethers.Contract(proxyAdminAddress, ProxyAdmin.abi, signer);
  contracts["ProxyAdmin"] = proxyAdminAddress;

  const poolFactoryProxy = PoolFactoryProxy.attach(contracts.PoolFactoryProxy || contracts.PoolFactory.proxy);
  const poolFactoryAddress = await proxyAdmin.getProxyImplementation(poolFactoryProxy.address);
  const poolFactory = PoolFactory.attach(poolFactoryAddress);
  contracts["PoolFactory"] = poolFactoryAddress;

  const assetHandlerProxy = AssetHandler.attach(contracts.AssetHandlerProxy || contracts.AssetHandler.proxy);
  const assetHandlerAddress = await proxyAdmin.getProxyImplementation(assetHandlerProxy.address);
  const assetHandler = AssetHandler.attach(assetHandlerAddress);
  contracts["AssetHandler"] = assetHandlerAddress;

  const governance = Governance.attach(contracts.Governance);
  const sushiLPAssetGuard = contracts.SushiLPAssetGuard && SushiLPAssetGuard.attach(contracts.SushiLPAssetGuard);
  const quickLPAssetGuard = contracts.SushiLPAssetGuard && QuickLPAssetGuard.attach(contracts.QuickLPAssetGuard);

  const poolLogic = PoolLogic.attach(
    (contracts.PoolLogic && contracts.PoolLogic.implementation) || contracts.PoolLogic,
  );
  const poolManagerLogic = PoolManagerLogic.attach(
    (contracts.PoolManagerLogic && contracts.PoolManagerLogic.implementation) || contracts.PoolManagerLogic,
  );
  const openAssetGuard = contracts.OpenAssetGuard && OpenAssetGuard.attach(contracts.OpenAssetGuard);
  const oneInchV3Guard = contracts.OneInchV3Guard && OpenAssetGuard.attach(contracts.OneInchV3Guard);
  const balancerV2Guard = contracts.BalancerV2Guard && OpenAssetGuard.attach(contracts.BalancerV2Guard);

  const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
  const balancerV2Vault =
    balancerV2VaultAddress && (await ethers.getContractAt(IBalancerV2Vault.abi, balancerV2VaultAddress));

  console.log("PoolFactory Implementation:", poolFactoryAddress);
  console.log("PoolLogic Implementation:", poolLogic.address);
  console.log("PoolManagerLogic Implementation:", poolManagerLogic.address);

  console.log("Initialization complete!");
  console.log("_________________________________________");

  return {
    assetsFileName,
    balancerLps,
    balancerV2Vault,
    namesFileName,
    assetGuardsFileName,
    contractGuardsFileName,
    versions,
    version,
    signer,
    protocolDao,
    protocolTreasury,
    contracts,
    proxyAdmin,
    proxyAdminOwner,
    poolFactoryProxy,
    poolFactory,
    assetHandlerProxy,
    assetHandler,
    governance,
    sushiLPAssetGuard,
    quickLPAssetGuard,
    balancerV2Guard,
    poolLogic,
    poolManagerLogic,
    openAssetGuard,
    oneInchV3Guard,
  };
};

const getEnvironmentFiles = async (environment) => {
  let versionsFileName, assetsFileName, balancerLpsFileName, namesFileName, assetGuardsFileName, contractGuardsFileName;

  switch (environment) {
    case "polygon":
      versionsFileName = "../../../publish/matic/versions.json";
      balancerLpsFileName = "../../../config/prod/dHEDGE Asset list - Polygon Balancer LP.json";
      // CSV
      assetsFileName = "./config/prod/dHEDGE Assets list - Polygon.csv";
      namesFileName = "./config/prod/dHEDGE Governance Names - Polygon.csv";
      assetGuardsFileName = "./config/prod/dHEDGE Governance Asset Guards - Polygon.csv";
      contractGuardsFileName = "./config/prod/dHEDGE Governance Contract Guards - Polygon.csv";
      break;

    case "staging":
      versionsFileName = "../../../publish/matic/staging-versions.json";
      balancerLpsFileName = "../../../config/staging/dHEDGE Asset list - Polygon Balancer LP Staging.json";
      // CSV
      assetsFileName = "./config/staging/dHEDGE Assets list - Polygon Staging.csv";
      namesFileName = "./config/staging/dHEDGE Governance Names - Polygon Staging.csv";
      assetGuardsFileName = "./config/staging/dHEDGE Governance Asset Guards - Polygon Staging.csv";
      contractGuardsFileName = "./config/staging/dHEDGE Governance Contract Guards - Polygon Staging.csv";
      break;

    case "ovm":
      versionsFileName = "../../../publish/ovm/prod/versions.json";
      balancerLpsFileName = undefined;
      // CSV
      assetsFileName = "./config/prod-ovm/assets/Chainlink Assets.csv";
      usdPriceAggregatorAssetsFileName = "./config/prod-ovm/assets/USDPriceAggregator Assets.csv";
      namesFileName = undefined;
      assetGuardsFileName = "./config/prod-ovm/dHEDGE Governance Asset Guards.csv";
      contractGuardsFileName = "./config/prod-ovm/dHEDGE Governance Contract Guards.csv";
      break;

    default:
      throw "Invalid environment input. Should be 'prod' or 'staging'.";
  }
  return {
    versionsFileName,
    balancerLpsFileName,
    assetsFileName,
    namesFileName,
    assetGuardsFileName,
    contractGuardsFileName,
  };
};

const getEnvironmentContracts = async (environment) => {
  let protocolDao, proxyAdminAddress, protocolTreasury, balancerV2VaultAddress;

  switch (environment) {
    case "polygon":
      proxyAdminOwner = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
      proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
      protocolDao = proxyAdminOwner;
      protocolTreasury = "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3";
      balancerV2VaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
      break;

    case "staging":
      proxyAdminOwner = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
      proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
      protocolDao = proxyAdminOwner;
      protocolTreasury = "0x51150F973c2b0537642f5AE8911A49567598808f";
      balancerV2VaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
      break;

    case "ovm":
      protocolDao = "0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08";
      proxyAdminOwner = "0xef31D75A2f85CfDD9032158A2CEB773C84d79192";
      proxyAdminAddress = "0x9FEE88a18479bf7f0D41Da03819538AA7A617730";
      protocolTreasury = "0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc";
      break;

    default:
      throw "Invalid environment input. Should be 'prod' or 'staging'.";
  }
  return { proxyAdminOwner, proxyAdminAddress, protocolDao, protocolTreasury, balancerV2VaultAddress };
};

module.exports = { init };
