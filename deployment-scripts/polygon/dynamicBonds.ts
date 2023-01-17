import axios from "axios";
import { BigNumber, Contract, utils } from "ethers";
import fs from "fs";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { polygonChainData } from "../../config/chainData/polygon-data";
import { DynamicBonds } from "../../types"; // Unit test fails on Github Actions
import { proposeTx, tryVerify } from "../Helpers";
import { IUpgradeConfigProposeTx, IVersion, IVersions } from "../types";
import { getDeploymentData, IDeploymentData } from "../upgrade/getDeploymentData";

const coingeckoNetwork = "polygon-pos";

const { protocolDao } = polygonChainData;

// Addresses
const depositToken = "0x2791bca1f2de4661ed88a30c99a7a9449aa84174"; // USDC
const payoutToken = "0x8c92e38eca8210f4fcbf17f0951b198dd7668292"; // DHT
const treasury = "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3"; // Polygon Protocol Treasury

// Bond terms
const minBondPrice = utils.parseUnits("0.1", 6); // $0.10 USDC
const maxPayoutAvailable = utils.parseUnits("50000"); // 50k DHT/week
const salePayoutAvailable = utils.parseUnits("25000"); // 25k DHT
const saleDuration = 60 * 60 * 24 * 5; // 5 days

// Bond option lock durations
const bondLockDurations = [7, 30, 182, 365]; // in days
// const bondLockDurations = [1 / (24 * 60), 1 / 24, 1, 7]; // Short durations that can be used for testing

// Bond option discount percentages
const discountOneWeek = 0.03;
const discountOneMonth = 0.07;
const discountSixMonths = 0.12;
const discountOneYear = 0.22;

const deployDynamicBonds = async (hre: HardhatRuntimeEnvironment, deploymentData: IDeploymentData) => {
  const ethers = hre.ethers;
  const upgrades = hre.upgrades;
  const provider = ethers.provider;

  // Deploy
  await hre.run("compile:one", { contractName: "DynamicBonds" });
  const DynamicBonds = await ethers.getContractFactory("DynamicBonds");
  const dynamicBondsInitParams = [depositToken, payoutToken, treasury, minBondPrice, maxPayoutAvailable];
  const dynamicBonds = await upgrades.deployProxy(DynamicBonds, dynamicBondsInitParams);
  await dynamicBonds.deployed();

  const dynamicBondsProxy = DynamicBonds.attach(dynamicBonds.address);

  const dynamicBondsImplementationAddress = ethers.utils.hexValue(
    await provider.getStorageAt(dynamicBondsProxy.address, deploymentData.addresses.implementationStorageAddress),
  );

  const dynamicBondsImplementation = DynamicBonds.attach(dynamicBondsImplementationAddress);

  await tryVerify(hre, dynamicBondsImplementation.address, "contracts/DynamicBonds.sol:DynamicBonds", []);

  console.log("dynamicBondsProxy deployed to:", dynamicBondsProxy.address);
  console.log("dynamicBonds implementation:", dynamicBondsImplementation.address);

  return { dynamicBondsProxy, dynamicBondsImplementation };
};

const setBondTerms = async (
  dynamicBonds: Contract,
  upgradeConfig: IUpgradeConfigProposeTx,
  deploymentData: IDeploymentData,
) => {
  const timeNow = Math.round(Date.now() / 1000);
  const timeAtSaleEnd = timeNow + saleDuration;
  console.log("-- Set bond terms --");
  console.log("Available payout:", utils.formatEther(salePayoutAvailable), "DHT");
  console.log("Terms expiry:", new Date(timeAtSaleEnd * 1000));
  // await dynamicBonds.setBondTerms(salePayoutAvailable, timeAtSaleEnd);
  const setBondTermsData = dynamicBonds.interface.encodeFunctionData("setBondTerms", [
    salePayoutAvailable,
    timeAtSaleEnd,
  ]);
  await proposeTx(
    dynamicBonds.address,
    setBondTermsData,
    `setBondTerms in DynamicBonds to:  Available DHT payout: ${utils.formatEther(
      salePayoutAvailable,
    )}, Expiry: ${new Date(timeAtSaleEnd * 1000)} `,
    upgradeConfig,
    deploymentData.addresses,
  );
  console.log("Bond terms proposed!");
};

const addBondOptions = async (hre: HardhatRuntimeEnvironment, dynamicBonds: Contract) => {
  const bondOptionsBefore = await dynamicBonds.bondOptions();
  if (bondOptionsBefore.length > 0) throw "Bonds already added";

  const { depositTokenDecimals } = await getTokenDecimals(hre);
  const bondOptionsNew = await getBondPrices(depositTokenDecimals);

  console.log("-- Add bond options --");
  let i = 0;
  for (const bondOption of bondOptionsNew) {
    console.log(
      `Option ${i}`,
      "Price:",
      bondOption.price.toString(),
      "Days:",
      bondOption.lockPeriod.toNumber() / 86400,
    );
    i++;
  }

  await dynamicBonds.addBondOptions(bondOptionsNew);
  console.log("Bond options added!");
};

const updateBondOptions = async (
  hre: HardhatRuntimeEnvironment,
  dynamicBonds: Contract,
  upgradeConfig: IUpgradeConfigProposeTx,
  deploymentData: IDeploymentData,
) => {
  const bondOptionsBefore = await dynamicBonds.bondOptions();
  const bondOptionLength = bondOptionsBefore.length;
  if (bondOptionLength == 0) throw "No bond options added yet";

  const { depositTokenDecimals } = await getTokenDecimals(hre);
  const bondOptionsNew = await getBondPrices(depositTokenDecimals);

  if (bondOptionLength !== bondOptionsNew.length)
    throw `New bond options amount doesn't match old. Old: ${bondOptionLength}, New: ${bondOptionsNew.length}`;

  console.log("-- Modify bond options --");
  let i = 0;
  for (const bondOption of bondOptionsNew) {
    console.log(
      `Option ${i}`,
      "Price:",
      bondOption.price.toString(),
      "Days:",
      bondOption.lockPeriod.toNumber() / 86400,
    );
    i++;
  }

  // await dynamicBonds.updateBondOptions([0, 1, 2, 3], bondOptionsNew);
  const updateBondOptionsData = dynamicBonds.interface.encodeFunctionData("updateBondOptions", [
    [0, 1, 2, 3],
    bondOptionsNew,
  ]);
  await proposeTx(
    dynamicBonds.address,
    updateBondOptionsData,
    `updateBondOptions in DynamicBonds 0: Price: ${bondOptionsNew[0].price.toString()} Days locked: ${
      bondOptionsNew[0].lockPeriod.toNumber() / 86400
    }, 1: Price: ${bondOptionsNew[1].price.toString()} Days locked: ${
      bondOptionsNew[1].lockPeriod.toNumber() / 86400
    }, 2: Price: ${bondOptionsNew[2].price.toString()} Days locked: ${
      bondOptionsNew[2].lockPeriod.toNumber() / 86400
    }, 3: Price: ${bondOptionsNew[3].price.toString()} Days locked: ${bondOptionsNew[3].lockPeriod.toNumber() / 86400}`,
    upgradeConfig,
    deploymentData.addresses,
  );
  console.log("Bond options proposed!");
};

const getTokenPrice = async (coingeckoNetwork: string, assetAddress: string) => {
  const url = `https://api.coingecko.com/api/v3/simple/token_price/${coingeckoNetwork}?contract_addresses=${assetAddress}&vs_currencies=usd&include_market_cap=false&include_24hr_vol=false&include_24hr_change=false&include_last_updated_at=true`;
  try {
    const { data } = await axios.get(url);
    const coingeckoAssetPriceUsd: number = parseFloat(data[assetAddress.toLowerCase()].usd);

    return coingeckoAssetPriceUsd;
  } catch (err) {
    console.error(`Error getting Coingecko feed for asset`);
    throw err;
  }
};

const printConfig = async (dynamicBonds: Contract, depositTokenDecimals: number) => {
  const owner = await dynamicBonds.owner();
  console.log("Bond contract owner:", owner);
  const bondTerms = await dynamicBonds.bondTerms();
  const bondOptions = await dynamicBonds.bondOptions();
  console.log("-- Bond Terms --");
  console.log("Available payout:", utils.formatEther(bondTerms.payoutAvailable), "DHT");
  console.log("Terms Expiry:", new Date(bondTerms.expiryTimestamp.toNumber() * 1000));
  console.log("------------------------");
  console.log("-- Bond Options --");
  console.log("Number of options:", bondOptions.length);
  for (let i = 0; i < bondOptions.length; i++) {
    console.log(
      `Option ${i}: Price: $${utils.formatUnits(
        bondOptions[i][0],
        depositTokenDecimals,
      )} (${depositTokenDecimals} decimals), Days: ${bondOptions[i][1].toNumber() / 86400}`,
    );
  }
  console.log("------------------------");
  console.log("-- Totals --");
  const depositTotal = await dynamicBonds.depositTotal();
  console.log("Deposit Total:", utils.formatUnits(depositTotal, 6), "USDC");
  const debtTotal = await dynamicBonds.debtTotal();
  console.log("Debt Total:", utils.formatEther(debtTotal), "DHT");
  console.log("------------------------");
  console.log("-- Addresses --");
  const depositTokenSetting = await dynamicBonds.depositToken();
  console.log("Deposit token (USDC):", depositTokenSetting);
  const payoutTokenSetting = await dynamicBonds.payoutToken();
  console.log("Payout token (DHT):", payoutTokenSetting);
  const treasurySetting = await dynamicBonds.treasury();
  console.log("Treasury address:", treasurySetting);
  console.log("------------------------");
};

const checkPayoutBalance = async (hre: HardhatRuntimeEnvironment, dynamicBonds: Contract) => {
  const IERC20 = await hre.artifacts.readArtifact("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");
  const payoutTokenSetting = await dynamicBonds.payoutToken();
  const payoutTokenERC20 = await hre.ethers.getContractAt(IERC20.abi, payoutTokenSetting);
  const payoutBalance = await payoutTokenERC20.balanceOf(dynamicBonds.address);
  const debtTotal = await dynamicBonds.debtTotal();
  console.log("-- DHT balance and debt --");
  if (debtTotal.gt(payoutBalance)) {
    console.log("!! Not enough DHT in the contract to cover debt !!");
    const netDebt = debtTotal.sub(payoutBalance);
    console.log(`!! Transfer ${utils.formatEther(netDebt)} more DHT to the contract !!`);
  }
  console.log("DHT debt:", utils.formatEther(debtTotal));
  console.log("DHT balance:", utils.formatEther(payoutBalance));
};

const getDynamicBondsContract = async (hre: HardhatRuntimeEnvironment, version: IVersion): Promise<DynamicBonds> => {
  const ethers = hre.ethers;
  const contractName = "DynamicBonds";
  const dynamicBondsProxyAddress = version.contracts["DynamicBondsProxy"];
  if (!dynamicBondsProxyAddress) throw `${contractName} contract not deployed`;

  await hre.run("compile:one", { contractName });
  const DynamicBonds = await ethers.getContractFactory(contractName);
  const dynamicBonds = DynamicBonds.attach(dynamicBondsProxyAddress);

  return dynamicBonds;
};

const getBondPrices = async (depositTokenDecimals: number) => {
  const dhtPrice = await getTokenPrice(coingeckoNetwork, payoutToken);
  console.log(`DHT price: $${dhtPrice}`);

  const bondOptionOneWeek = {
    price: utils.parseUnits(
      (dhtPrice * (1 - discountOneWeek)).toFixed(depositTokenDecimals).toString(),
      depositTokenDecimals,
    ),
    lockPeriod: BigNumber.from(60 * 60 * 24 * bondLockDurations[0]),
    // lockPeriod: BigNumber.from(60 * 1), // Test: 1 minute
  };
  const bondOptionOneMonth = {
    price: utils.parseUnits(
      (dhtPrice * (1 - discountOneMonth)).toFixed(depositTokenDecimals).toString(),
      depositTokenDecimals,
    ),
    lockPeriod: BigNumber.from(60 * 60 * 24 * bondLockDurations[1]),
    // lockPeriod: BigNumber.from(60 * 10), // Test: 10 minutes
  };
  const bondOptionSixMonths = {
    price: utils.parseUnits(
      (dhtPrice * (1 - discountSixMonths)).toFixed(depositTokenDecimals).toString(),
      depositTokenDecimals,
    ),
    lockPeriod: BigNumber.from(60 * 60 * 24 * bondLockDurations[2]),
    // lockPeriod: BigNumber.from(60 * 60 * 1), // Test: 1 hour
  };
  const bondOptionOneYear = {
    price: utils.parseUnits(
      (dhtPrice * (1 - discountOneYear)).toFixed(depositTokenDecimals).toString(),
      depositTokenDecimals,
    ),
    lockPeriod: BigNumber.from(60 * 60 * 24 * bondLockDurations[3]),
    // lockPeriod: BigNumber.from(60 * 60 * 24 * 1), // Test: 1 day
  };

  const bondOptionsNew = [bondOptionOneWeek, bondOptionOneMonth, bondOptionSixMonths, bondOptionOneYear];

  return bondOptionsNew;
};

const getTokenDecimals = async (hre: HardhatRuntimeEnvironment) => {
  const IERC20 = await hre.artifacts.readArtifact("IERC20Extended");

  const depositTokenSetting = depositToken;
  const depositTokenERC20 = await hre.ethers.getContractAt(IERC20.abi, depositTokenSetting);
  const depositTokenDecimals: number = await depositTokenERC20.decimals();

  const payoutTokenSetting = payoutToken;
  const payoutTokenERC20 = await hre.ethers.getContractAt(IERC20.abi, payoutTokenSetting);
  const payoutTokenDecimals: number = await payoutTokenERC20.decimals();

  return { depositTokenDecimals, payoutTokenDecimals };
};

task("dynamicBonds", "Deploy Dynamic Bonds contract")
  .addOptionalParam("restartnonce", "propose transactions", false, types.boolean)
  .addOptionalParam("execute", "propose transactions", false, types.boolean)
  .addOptionalParam("production", "run in production environment", false, types.boolean)
  .addOptionalParam("deploy", "deploy Dynamic Bonds", false, types.boolean)
  .addOptionalParam("upgrade", "upgrade Dynamic Bonds", false, types.boolean)
  .addOptionalParam("updateTerms", "update bond terms", false, types.boolean)
  .addOptionalParam("updateTreasury", "change the treasury address", false, types.boolean)
  .addOptionalParam("getConfig", "get live contract configuration", false, types.boolean)
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;
    const upgrades = hre.upgrades;
    const network = await ethers.provider.getNetwork();
    console.log("Network:", network.name);
    await hre.run("compile");

    const upgradeConfig: IUpgradeConfigProposeTx = { execute: taskArgs.execute, restartnonce: taskArgs.restartnonce };

    const deploymentData = getDeploymentData(network.chainId, taskArgs.production ? "production" : "staging");
    // Init contracts
    const ProxyAdmin = await hre.artifacts.readArtifact("ProxyAdmin");
    const proxyAdmin = new ethers.utils.Interface(ProxyAdmin.abi);

    // Init version
    const versions: IVersions = JSON.parse(fs.readFileSync(deploymentData.filenames.versionsFileName, "utf-8"));
    const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];
    const version = versions[latestVersion];
    let versionUpdate = false;

    if (taskArgs.getConfig) {
      const dynamicBondsProxy = await getDynamicBondsContract(hre, version);
      const { depositTokenDecimals } = await getTokenDecimals(hre);
      await printConfig(dynamicBondsProxy, depositTokenDecimals);
      await checkPayoutBalance(hre, dynamicBondsProxy);
    }

    if (taskArgs.updateTerms) {
      const dynamicBondsProxy = await getDynamicBondsContract(hre, version);
      await updateBondOptions(hre, dynamicBondsProxy, upgradeConfig, deploymentData); // set bond prices first
      await setBondTerms(dynamicBondsProxy, upgradeConfig, deploymentData); // then open for trading with future expiry date
    }

    if (taskArgs.updateTreasury) {
      const dynamicBondsProxy = await getDynamicBondsContract(hre, version);
      await dynamicBondsProxy.setTreasury(treasury);
      console.log("Treasury set to:", treasury);
    }

    if (taskArgs.upgrade) {
      const dynamicBondsProxy = await getDynamicBondsContract(hre, version);
      const DynamicBonds = await ethers.getContractFactory("DynamicBonds");

      const newDynamicBondsImplementation = await upgrades.prepareUpgrade(dynamicBondsProxy, DynamicBonds);
      console.log("New DynamicBonds logic deployed to: ", newDynamicBondsImplementation);

      await tryVerify(hre, newDynamicBondsImplementation, "contracts/DynamicBonds.sol:DynamicBonds", []);

      const upgradeABI = proxyAdmin.encodeFunctionData("upgrade", [
        dynamicBondsProxy.address,
        newDynamicBondsImplementation,
      ]);
      await proposeTx(
        deploymentData.addresses.proxyAdminAddress,
        upgradeABI,
        "Upgrade Dynamic Bonds",
        taskArgs,
        deploymentData.addresses,
      );

      versions[latestVersion].contracts.DynamicBonds = newDynamicBondsImplementation;
      versionUpdate = true;
    }

    if (taskArgs.deploy) {
      if (versions[latestVersion].contracts.DynamicBondsProxy) throw "Dynamic Bonds contract already deployed";

      const { dynamicBondsProxy, dynamicBondsImplementation } = await deployDynamicBonds(hre, deploymentData);
      console.log("Dynamic Bonds proxy deployed to", dynamicBondsProxy.address);
      const transferOwnershipTx = await dynamicBondsProxy.transferOwnership(protocolDao);
      await transferOwnershipTx.wait(5);
      console.log("Ownership transferred to", protocolDao);
      await setBondTerms(dynamicBondsProxy, taskArgs, deploymentData);
      await addBondOptions(hre, dynamicBondsProxy);

      versions[latestVersion].contracts.DynamicBondsProxy = dynamicBondsProxy.address;
      versions[latestVersion].contracts.DynamicBonds = dynamicBondsImplementation.address;
      versionUpdate = true;
    }

    if (versionUpdate) {
      versions[latestVersion].lastUpdated = new Date().toUTCString();
      // convert JSON object to string
      const data = JSON.stringify(versions, null, 2);
      // write to version file
      fs.writeFileSync(deploymentData.filenames.versionsFileName, data);
    }
  });
