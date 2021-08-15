const { ethers } = require("hardhat");
const fs = require("fs");
const fsp = fs.promises;
const { expect, assert, use } = require("chai");
const chaiAlmost = require("chai-almost");
const axios = require("axios");
const csv = require("csvtojson");
const ProxyAdmin = require("@openzeppelin/contracts/build/contracts/ProxyAdmin.json");

const versions = require("../../../publish/polygon/versions.json");
const { deploy } = require("@openzeppelin/hardhat-upgrades/dist/utils");
const { getTag } = require("../../Helpers");

use(chaiAlmost());

// Polygon addresses
const protocolDao = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
const protocolTreasury = "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3";

// CSV
const assetsFileName = "./dHEDGE Assets list - Polygon.csv";
const namesFileName = "./dHEDGE Governance Names - Polygon.csv";
const assetGuardsFileName = "./dHEDGE Governance Asset Guards - Polygon.csv";
const contractGuardsFileName = "./dHEDGE Governance Contract Guards - Polygon.csv";

let version, signer;
let proxyAdmin, poolFactory, governance, assetHandler; // contracts
let poolFactoryAddress, assetHandlerAddress; // proxy implementations
let owner = {};

const init = async (deployedVersion = "") => {
  console.log("Initializing contracts and variables..");

  signer = (await ethers.getSigners())[0];
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
    version,
    signer,
    protocolDao,
    protocolTreasury,
    contracts,
    contractsArray,
    proxyAdmin,
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

module.exports = { init };
