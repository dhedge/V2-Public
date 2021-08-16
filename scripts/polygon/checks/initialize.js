const { ethers } = require("hardhat");
const { use } = require("chai");
const chaiAlmost = require("chai-almost");
const ProxyAdmin = require("@openzeppelin/contracts/build/contracts/ProxyAdmin.json");

const { getTag } = require("../../Helpers");

use(chaiAlmost());

let proxyAdmin, poolFactory, governance, assetHandler; // contracts
let poolFactoryAddress, assetHandlerAddress; // proxy implementations

const init = async (environment, deployedVersion = "") => {
  console.log("Initializing contracts and variables..");

  const {
    versionsFileName,
    assetsFileName,
    namesFileName,
    assetGuardsFileName,
    contractGuardsFileName,
  } = await getEnvironmentFiles(environment);

  const { proxyAdminOwner, proxyAdminAddress, protocolDao, protocolTreasury } = await getEnvironmentContracts(
    environment,
  );

  const versions = require(versionsFileName);
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

  const contractsArray = [
    { contract: Governance, name: "Governance" },
    { contract: PoolFactory, name: "PoolFactory" },
    { contract: PoolLogic, name: "PoolLogic" },
    { contract: PoolManagerLogic, name: "PoolManagerLogic" },
    { contract: AssetHandler, name: "AssetHandler" },
    { contract: ERC20Guard, name: "ERC20Guard" },
    { contract: UniswapV2RouterGuard, name: "UniswapV2RouterGuard" },
    { contract: SushiMiniChefV2Guard, name: "SushiMiniChefV2Guard" },
    { contract: SushiLPAssetGuard, name: "SushiLPAssetGuard" },
  ];

  let contracts = versions[version].contracts;

  // create contract instances
  proxyAdmin = new ethers.Contract(proxyAdminAddress, ProxyAdmin.abi, signer);
  contracts["ProxyAdmin"] = proxyAdminAddress;

  poolFactoryProxy = PoolFactoryProxy.attach(contracts.PoolFactoryProxy);
  poolFactoryAddress = await proxyAdmin.getProxyImplementation(poolFactoryProxy.address);
  poolFactory = PoolFactory.attach(poolFactoryAddress);
  contracts["PoolFactory"] = poolFactoryAddress;

  assetHandlerProxy = AssetHandler.attach(contracts.AssetHandlerProxy);
  assetHandlerAddress = await proxyAdmin.getProxyImplementation(assetHandlerProxy.address);
  assetHandler = AssetHandler.attach(assetHandlerAddress);
  contracts["AssetHandler"] = assetHandlerAddress;

  governance = Governance.attach(contracts.Governance);
  sushiLPAssetGuard = SushiLPAssetGuard.attach(contracts.SushiLPAssetGuard);
  poolLogic = PoolLogic.attach(contracts.PoolLogic);
  poolManagerLogic = PoolManagerLogic.attach(contracts.PoolManagerLogic);

  console.log("Initialization complete!");
  console.log("_________________________________________");

  return {
    assetsFileName,
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
    poolLogic,
    poolManagerLogic,
  };
};

const getEnvironmentFiles = async (environment) => {
  let versions, assetsFileName, namesFileName, assetGuardsFileName, contractGuardsFileName;

  switch (environment) {
    case "prod":
      versionsFileName = "../../../publish/matic/versions.json";
      // CSV
      assetsFileName = "./config/prod/dHEDGE Assets list - Polygon.csv";
      namesFileName = "./config/prod/dHEDGE Governance Names - Polygon.csv";
      assetGuardsFileName = "./config/prod/dHEDGE Governance Asset Guards - Polygon.csv";
      contractGuardsFileName = "./config/prod/dHEDGE Governance Contract Guards - Polygon.csv";
      break;

    case "staging":
      versionsFileName = "../../../publish/matic/staging-versions.json";
      // CSV
      assetsFileName = "./config/staging/dHEDGE Assets list - Polygon Staging.csv";
      namesFileName = "./config/staging/dHEDGE Governance Names - Polygon Staging.csv";
      assetGuardsFileName = "./config/staging/dHEDGE Governance Asset Guards - Polygon Staging.csv";
      contractGuardsFileName = "./config/staging/dHEDGE Governance Contract Guards - Polygon Staging.csv";
      break;

    default:
      throw "Invalid environment input. Should be 'prod' or 'staging'.";
  }
  return { versionsFileName, assetsFileName, namesFileName, assetGuardsFileName, contractGuardsFileName };
};

const getEnvironmentContracts = async (environment) => {
  let protocolDao, proxyAdminAddress, protocolTreasury;

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
      protocolDao = "0x51150F973c2b0537642f5AE8911A49567598808f";
      protocolTreasury = "0x51150F973c2b0537642f5AE8911A49567598808f";
      break;

    default:
      throw "Invalid environment input. Should be 'prod' or 'staging'.";
  }
  return { proxyAdminOwner, proxyAdminAddress, protocolDao, protocolTreasury };
};

module.exports = { init };
