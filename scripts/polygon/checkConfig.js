const { ethers } = require("hardhat");
const fs = require("fs");
const fsp = fs.promises;
const { expect, assert, use } = require("chai");
const chaiAlmost = require("chai-almost");
const axios = require("axios");
const csv = require("csvtojson");
const ProxyAdmin = require("@openzeppelin/contracts/build/contracts/ProxyAdmin.json");

use(chaiAlmost());

const versions = require("../../publish/polygon/versions.json");
const { getTag, isSameBytecode } = require("../Helpers");

// CSV
const csvFileName = "./dHEDGE Assets list - Polygon.csv";

// Coingecko API
const coingeckoNetwork = "polygon-pos";

// Polygon addresses
const protocolDao = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
const uberPool = "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3";
const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";

let version, signer;
let proxyAdmin, poolFactory, governance, assetHandler; // contracts
let poolFactoryAddress, assetHandlerAddress; // proxy implementations
let owner = {};

const main = async () => {
  signer = (await ethers.getSigners())[0];
  // version = await getTag();
  version = "v2.4.0"; // TODO: replace with getTag() once new version updated

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

  let contracts = versions[version].contracts;

  // create contract instances
  proxyAdmin = new ethers.Contract(proxyAdminAddress, ProxyAdmin.abi, signer);
  contracts["ProxyAdmin"] = proxyAdminAddress;

  poolFactoryProxy = PoolFactoryProxy.attach(contracts.PoolFactoryProxy);
  poolFactoryAddress = await proxyAdmin.getProxyImplementation(poolFactoryProxy.address);
  poolFactory = PoolFactory.attach(poolFactoryAddress);
  contracts["PoolFactory"] = poolFactoryAddress;
  console.log("poolFactory implementation:", poolFactoryAddress);

  assetHandlerProxy = AssetHandler.attach(contracts.AssetHandlerProxy);
  assetHandlerAddress = await proxyAdmin.getProxyImplementation(assetHandlerProxy.address);
  assetHandler = AssetHandler.attach(assetHandlerAddress);
  contracts["AssetHandler"] = assetHandlerAddress;
  console.log("assetHandler implementation:", assetHandlerAddress);

  governance = Governance.attach(contracts.Governance);
  sushiLPAssetGuard = SushiLPAssetGuard.attach(contracts.SushiLPAssetGuard);
  poolLogic = PoolLogic.attach(contracts.PoolLogic);
  poolManagerLogic = PoolManagerLogic.attach(contracts.PoolManagerLogic);

  // Check ownership
  console.log("Checking ownership..");

  owner.proxyAdmin = await proxyAdmin.owner();
  owner.poolFactoryProxy = await poolFactoryProxy.owner();
  owner.governance = await governance.owner();
  owner.assetHandlerProxy = await assetHandlerProxy.owner();
  owner.sushiLPAssetGuard = await sushiLPAssetGuard.owner();

  expect(owner.proxyAdmin).to.equal(protocolDao);
  expect(owner.poolFactoryProxy).to.equal(protocolDao);
  expect(owner.governance).to.equal(protocolDao);
  expect(owner.assetHandlerProxy).to.equal(protocolDao);
  expect(owner.sushiLPAssetGuard).to.equal(protocolDao);

  // Check Factory settings
  console.log("Checking Factory settings..");

  const uberpoolSetting = await poolFactoryProxy.daoAddress();
  expect(uberpoolSetting).to.equal(uberPool);

  const governanceSetting = await poolFactoryProxy.governanceAddress();
  expect(governanceSetting).to.equal(governance.address);

  const assetHandlerSetting = await poolFactoryProxy.getAssetHandler();
  expect(assetHandlerSetting).to.equal(assetHandlerProxy.address);

  // Check Assets settings against latest Assets CSV file
  console.log("Checking assets..");

  const assets = versions[version].contracts.Assets;
  const csvAssets = await csv().fromFile(csvFileName);

  // Check for any new assets in the CSV
  for (const csvAsset of csvAssets) {
    let foundInVersions = false;
    for (const asset of assets) {
      if (csvAsset.Address === asset.asset) foundInVersions = true;
    }
    assert(foundInVersions, `Couldn't find ${csvAsset["Asset Name"]} address in published versions.json list.`);
  }

  for (const asset of assets) {
    const assetAddress = asset.asset;
    const assetPrice = parseInt(await poolFactoryProxy.getAssetPrice(assetAddress));
    const assetType = parseInt(await poolFactoryProxy.getAssetType(assetAddress));

    assert(assetPrice > 0, `${asset.name} price is not above 0`);
    assert(
      assetType == parseInt(asset.assetType),
      `${asset.name} assetType mismatch. Deployed assetType = ${asset.assetType}, Contract assetType = ${assetType}`,
    );

    let foundInCsv = false;
    for (const csvAsset of csvAssets) {
      if (csvAsset.Address == assetAddress) {
        foundInCsv = true;
        assert(
          assetType == parseInt(csvAsset.AssetType),
          `${asset.name} assetType mismatch. CSV assetType = ${csvAsset.AssetType}, Contract assetType = ${assetType}`,
        );
      }
    }
    assert(foundInCsv, `Couldn't find ${asset.name} address in the Assets CSV.`);

    // Check primitive asset prices against Coingecko (correct price oracle config)
    const assetPriceUsd = assetPrice / 1e18;
    let coingeckoAssetPriceUsd;

    if (assetType == 0 || assetType == 1 || assetType == 4) {
      const url = `https://api.coingecko.com/api/v3/simple/token_price/${coingeckoNetwork}?contract_addresses=${assetAddress}&vs_currencies=usd&include_market_cap=false&include_24hr_vol=false&include_24hr_change=false&include_last_updated_at=true`;
      try {
        const { data } = await axios.get(url);
        coingeckoAssetPriceUsd = data[assetAddress].usd;

        const approxEq = (v1, v2, diff = 0.01) => Math.abs(1 - v1 / v2) <= diff;

        assert(
          approxEq(assetPriceUsd, coingeckoAssetPriceUsd),
          `${asset.name} price doesn't match Coingecko. dHEDGE price ${assetPriceUsd}, Coingecko price ${coingeckoAssetPriceUsd}`,
        );
      } catch (err) {
        console.error(err);
      }
    }
    console.log(
      `${asset.name} Asset type: ${assetType}, Asset price: ${assetPriceUsd}, Coingecko price: ${coingeckoAssetPriceUsd}`,
    );
  }

  // Check latest contract bytecodes (what needs to be upgraded on next release)
  console.log("Checking latest bytecodes against last deployment..");
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

  const bytecodeErrors = [];
  for (const contract of contractsArray) {
    const creationBytecode = contract.contract.bytecode;
    const runtimeBytecode = await ethers.provider.getCode(contracts[contract.name]);
    const bytecodeCheck = isSameBytecode(creationBytecode, runtimeBytecode);
    if (runtimeBytecode.length < 10) bytecodeErrors.push(`Missing bytecode in deployed address for ${contract.name}`);
    if (!bytecodeCheck) bytecodeErrors.push(`Bytecode mismatch for ${contract.name}`);
  }

  assert(!bytecodeErrors.length, `Latest bytecode vs last deployment: ${bytecodeErrors}`);

  console.log("Checks complete!");
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
