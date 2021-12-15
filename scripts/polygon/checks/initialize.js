const { ethers } = require("hardhat");
const { use } = require("chai");
const chaiAlmost = require("chai-almost");
const ProxyAdmin = require("@openzeppelin/contracts/build/contracts/ProxyAdmin.json");

const { getTag } = require("../../Helpers");

use(chaiAlmost());

const init = async (environment, deployedVersion = "") => {
  console.log("Initializing contracts and variables..");

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
  const balancerLps = require(balancerLpsFileName);
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
  const UniswapV2RouterGuard = await ethers.getContractFactory("ERC20Guard");
  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
  const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
  const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
  const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
  const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
  const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
  const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
  const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
  const OneInchV3Guard = await ethers.getContractFactory("OneInchV3Guard");
  const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
  const PoolPerformance = await ethers.getContractFactory("PoolPerformance");

  const contractsArray = [
    { contract: Governance, name: "Governance" },
    { contract: PoolFactory, name: "PoolFactory" },
    { contract: PoolLogic, name: "PoolLogic" },
    { contract: PoolManagerLogic, name: "PoolManagerLogic" },
    { contract: AssetHandler, name: "AssetHandler" },
    { contract: ERC20Guard, name: "ERC20Guard" },
    { contract: UniswapV2RouterGuard, name: "UniswapV2RouterGuard" },
    { contract: SushiMiniChefV2Guard, name: "SushiMiniChefV2Guard" },
    { contract: AaveLendingPoolAssetGuard, name: "AaveLendingPoolAssetGuard" },
    { contract: AaveLendingPoolGuard, name: "AaveLendingPoolGuard" },
    { contract: LendingEnabledAssetGuard, name: "LendingEnabledAssetGuard" },
    { contract: AaveIncentivesControllerGuard, name: "AaveIncentivesControllerGuard" },
    { contract: OpenAssetGuard, name: "OpenAssetGuard" },
    { contract: QuickLPAssetGuard, name: "QuickLPAssetGuard" },
    { contract: QuickStakingRewardsGuard, name: "QuickStakingRewardsGuard" },
    { contract: OneInchV3Guard, name: "OneInchV3Guard" },
    { contract: BalancerV2Guard, name: "BalancerV2Guard" },
    { contract: PoolPerformance, name: "PoolPerformance" },
  ];

  let contracts;
  try {
    contracts = versions[version].contracts;
  } catch (error) {
    throw `Couldn't get version ${version} from the published versions JSON file. Try using "--v v2.X.Y" in the command to specify existing deployed version.`;
  }

  // create contract instances
  const proxyAdmin = new ethers.Contract(proxyAdminAddress, ProxyAdmin.abi, signer);
  contracts["ProxyAdmin"] = proxyAdminAddress;

  const poolFactoryProxy = PoolFactoryProxy.attach(contracts.PoolFactoryProxy);
  const poolFactoryAddress = await proxyAdmin.getProxyImplementation(poolFactoryProxy.address);
  const poolFactory = PoolFactory.attach(poolFactoryAddress);
  contracts["PoolFactory"] = poolFactoryAddress;

  const assetHandlerProxy = AssetHandler.attach(contracts.AssetHandlerProxy);
  const assetHandlerAddress = await proxyAdmin.getProxyImplementation(assetHandlerProxy.address);
  const assetHandler = AssetHandler.attach(assetHandlerAddress);
  contracts["AssetHandler"] = assetHandlerAddress;

  const governance = Governance.attach(contracts.Governance);
  const sushiLPAssetGuard = SushiLPAssetGuard.attach(contracts.SushiLPAssetGuard);
  const quickLPAssetGuard = QuickLPAssetGuard.attach(contracts.QuickLPAssetGuard);
  const poolLogic = PoolLogic.attach(contracts.PoolLogic);
  const poolManagerLogic = PoolManagerLogic.attach(contracts.PoolManagerLogic);
  const openAssetGuard = OpenAssetGuard.attach(contracts.OpenAssetGuard);
  const oneInchV3Guard = OpenAssetGuard.attach(contracts.OneInchV3Guard);
  const balancerV2Guard = OpenAssetGuard.attach(contracts.BalancerV2Guard);

  const IBalancerV2Vault = await hre.artifacts.readArtifact("IBalancerV2Vault");
  const balancerV2Vault = await ethers.getContractAt(IBalancerV2Vault.abi, balancerV2VaultAddress);

  console.log("PoolFactory Implementation:", poolFactoryAddress);
  console.log("PoolLogic Implementation:", contracts.PoolLogic);
  console.log("PoolManagerLogic Implementation:", contracts.PoolManagerLogic);

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
    contractsArray,
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
    case "prod":
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
  let protocolDao, proxyAdminAddress, protocolTreasury;
  const balancerV2VaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";

  switch (environment) {
    case "prod":
      proxyAdminOwner = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
      proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
      protocolDao = proxyAdminOwner;
      protocolTreasury = "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3";
      break;

    case "staging":
      proxyAdminOwner = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
      proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
      protocolDao = proxyAdminOwner;
      protocolTreasury = "0x51150F973c2b0537642f5AE8911A49567598808f";
      break;

    default:
      throw "Invalid environment input. Should be 'prod' or 'staging'.";
  }
  return { proxyAdminOwner, proxyAdminAddress, protocolDao, protocolTreasury, balancerV2VaultAddress };
};

module.exports = { init };
