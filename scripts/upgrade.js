const fs = require("fs");
const csv = require("csvtojson");
const {
  writeCsv,
  getTag,
  hasDuplicates,
  tryVerify,
  proposeTx,
  nonceLog,
  checkAsset,
  checkBalancerLpAsset,
  getAggregator,
} = require("./Helpers");
const Decimal = require("decimal.js");
const proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";

// File Names
const stagingBalancerConfig = require("../config/staging/dHEDGE Asset list - Polygon Balancer LP Staging.json");
const prodBalancerConfig = require("../config/prod/dHEDGE Asset list - Polygon Balancer LP.json");
const stagingAssetFileName = "./config/staging/dHEDGE Assets list - Polygon Staging.csv";
const prodAssetFileName = "./config/prod/dHEDGE Assets list - Polygon.csv";
const stagingAssetGuardFileName = "./config/staging/dHEDGE Governance Asset Guards - Polygon Staging.csv";
const prodAssetGuardFileName = "./config/prod/dHEDGE Governance Asset Guards - Polygon.csv";
const stagingContractGuardFileName = "./config/staging/dHEDGE Governance Contract Guards - Polygon Staging.csv";
const prodContractGuardFileName = "./config/prod/dHEDGE Governance Contract Guards - Polygon.csv";
const stagingGovernanceNamesFileName = "./config/staging/dHEDGE Governance Names - Polygon Staging.csv";
const prodGovernanceNamesFileName = "./config/prod/dHEDGE Governance Names - Polygon.csv";
const stagingExternalAssetFileName = "./config/staging/dHEDGE Assets list - Polygon External Staging.csv";
const prodExternalAssetFileName = "./config/prod/dHEDGE Assets list - Polygon External.csv";

// Addresses
const balancerV2Vault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
const aaveProtocolDataProvider = "0x7551b5D2763519d4e37e8B81929D336De671d46d";
const sushiswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";
const quickswapRouter = "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff";
const protocolDao = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
const quickStakingRewardsFactory = "0x5eec262B05A57da9beb5FE96a34aa4eD0C5e029f";
const quickLpUsdcWethStakingRewards = "0x4A73218eF2e820987c59F838906A82455F42D98b";
const aaveIncentivesController = "0x357D51124f59836DeD84c8a1730D72B749d8BC23";
const aaveLendingPool = "0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf";
const oneInchV3Router = "0x11111112542D85B3EF69AE05771c2dCCff4fAa26";
let sushiToken, wmatic;
const sushiMiniChefV2 = "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F";

// Misc
const implementationStorage = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";

const deployBalancerV2LpAggregator = async (factory, info) => {
  const ether = "1000000000000000000";
  const divisor = info.weights.reduce((acc, w, i) => {
    if (i == 0) {
      return new Decimal(w).pow(w);
    }
    return acc.mul(new Decimal(w).pow(w));
  }, new Decimal("0"));

  const K = new Decimal(ether).div(divisor).toFixed(0);

  let matrix = [];
  for (let i = 1; i <= 20; i++) {
    const elements = [new Decimal(10).pow(i).times(ether).toFixed(0)];
    for (let j = 0; j < info.weights.length; j++) {
      elements.push(new Decimal(10).pow(i).pow(info.weights[j]).times(ether).toFixed(0));
    }
    matrix.push(elements);
  }

  const BalancerV2LPAggregator = await ethers.getContractFactory("BalancerV2LPAggregator");

  return await BalancerV2LPAggregator.deploy(
    factory,
    balancerV2Vault,
    info.pool,
    info.tokens,
    info.decimals,
    info.weights.map((w) => new Decimal(w).mul(ether).toFixed(0)),
    [
      "50000000000000000", // maxPriceDeviation: 0.05
      K,
      "100000000", // powerPrecision
      matrix, // approximationMatrix
    ],
  );
};

task("upgrade", "Upgrade contracts")
  .addOptionalParam("execute", "propose transactions", false, types.boolean)
  .addOptionalParam("poolFactory", "upgrade poolFactory", false, types.boolean)
  .addOptionalParam("assetHandler", "upgrade assetHandler", false, types.boolean)
  .addOptionalParam("poolLogic", "upgrade poolLogic", false, types.boolean)
  .addOptionalParam("poolManagerLogic", "upgrade poolManagerLogic", false, types.boolean)
  .addOptionalParam("poolPerformance", "upgrade poolPerformance", false, types.boolean)
  .addOptionalParam("assets", "deploy new assets", false, types.boolean)
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .addOptionalParam("aaveLendingPoolAssetGuard", "upgrade aaveLendingPoolAssetGuard", false, types.boolean)
  .addOptionalParam("sushiLPAssetGuard", "upgrade sushiLPAssetGuard", false, types.boolean)
  .addOptionalParam("erc20Guard", "upgrade erc20Guard", false, types.boolean)
  .addOptionalParam("lendingEnabledAssetGuard", "upgrade LendingEnabledAssetGuard", false, types.boolean)
  .addOptionalParam("uniswapV2RouterGuard", "upgrade uniswapV2RouterGuard", false, types.boolean)
  .addOptionalParam("openAssetGuard", "upgrade openAssetGuard", false, types.boolean)
  .addOptionalParam("quickLPAssetGuard", "upgrade quickLPAssetGuard", false, types.boolean)
  .addOptionalParam("balancerv2guard", "upgrade balancerV2Guard", false, types.boolean)
  .addOptionalParam("quickStakingRewardsGuard", "upgrade quickStakingRewardsGuard", false, types.boolean)
  .addOptionalParam("sushiMiniChefV2Guard", "upgrade sushiMiniChefV2Guard", false, types.boolean)
  .addOptionalParam("aaveIncentivesControllerGuard", "upgrade AaveIncentivesControllerGuard", false, types.boolean)
  .addOptionalParam("aaveLendingPoolGuard", "upgrade AaveLendingPoolGuard", false, types.boolean)
  .addOptionalParam("oneInchV3Guard", "upgrade oneInchV3Guard", false, types.boolean)
  .addOptionalParam("governanceNames", "upgrade Governance contract address mapping", false, types.boolean)
  .addOptionalParam("pause", "pause contract", false, types.boolean)
  .addOptionalParam("unpause", "unpause contract", false, types.boolean)
  .addOptionalParam("keepVersion", "keep the previous release published version. don't update it", false, types.boolean)
  .setAction(async (taskArgs) => {
    const provider = ethers.provider;
    const network = await ethers.provider.getNetwork();
    console.log("network:", network);
    const hre = require("hardhat");

    // Init tag
    const versionFile = taskArgs.production ? "versions" : "staging-versions";
    const versions = require(`../publish/${network.name}/${versionFile}.json`);

    const oldTag = Object.keys(versions)[Object.keys(versions).length - 1];
    let newTag;
    if (taskArgs.keepVersion) {
      newTag = oldTag;
    } else {
      // update to latest release version
      newTag = await getTag();
    }
    console.log(`oldTag: ${oldTag}`);
    console.log(`newTag: ${newTag}`);
    // Comment this out as assets is default to true and it's always comes with pause/unpause true
    // const checkNewVersion = !taskArgs.assets && !taskArgs.pause && !taskArgs.unpause;
    // if (checkNewVersion && newTag == oldTag) throw "Error: No new version to upgrade"; // comment out as we could deploy and overrite the current version

    // Init contracts data
    const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
    const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

    const contracts = versions[oldTag].contracts;
    versions[newTag] = new Object();
    versions[newTag].contracts = { ...contracts };
    versions[newTag].network = network;
    versions[newTag].date = new Date().toUTCString();
    let setLogic = false;
    let assetHandlerAssets = [];

    // Governance
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const governance = await ethers.getContractAt(governanceABI, contracts.Governance);

    // Asset Guard
    const assetGuardfileName = taskArgs.production ? prodAssetGuardFileName : stagingAssetGuardFileName;
    const csvAssetGuards = await csv().fromFile(assetGuardfileName);
    let newAssetGuards = new Array();

    // Contract Guard
    const contractGuardfileName = taskArgs.production ? prodContractGuardFileName : stagingContractGuardFileName;
    const csvContractGuards = await csv().fromFile(contractGuardfileName);
    let newContractGuards = new Array();

    // Governance names
    const governanceNamesfileName = taskArgs.production ? prodGovernanceNamesFileName : stagingGovernanceNamesFileName;
    const csvGovernanceNames = await csv().fromFile(governanceNamesfileName);
    let newGovernanceNames = new Array();

    // Pool Factory
    const poolFactoryProxy = contracts.PoolFactoryProxy;
    const PoolFactory = await hre.artifacts.readArtifact("PoolFactory");
    const PoolFactoryABI = new ethers.utils.Interface(PoolFactory.abi);
    const poolFactory = await ethers.getContractAt(PoolFactoryABI, poolFactoryProxy);

    if (taskArgs.pause) {
      if (!taskArgs.execute) {
        console.log("Will pause");
      } else {
        const pauseABI = PoolFactoryABI.encodeFunctionData("pause", []);
        await proposeTx(poolFactoryProxy, pauseABI, "Pause Pool Factory", taskArgs.execute);
      }
    }
    if (taskArgs.assets) {
      // look up to check if csvAsset is in the current versions
      const fileName = taskArgs.production ? prodAssetFileName : stagingAssetFileName;
      const csvAssets = await csv().fromFile(fileName);

      // Check for any accidental duplicate addresses or price feeds in the CSV
      if (await hasDuplicates(csvAssets, "Address")) throw "Duplicate 'Address' field found in assets CSV";
      if (await hasDuplicates(csvAssets, "Chainlink Price Feed"))
        throw "Duplicate 'Chainlink Price Feed' field found in assets CSV";

      const SushiLPAggregator = await ethers.getContractFactory("UniV2LPAggregator");
      for (const csvAsset of csvAssets) {
        const foundInVersions = await checkAsset(csvAsset, contracts, poolFactory, assetHandlerAssets);
        if (!foundInVersions) {
          const assetType = csvAsset.AssetType;
          switch (assetType) {
            case "2":
              if (!taskArgs.execute) {
                console.log("Will deploy asset", csvAsset["Asset Name"]);
                break;
              }

              // Deploy Sushi LP Aggregator
              console.log("Deploying ", csvAsset["Asset Name"]);
              const sushiLPAggregator = await SushiLPAggregator.deploy(csvAsset.Address, contracts.PoolFactoryProxy);
              await sushiLPAggregator.deployed();
              console.log(`${csvAsset["Asset Name"]} SushiLPAggregator deployed at ${sushiLPAggregator.address}`);
              assetHandlerAssets.push({
                name: csvAsset["Asset Name"],
                asset: csvAsset.Address,
                assetType: assetType,
                aggregator: sushiLPAggregator.address,
              });
              break;
            case "3":
              if (!taskArgs.execute) {
                console.log("Will deploy asset", csvAsset["Asset Name"]);
                break;
              }

              let usdPriceAggregatorAddress;
              if (!csvAsset["Chainlink Price Feed"]) {
                // Deploy USDPriceAggregator
                const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
                const usdPriceAggregator = await USDPriceAggregator.deploy();
                await usdPriceAggregator.deployed();
                usdPriceAggregatorAddress = usdPriceAggregator.address;
              } else {
                // Use configured USDPriceAggregator
                usdPriceAggregatorAddress = csvAsset["Chainlink Price Feed"];
              }

              console.log("USDPriceAggregator deployed at", usdPriceAggregatorAddress);
              assetHandlerAssets.push({
                name: csvAsset["Asset Name"],
                asset: csvAsset.Address,
                assetType: assetType,
                aggregator: usdPriceAggregatorAddress,
              });
              break;
            default:
              if (!taskArgs.execute) {
                console.log("Will deploy asset", csvAsset["Asset Name"]);
                break;
              }
              console.log(`Adding new asset to AssetHandler: ${csvAsset["Asset Name"]}`);
              const aggregator = await getAggregator(csvAsset);
              assetHandlerAssets.push({
                name: csvAsset["Asset Name"],
                asset: csvAsset.Address,
                assetType: assetType,
                aggregator: aggregator,
              });
          }
        }
      }

      const balancerLps = taskArgs.production ? prodBalancerConfig : stagingBalancerConfig;
      for (const balancerLp of balancerLps) {
        const foundInVersions = await checkBalancerLpAsset(balancerLp, contracts, poolFactory, assetHandlerAssets);
        if (!foundInVersions) {
          if (!taskArgs.execute) {
            console.log("Will deploy Balancer V2 LP asset", balancerLp.name);
          } else {
            // Deploy Balancer LP Aggregator
            console.log("Deploying ", balancerLp.name);
            const balancerV2Aggregator = await deployBalancerV2LpAggregator(
              contracts.PoolFactoryProxy,
              balancerLp.data,
            );
            await balancerV2Aggregator.deployed();
            console.log(`${balancerLp.name} BalancerV2LPAggregator deployed at ${balancerV2Aggregator.address}`);
            assetHandlerAssets.push({
              name: balancerLp.name,
              asset: balancerLp.data.pool,
              assetType: balancerLp.assetType,
              aggregator: balancerV2Aggregator.address,
            });
          }
        }
      }

      const AssetHandlerLogic = await hre.artifacts.readArtifact("AssetHandler");
      const assetHandlerLogic = new ethers.utils.Interface(AssetHandlerLogic.abi);
      const addAssetsABI = assetHandlerLogic.encodeFunctionData("addAssets", [assetHandlerAssets]);

      if (assetHandlerAssets.length > 0) {
        await proposeTx(contracts.AssetHandlerProxy, addAssetsABI, "Update assets in Asset Handler", taskArgs.execute);
        versions[newTag].contracts.Assets = [...versions[newTag].contracts.Assets, ...assetHandlerAssets];
      }
    }
    if (taskArgs.poolFactory) {
      if (!taskArgs.execute) {
        console.log("Will upgrade PoolFactory");
      } else {
        const PoolFactoryContract = await ethers.getContractFactory("PoolFactory");
        const newPoolFactoryLogic = await upgrades.prepareUpgrade(poolFactoryProxy, PoolFactoryContract);
        console.log("New PoolFactory logic deployed to: ", newPoolFactoryLogic);

        await tryVerify(hre, newPoolFactoryLogic, "contracts/PoolFactory.sol:PoolFactory", []);

        const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [poolFactoryProxy, newPoolFactoryLogic]);
        await proposeTx(proxyAdminAddress, upgradeABI, "Upgrade Pool Factory", taskArgs.execute);
      }
    }
    if (taskArgs.assetHandler) {
      if (!taskArgs.execute) {
        console.log("Will upgrade AssetHandler");
      } else {
        let oldAssetHandler = contracts.AssetHandlerProxy;
        const AssetHandler = await ethers.getContractFactory("AssetHandler");
        const assetHandler = await upgrades.prepareUpgrade(oldAssetHandler, AssetHandler);
        console.log("assetHandler logic deployed to: ", assetHandler);

        await tryVerify(hre, assetHandler, "contracts/assets/AssetHandler.sol:AssetHandler", []);

        const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [oldAssetHandler, assetHandler]);
        await proposeTx(proxyAdminAddress, upgradeABI, "Upgrade Asset Handler", taskArgs.execute);
      }
    }
    if (taskArgs.poolLogic) {
      if (!taskArgs.execute) {
        console.log("Will upgrade PoolLogic");
      } else {
        let oldPooLogicProxy = contracts.PoolLogicProxy;
        const PoolLogic = await ethers.getContractFactory("PoolLogic");
        const poolLogic = await upgrades.prepareUpgrade(oldPooLogicProxy, PoolLogic);
        console.log("poolLogic deployed to: ", poolLogic);
        versions[newTag].contracts.PoolLogic = poolLogic;
        setLogic = true;

        await tryVerify(hre, poolLogic, "contracts/PoolLogic.sol:PoolLogic", []);
      }
    }
    if (taskArgs.poolManagerLogic) {
      if (!taskArgs.execute) {
        console.log("Will upgrade PoolManagerLogic");
      } else {
        let oldPooManagerLogicProxy = contracts.PoolManagerLogicProxy;
        const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        const poolManagerLogic = await upgrades.prepareUpgrade(oldPooManagerLogicProxy, PoolManagerLogic);
        console.log("poolManagerLogic deployed to: ", poolManagerLogic);
        versions[newTag].contracts.PoolManagerLogic = poolManagerLogic;
        setLogic = true;

        await tryVerify(hre, poolManagerLogic, "contracts/PoolManagerLogic.sol:PoolManagerLogic", []);
      }
    }
    if (setLogic) {
      const setLogicABI = PoolFactoryABI.encodeFunctionData("setLogic", [
        versions[newTag].contracts.PoolLogic,
        versions[newTag].contracts.PoolManagerLogic,
      ]);
      await proposeTx(
        contracts.PoolFactoryProxy,
        setLogicABI,
        "Set logic for poolLogic and poolManagerLogic",
        taskArgs.execute,
      );
    }

    if (taskArgs.poolPerformance) {
      if (contracts.PoolPerformanceProxy) {
        // Upgrade PoolPerformance
        if (!taskArgs.execute) {
          console.log("Will upgrade PoolPerformance");
        } else {
          let oldPoolPerformance = contracts.PoolPerformanceProxy;
          const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
          const poolPerformance = await upgrades.prepareUpgrade(oldPoolPerformance, PoolPerformance);
          console.log("poolPerformance deployed to: ", poolPerformance);

          await tryVerify(hre, poolPerformance, "contracts/PoolPerformance.sol:PoolPerformance", []);

          const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [oldPoolPerformance, poolPerformance]);
          await proposeTx(proxyAdminAddress, upgradeABI, "Upgrade Pool Performance", taskArgs.execute);

          versions[newTag].contracts.PoolPerformance = poolPerformance.address;
        }
      } else {
        if (!taskArgs.execute) {
          console.log("Will deploy PoolPerformance");
        } else {
          // Deploy PoolPerformance (is not yet deployed)
          const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
          const poolPerformanceProxy = await upgrades.deployProxy(PoolPerformance, []);
          await poolPerformanceProxy.deployed();
          console.log("poolPerformanceProxy deployed to:", poolPerformanceProxy.address);
          const poolPerformanceAddress = ethers.utils.hexValue(
            await provider.getStorageAt(poolPerformanceProxy.address, implementationStorage),
          );
          // const poolPerformanceAddress = await proxyAdmin.getProxyImplementation(poolPerformanceProxy.address);
          const poolPerformance = PoolPerformance.attach(poolPerformanceAddress);

          await poolPerformanceProxy.transferOwnership(protocolDao);

          await tryVerify(hre, poolPerformance.address, "contracts/PoolPerformance.sol:PoolPerformance", []);

          // Set PoolPerformance address in the Factory
          const setPoolPerformanceAddressABI = PoolFactoryABI.encodeFunctionData("setPoolPerformanceAddress", [
            poolPerformanceProxy.address,
          ]);
          await proposeTx(
            poolFactoryProxy,
            setPoolPerformanceAddressABI,
            `setPoolPerformanceAddress in Factory to ${poolPerformanceAddress}`,
            taskArgs.execute,
          );

          // Add to versions file
          versions[newTag].contracts.PoolPerformanceProxy = poolPerformanceProxy.address;
          versions[newTag].contracts.PoolPerformance = poolPerformanceAddress;
        }
      }
    }

    if (taskArgs.aaveLendingPoolAssetGuard) {
      if (!taskArgs.execute) {
        console.log("Will deploy AaveLendingPoolAssetGuard");
      } else {
        const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
        const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(aaveProtocolDataProvider);
        await aaveLendingPoolAssetGuard.deployed();
        console.log("AaveLendingPoolAssetGuard deployed at", aaveLendingPoolAssetGuard.address);
        versions[newTag].contracts.AaveLendingPoolAssetGuard = aaveLendingPoolAssetGuard.address;

        await tryVerify(
          hre,
          aaveLendingPoolAssetGuard.address,
          "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol:AaveLendingPoolAssetGuard",
          [aaveProtocolDataProvider],
        );

        const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
          3,
          aaveLendingPoolAssetGuard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setAssetGuardABI,
          "setAssetGuard for aaveLendingPoolAssetGuard",
          taskArgs.execute,
        );
        newAssetGuards.push({
          AssetType: 3,
          GuardName: "AaveLendingPoolAssetGuard",
          GuardAddress: aaveLendingPoolAssetGuard.address,
          Description: "Aave Lending Pool",
        });
      }
    }
    if (taskArgs.sushiLPAssetGuard) {
      if (!taskArgs.execute) {
        console.log("Will deploy SushiLPAssetGuard");
      } else {
        const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
        const sushiLPAssetGuard = await SushiLPAssetGuard.deploy(sushiMiniChefV2); // initialise with Sushi staking pool Id
        await sushiLPAssetGuard.deployed();
        console.log("SushiLPAssetGuard deployed at", sushiLPAssetGuard.address);
        versions[newTag].contracts.SushiLPAssetGuard = sushiLPAssetGuard.address;

        await tryVerify(
          hre,
          sushiLPAssetGuard.address,
          "contracts/guards/assetGuards/SushiLPAssetGuard.sol:SushiLPAssetGuard",
          [sushiMiniChefV2],
        );

        await sushiLPAssetGuard.transferOwnership(protocolDao);
        const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [2, sushiLPAssetGuard.address]);
        await proposeTx(
          contracts.Governance,
          setAssetGuardABI,
          "setAssetGuard for SushiLPAssetGuard",
          taskArgs.execute,
        );
        newAssetGuards.push({
          AssetType: 2,
          GuardName: "SushiLPAssetGuard",
          GuardAddress: sushiLPAssetGuard.address,
          Description: "Sushi LP tokens",
        });
      }
    }
    if (taskArgs.erc20Guard) {
      if (!taskArgs.execute) {
        console.log("Will deploy ERC20Guard");
      } else {
        const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
        const erc20Guard = await ERC20Guard.deploy();
        await erc20Guard.deployed();
        console.log("ERC20Guard deployed at", erc20Guard.address);
        versions[newTag].contracts.ERC20Guard = erc20Guard.address;

        await tryVerify(hre, erc20Guard.address, "contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard", []);

        const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [0, erc20Guard.address]);
        await proposeTx(contracts.Governance, setAssetGuardABI, "setAssetGuard for ERC20Guard", taskArgs.execute);
        newAssetGuards.push({
          AssetType: 0,
          GuardName: "ERC20Guard",
          GuardAddress: erc20Guard.address,
          Description: "ERC20 tokens",
        });
      }
    }
    if (taskArgs.lendingEnabledAssetGuard) {
      if (!taskArgs.execute) {
        console.log("Will deploy LendingEnabledAssetGuard");
      } else {
        const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
        const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
        await lendingEnabledAssetGuard.deployed();
        console.log("LendingEnabledAssetGuard deployed at", lendingEnabledAssetGuard.address);

        versions[newTag].contracts.LendingEnabledAssetGuard = lendingEnabledAssetGuard.address;

        await tryVerify(
          hre,
          lendingEnabledAssetGuard.address,
          "contracts/guards/assetGuards/LendingEnabledAssetGuard.sol:LendingEnabledAssetGuard",
          [],
        );

        const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [
          4,
          lendingEnabledAssetGuard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setAssetGuardABI,
          "setAssetGuard for LendingEnabledAssetGuard",
          taskArgs.execute,
        );
        newAssetGuards.push({
          AssetType: 4,
          GuardName: "LendingEnabledAssetGuard",
          GuardAddress: lendingEnabledAssetGuard.address,
          Description: "Lending Enabled Asset tokens",
        });
      }
    }
    if (taskArgs.uniswapV2RouterGuard) {
      if (!taskArgs.execute) {
        console.log("Will deploy UniswapV2RouterGuard");
      } else {
        const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
        const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(10, 100); // set slippage 10%
        await uniswapV2RouterGuard.deployed();
        console.log("UniswapV2RouterGuard deployed at", uniswapV2RouterGuard.address);
        versions[newTag].contracts.UniswapV2RouterGuard = uniswapV2RouterGuard.address;

        await tryVerify(
          hre,
          uniswapV2RouterGuard.address,
          "contracts/guards/UniswapV2RouterGuard.sol:UniswapV2RouterGuard",
          [10, 100],
        );

        await uniswapV2RouterGuard.transferOwnership(protocolDao);
        let setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          sushiswapV2Router,
          uniswapV2RouterGuard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setContractGuardABI,
          "setContractGuard for sushiswapV2Router",
          taskArgs.execute,
        );
        newContractGuards.push({
          ContractAddress: sushiswapV2Router,
          GuardName: "UniswapV2RouterGuard",
          GuardAddress: uniswapV2RouterGuard.address,
          Description: "Sushi V2 router",
        });

        setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          quickswapRouter,
          uniswapV2RouterGuard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setContractGuardABI,
          "setContractGuard for quickswapRouter",
          taskArgs.execute,
        );
        newContractGuards.push({
          ContractAddress: quickswapRouter,
          GuardName: "UniswapV2RouterGuard",
          GuardAddress: uniswapV2RouterGuard.address,
          Description: "Quickswap V2 router",
        });
      }
    }
    if (taskArgs.balancerv2guard) {
      if (!taskArgs.execute) {
        console.log("Will deploy BalancerV2Guard");
      } else {
        const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
        const balancerV2Guard = await BalancerV2Guard.deploy(10, 100); // set slippage 10%
        await balancerV2Guard.deployed();
        console.log("BalancerV2Guard deployed at", balancerV2Guard.address);
        versions[newTag].contracts.UniswapV2RouterGuard = balancerV2Guard.address;

        await tryVerify(
          hre,
          balancerV2Guard.address,
          "contracts/guards/BalancerV2Guard.sol:BalancerV2Guard",
          [10, 100],
        );

        await balancerV2Guard.transferOwnership(protocolDao);
        let setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          balancerV2Vault,
          balancerV2Guard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setContractGuardABI,
          "setContractGuard for balancerV2Vault",
          taskArgs.execute,
        );
        newContractGuards.push({
          ContractAddress: balancerV2Vault,
          GuardName: "BalancerV2Guard",
          GuardAddress: balancerV2Guard.address,
          Description: "Balancer V2 Guard",
        });
      }
    }
    if (taskArgs.openAssetGuard) {
      if (!taskArgs.execute) {
        console.log("Will deploy OpenAssetGuard");
      } else {
        const fileName = taskArgs.production ? prodExternalAssetFileName : stagingExternalAssetFileName;
        const csvAssets = await csv().fromFile(fileName);
        let addresses = csvAssets.map((asset) => asset.Address);
        const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
        const openAssetGuard = await OpenAssetGuard.deploy(addresses);
        await openAssetGuard.deployed();
        console.log("OpenAssetGuard deployed at", openAssetGuard.address);
        versions[newTag].contracts.OpenAssetGuard = openAssetGuard.address;

        await tryVerify(hre, openAssetGuard.address, "contracts/guards/assetGuards/OpenAssetGuard.sol:OpenAssetGuard", [
          addresses,
        ]);

        await openAssetGuard.transferOwnership(protocolDao);
        const setAddressesABI = governanceABI.encodeFunctionData("setAddresses", [
          [[ethers.utils.formatBytes32String("openAssetGuard"), openAssetGuard.address]],
        ]);
        await proposeTx(contracts.Governance, setAddressesABI, "setAddresses for openAssetGuard", taskArgs.execute);
        newGovernanceNames.push({
          Name: "openAssetGuard",
          Destination: openAssetGuard.address,
        });
      }
    }
    if (taskArgs.quickLPAssetGuard) {
      if (!taskArgs.execute) {
        console.log("Will deploy QuickLpAssetGuard");
      } else {
        const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
        const quickLPAssetGuard = await QuickLPAssetGuard.deploy(quickStakingRewardsFactory);
        await quickLPAssetGuard.deployed();
        console.log("quickLPAssetGuard deployed at", quickLPAssetGuard.address);
        versions[newTag].contracts.QuickLPAssetGuard = quickLPAssetGuard.address;

        await tryVerify(
          hre,
          quickLPAssetGuard.address,
          "contracts/guards/assetGuards/QuickLPAssetGuard.sol:QuickLPAssetGuard",
          [quickStakingRewardsFactory],
        );

        await quickLPAssetGuard.transferOwnership(protocolDao);
        const setAssetGuardABI = governanceABI.encodeFunctionData("setAssetGuard", [5, quickLPAssetGuard.address]);
        await proposeTx(
          contracts.Governance,
          setAssetGuardABI,
          "setAssetGuard for quickLPAssetGuard",
          taskArgs.execute,
        );
        newAssetGuards.push({
          AssetType: 5,
          GuardName: "QuickLPAssetGuard",
          GuardAddress: quickLPAssetGuard.address,
          Description: "Quick LP tokens",
        });
      }
    }
    if (taskArgs.quickStakingRewardsGuard) {
      if (!taskArgs.execute) {
        console.log("Will deploy QuickStakingRewardsGuard");
      } else {
        const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
        const quickStakingRewardsGuard = await QuickStakingRewardsGuard.deploy();
        await quickStakingRewardsGuard.deployed();
        console.log("quickStakingRewardsGuard deployed at", quickStakingRewardsGuard.address);
        versions[newTag].contracts.QuickStakingRewardsGuard = quickStakingRewardsGuard.address;

        await tryVerify(
          hre,
          quickStakingRewardsGuard.address,
          "contracts/guards/QuickStakingRewardsGuard.sol:QuickStakingRewardsGuard",
          [],
        );

        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          quickLpUsdcWethStakingRewards,
          quickStakingRewardsGuard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setContractGuardABI,
          "setContractGuard for QuickStakingRewardsGuard",
          taskArgs.execute,
        );
        newContractGuards.push({
          ContractAddress: quickLpUsdcWethStakingRewards,
          GuardName: "QuickStakingRewardsGuard",
          GuardAddress: quickStakingRewardsGuard.address,
          Description: "Quick Staking Reward",
        });
      }
    }
    if (taskArgs.sushiMiniChefV2Guard) {
      if (!taskArgs.execute) {
        console.log("Will deploy SushiMiniChefV2Guard");
      } else {
        const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
        const sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy(sushiToken, wmatic);
        await sushiMiniChefV2Guard.deployed();
        console.log("SushiMiniChefV2Guard deployed at", sushiMiniChefV2Guard.address);
        versions[newTag].contracts.SushiMiniChefV2Guard = sushiMiniChefV2Guard.address;

        await tryVerify(
          hre,
          sushiMiniChefV2Guard.address,
          "contracts/guards/SushiMiniChefV2Guard.sol:SushiMiniChefV2Guard",
          [sushiToken, wmatic],
        );

        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          sushiMiniChefV2,
          sushiMiniChefV2Guard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setContractGuardABI,
          "setContractGuard for sushiMiniChefV2Guard",
          taskArgs.execute,
        );
        newContractGuards.push({
          ContractAddress: sushiMiniChefV2,
          GuardName: "SushiMiniChefV2Guard",
          GuardAddress: sushiMiniChefV2Guard.address,
          Description: "Sushi rewards contract",
        });
      }
    }
    if (taskArgs.aaveIncentivesControllerGuard) {
      if (!taskArgs.execute) {
        console.log("Will deploy AaveIncentivesControllerGuard");
      } else {
        const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
        console.log("wmatic: ", wmatic);
        const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy(wmatic);
        await aaveIncentivesControllerGuard.deployed();
        console.log("AaveIncentivesControllerGuard deployed at", aaveIncentivesControllerGuard.address);
        versions[newTag].contracts.AaveIncentivesControllerGuard = aaveIncentivesControllerGuard.address;

        await tryVerify(
          hre,
          aaveIncentivesControllerGuard.address,
          "contracts/guards/AaveIncentivesControllerGuard.sol:AaveIncentivesControllerGuard",
          [wmatic],
        );

        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          aaveIncentivesController,
          aaveIncentivesControllerGuard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setContractGuardABI,
          "setContractGuard for AaveIncentivesControllerGuard",
          taskArgs.execute,
        );
        newContractGuards.push({
          ContractAddress: aaveIncentivesController,
          GuardName: "AaveIncentivesControllerGuard",
          GuardAddress: aaveIncentivesControllerGuard.address,
          Description: "Aave Incentives Controller contract",
        });
      }
    }
    if (taskArgs.aaveLendingPoolGuard) {
      if (!taskArgs.execute) {
        console.log("Will deploy AaveLendingPoolGuard");
      } else {
        const AaveLendingPoolGuard = await ethers.getContractFactory("AaveLendingPoolGuard");
        const aaveLendingPoolGuard = await AaveLendingPoolGuard.deploy();
        await aaveLendingPoolGuard.deployed();
        console.log("AaveLendingPoolGuard deployed at", aaveLendingPoolGuard.address);
        versions[newTag].contracts.AaveLendingPoolGuard = aaveLendingPoolGuard.address;

        await tryVerify(
          hre,
          aaveLendingPoolGuard.address,
          "contracts/guards/AaveLendingPoolGuard.sol:AaveLendingPoolGuard",
          [],
        );

        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          aaveLendingPool,
          aaveLendingPoolGuard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setContractGuardABI,
          "setContractGuard for aaveLendingPoolGuard",
          taskArgs.execute,
        );
        newContractGuards.push({
          ContractAddress: aaveLendingPool,
          GuardName: "AaveLendingPoolGuard",
          GuardAddress: aaveLendingPoolGuard.address,
          Description: "Aave Lending Pool contract",
        });
      }
    }
    if (taskArgs.oneInchV3Guard) {
      if (!taskArgs.execute) {
        console.log("Will deploy OneInchV2Guard");
      } else {
        const OneInchV3Guard = await ethers.getContractFactory("OneInchV3Guard");
        oneInchV3Guard = await OneInchV3Guard.deploy(10, 100); // set slippage 10%
        await oneInchV3Guard.deployed();
        console.log("oneInchV3Guard deployed at", oneInchV3Guard.address);
        versions[newTag].contracts.OneInchV3Guard = oneInchV3Guard.address;

        await tryVerify(hre, oneInchV3Guard.address, "contracts/guards/OneInchV3Guard.sol:OneInchV3Guard", [10, 100]);

        const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
          oneInchV3Router,
          oneInchV3Guard.address,
        ]);
        await proposeTx(
          contracts.Governance,
          setContractGuardABI,
          "setContractGuard for oneInchV3Guard",
          taskArgs.execute,
        );
        newContractGuards.push({
          ContractAddress: oneInchV3Router,
          GuardName: "OneInchV3Guard",
          GuardAddress: oneInchV3Guard.address,
          Description: "OneInch V3 Router",
        });
      }
    }

    if (taskArgs.governanceNames) {
      for (const csvGovernanceName of csvGovernanceNames) {
        const name = csvGovernanceName.Name;
        const destination = csvGovernanceName.Destination;
        const nameBytes = ethers.utils.formatBytes32String(name);
        const configuredDestination = await governance.nameToDestination(nameBytes);

        if (configuredDestination === "0x0000000000000000000000000000000000000000") {
          const setAddressesABI = governanceABI.encodeFunctionData("setAddresses", [[[nameBytes, destination]]]);
          await proposeTx(
            contracts.Governance,
            setAddressesABI,
            `setAddresses for ${name} to ${destination}`,
            taskArgs.execute,
          );
        }
      }
    }

    if (taskArgs.unpause) {
      if (!taskArgs.execute) {
        console.log("Will unpause");
      } else {
        // Unpause Pool Factory
        const unpauseABI = PoolFactoryABI.encodeFunctionData("unpause", []);
        await proposeTx(poolFactoryProxy, unpauseABI, "Unpause pool Factory", taskArgs.execute);
      }
    }

    // convert JSON object to string
    const data = JSON.stringify(versions, null, 2);

    // write to version file
    if (taskArgs.execute && !taskArgs.unpause) {
      // skip version file update if just unpausing
      fs.writeFileSync(`./publish/${network.name}/${versionFile}.json`, data);
    }

    versions[newTag].contracts = { ...contracts };
    for (const newAssetGuard of newAssetGuards) {
      let replaced = false;
      for (const csvAssetGuard of csvAssetGuards) {
        if (newAssetGuard.GuardName == csvAssetGuard.GuardName) {
          csvAssetGuard.AssetType = newAssetGuard.AssetType;
          csvAssetGuard.GuardAddress = newAssetGuard.GuardAddress;
          csvAssetGuard.Description = newAssetGuard.Description;
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        csvAssetGuards.push(newAssetGuard);
      }
    }
    for (const newContractGuard of newContractGuards) {
      let replaced = false;
      for (const csvContractGuard of csvContractGuards) {
        if (newContractGuard.GuardName == csvContractGuard.GuardName) {
          csvContractGuard.ContractAddress = newContractGuard.ContractAddress;
          csvContractGuard.GuardAddress = newContractGuard.GuardAddress;
          csvContractGuard.Description = newContractGuard.Description;
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        csvContractGuards.push(newContractGuard);
      }
    }
    for (const newGovernanceName of newGovernanceNames) {
      let replaced = false;
      for (const csvGovernanceName of csvGovernanceNames) {
        if (newGovernanceName.Name == csvGovernanceName.Name) {
          csvGovernanceName.Destination = newGovernanceName.Destination;
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        csvGovernanceNames.push(newGovernanceName);
      }
    }
    if (csvAssetGuards.length > 0) writeCsv(csvAssetGuards, assetGuardfileName);
    if (csvContractGuards.length > 0) writeCsv(csvContractGuards, contractGuardfileName);
    if (csvGovernanceNames.length > 0) writeCsv(csvGovernanceNames, governanceNamesfileName);

    if (taskArgs.execute) console.log(nonceLog);
  });

module.exports = {};
