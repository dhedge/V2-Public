import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, proposeTransactions } from "../../../helpers/safe";
import { tryVerify } from "../../../helpers/verify";
import type { MetaTransactionData } from "../../../helpers/safe";

import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";
import { addOrReplaceGuardInFile } from "../../../helpers/csv";
import { closedContractGuardJob } from "./closedContractGuardJob";

// dHEDGE asset type registered for the Gmx Perps Market asset guard.
const GMX_MARKET_ASSET_TYPE = 105;

// Propose assets at an earlier Safe nonce; the registry is updated only when that proposal executes.
// PoolManagerLogic.changeAssets validates asset registration when this batch executes.
// Remove entries after their guard activation batch executes.
const MARKET_ACTIVATIONS: { market: string; vaults: string[] }[] = [
  {
    market: "0x63Dc80EE90F26363B3FCD609007CC9e14c8991BE", // NEAR
    vaults: [
      "0x75d1c951e5BCE4CcA5091901A7e7F2a697d99e5E", // NEAR1X
      "0xF1078306A52Aa9370e846f93ff3dD6591d028051", // NEARBULL2X
      "0xb6bd70E974A77E9440ABa6E44865c7bCfA585954", // NEARBULL3X
    ],
  },
];

export const gmxExchangeRouterContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.gmx) {
    return console.warn("No config for GmxExchangeRouterContractGuard: skipping.");
  }

  const {
    approvalRouter,
    dHedgeVaultsWhitelist,
    dataStore,
    exchangeRouter,
    feeReceiver,
    reader,
    virtualTokenResolver,
    referralStorage,
  } = addresses.gmx;

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);
  const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;
  const nftTrackerStorage = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;
  if (!slippageAccumulatorAddress) {
    return console.warn("SlippageAccumulator could not be found: skipping.");
  }

  if (!nftTrackerStorage) {
    return console.warn("DhedgeNftTrackerStorage could not be found: skipping.");
  }

  console.log("Will deploy GmxExchangeRouterContractGuard");
  for (const activation of MARKET_ACTIVATIONS) {
    console.log(
      `Will enable GMX market ${activation.market} and register callbacks in ${activation.vaults.length} vault(s)`,
    );
  }

  if (config.execute) {
    console.log("Deploying GMX libraries...");

    const GmxHelperLib = await ethers.getContractFactory("GmxHelperLib");
    const gmxHelperLib = await GmxHelperLib.deploy();
    await gmxHelperLib.deployed();
    console.log("GmxHelperLib deployed at:", gmxHelperLib.address);
    versions[config.newTag].contracts.GmxHelperLib = gmxHelperLib.address;

    await tryVerify(hre, gmxHelperLib.address, "contracts/utils/gmx/GmxHelperLib.sol:GmxHelperLib", []);

    const GmxClaimableCollateralTrackerLib = await ethers.getContractFactory("GmxClaimableCollateralTrackerLib", {
      libraries: {
        GmxHelperLib: gmxHelperLib.address,
      },
    });
    const gmxClaimableCollateralTrackerLib = await GmxClaimableCollateralTrackerLib.deploy();
    await gmxClaimableCollateralTrackerLib.deployed();
    console.log("GmxClaimableCollateralTrackerLib deployed at:", gmxClaimableCollateralTrackerLib.address);
    versions[config.newTag].contracts.GmxClaimableCollateralTrackerLib = gmxClaimableCollateralTrackerLib.address;

    await tryVerify(
      hre,
      gmxClaimableCollateralTrackerLib.address,
      "contracts/utils/gmx/GmxClaimableCollateralTrackerLib.sol:GmxClaimableCollateralTrackerLib",
      [],
    );

    const GmxAfterTxValidatorLib = await ethers.getContractFactory("GmxAfterTxValidatorLib", {
      libraries: {
        GmxHelperLib: gmxHelperLib.address,
      },
    });
    const gmxAfterTxValidatorLib = await GmxAfterTxValidatorLib.deploy();
    await gmxAfterTxValidatorLib.deployed();
    console.log("GmxAfterTxValidatorLib deployed at:", gmxAfterTxValidatorLib.address);
    versions[config.newTag].contracts.GmxAfterTxValidatorLib = gmxAfterTxValidatorLib.address;

    await tryVerify(
      hre,
      gmxAfterTxValidatorLib.address,
      "contracts/utils/gmx/GmxAfterTxValidatorLib.sol:GmxAfterTxValidatorLib",
      [],
    );

    const GmxEventUtils = await ethers.getContractFactory("GmxEventUtils");
    const gmxEventUtils = await GmxEventUtils.deploy();
    await gmxEventUtils.deployed();
    console.log("GmxEventUtils deployed at:", gmxEventUtils.address);
    versions[config.newTag].contracts.GmxEventUtils = gmxEventUtils.address;

    await tryVerify(hre, gmxEventUtils.address, "contracts/utils/gmx/GmxEventUtils.sol:GmxEventUtils", []);

    const GmxAfterExecutionLib = await ethers.getContractFactory("GmxAfterExecutionLib", {
      libraries: {
        GmxAfterTxValidatorLib: gmxAfterTxValidatorLib.address,
        GmxClaimableCollateralTrackerLib: gmxClaimableCollateralTrackerLib.address,
        GmxEventUtils: gmxEventUtils.address,
        GmxHelperLib: gmxHelperLib.address,
      },
    });
    const gmxAfterExecutionLib = await GmxAfterExecutionLib.deploy();
    await gmxAfterExecutionLib.deployed();
    console.log("GmxAfterExecutionLib deployed at:", gmxAfterExecutionLib.address);
    versions[config.newTag].contracts.GmxAfterExecutionLib = gmxAfterExecutionLib.address;

    await tryVerify(
      hre,
      gmxAfterExecutionLib.address,
      "contracts/utils/gmx/GmxAfterExecutionLib.sol:GmxAfterExecutionLib",
      [],
    );

    const GmxExchangeRouterContractGuard = await ethers.getContractFactory("GmxExchangeRouterContractGuard", {
      libraries: {
        GmxHelperLib: gmxHelperLib.address,
        GmxAfterTxValidatorLib: gmxAfterTxValidatorLib.address,
        GmxAfterExecutionLib: gmxAfterExecutionLib.address,
      },
    });

    const args: Parameters<typeof GmxExchangeRouterContractGuard.deploy> = [
      {
        dataStore,
        feeReceiver,
        reader,
        gmxExchangeRouter: exchangeRouter,
        referralStorage,
      },
      dHedgeVaultsWhitelist,
      virtualTokenResolver,
      slippageAccumulatorAddress,
      nftTrackerStorage,
    ];

    const gmxExchangeRouterContractGuard = await GmxExchangeRouterContractGuard.deploy(...args);
    await gmxExchangeRouterContractGuard.deployed();
    const gmxExchangeRouterContractGuardAddress = gmxExchangeRouterContractGuard.address;
    console.log("gmxExchangeRouterContractGuard deployed at", gmxExchangeRouterContractGuardAddress);
    versions[config.newTag].contracts.GmxExchangeRouterContractGuard = gmxExchangeRouterContractGuardAddress;

    await tryVerify(
      hre,
      gmxExchangeRouterContractGuardAddress,
      "contracts/guards/contractGuards/gmx/GmxExchangeRouterContractGuard.sol:GmxExchangeRouterContractGuard",
      args,
    );

    // Register the new guard as the saved callback contract for every whitelisted vault on every
    // supported GMX market, so keeper-created orders (liquidations, ADLs) can reach this guard.
    // Proposed atomically with the guard installation: any failed registration reverts the batch.
    const discoveredPairs = await discoverSavedCallbackRegistrationPairs(
      hre,
      dHedgeVaultsWhitelist,
      dataStore,
      reader,
      addresses,
    );

    const { safeTransactionData, registrationPairs } = await buildGuardAndMarketActivationCalls(
      hre,
      {
        governanceAddress: versions[config.oldTag].contracts.Governance,
        exchangeRouter,
        guardAddress: gmxExchangeRouterContractGuardAddress,
        dHedgeVaultsWhitelist,
        dataStore,
        reader,
      },
      discoveredPairs,
    );

    const perPoolRegistrationCalls = await buildPerPoolRegistrationCalls(
      hre,
      registrationPairs,
      exchangeRouter,
      gmxExchangeRouterContractGuardAddress,
    );
    console.log(
      `Saved callback migration: ${perPoolRegistrationCalls.length} pool(s), ${registrationPairs.size} (pool, market) pair(s)`,
    );

    for (const poolRegistration of perPoolRegistrationCalls) {
      safeTransactionData.push(poolRegistration);
    }

    await proposeTransactions(
      safeTransactionData,
      "setContractGuard for GmxExchangeRouterContractGuard + market activation + saved callback registration",
      config,
      addresses,
    );

    await addOrReplaceGuardInFile(
      filenames.contractGuardsFileName,
      {
        contractAddress: exchangeRouter,
        guardName: "GmxExchangeRouterContractGuard",
        guardAddress: gmxExchangeRouterContractGuardAddress,
        description: "Gmx Exchange Router Guard",
      },
      "contractAddress",
    );

    if (!versions[config.oldTag].contracts.ClosedContractGuard) {
      await closedContractGuardJob(config, hre, versions, filenames, addresses);
    }

    const governance = await ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);
    const approvalRouterGuardSet = await governance.contractGuards(approvalRouter);

    if (approvalRouterGuardSet.toLowerCase() !== versions[config.newTag].contracts.ClosedContractGuard?.toLowerCase()) {
      await proposeTx(
        versions[config.oldTag].contracts.Governance,
        governanceABI.encodeFunctionData("setContractGuard", [
          approvalRouter,
          versions[config.oldTag].contracts.ClosedContractGuard,
        ]),
        "setContractGuard for GMX Approval Router",
        config,
        addresses,
      );

      await addOrReplaceGuardInFile(
        filenames.contractGuardsFileName,
        {
          contractAddress: approvalRouter,
          guardName: "ClosedContractGuard",
          guardAddress: versions[config.oldTag].contracts.ClosedContractGuard as string,
          description: "GMX Approval Router Contract Guard",
        },
        "contractAddress",
      );
    }
  }
};

type GuardAndMarketActivationParams = {
  governanceAddress: string;
  exchangeRouter: string;
  guardAddress: string;
  dHedgeVaultsWhitelist: { poolLogic: string }[];
  dataStore: string;
  reader: string;
};

/** Builds the guard installation and any new market activations in Safe execution order. */
const buildGuardAndMarketActivationCalls = async (
  hre: HardhatRuntimeEnvironment,
  params: GuardAndMarketActivationParams,
  discoveredPairs: Set<string>,
): Promise<{ safeTransactionData: MetaTransactionData[]; registrationPairs: Set<string> }> => {
  const ethers = hre.ethers;
  const governance = await ethers.getContractAt("Governance", params.governanceAddress);
  const safeTransactionData: MetaTransactionData[] = [
    {
      to: params.governanceAddress,
      value: "0",
      data: governance.interface.encodeFunctionData("setContractGuard", [params.exchangeRouter, params.guardAddress]),
    },
  ];
  const registrationPairs = new Set(discoveredPairs);
  const whitelistedPools = new Set(params.dHedgeVaultsWhitelist.map(({ poolLogic }) => poolLogic.toLowerCase()));
  const readerArtifact = await hre.artifacts.readArtifact("IGmxReader");
  const readerContract = new ethers.Contract(params.reader, readerArtifact.abi, ethers.provider);

  for (const activation of MARKET_ACTIVATIONS) {
    const market = activation.market.toLowerCase();
    const { marketToken } = await readerContract.getMarket(params.dataStore, market);
    if (marketToken.toLowerCase() !== market) {
      throw new Error(`Activation market ${market} is not a GMX market`);
    }

    for (const vault of activation.vaults) {
      const poolLogic = vault.toLowerCase();
      if (!whitelistedPools.has(poolLogic)) throw new Error(`Activation pool ${vault} is not GMX whitelisted`);

      const pair = `${poolLogic}:${market}`;
      if (registrationPairs.has(pair)) continue;

      const pool = await ethers.getContractAt("PoolLogic", poolLogic);
      const managerAddress = await pool.poolManagerLogic();
      const manager = await ethers.getContractAt("PoolManagerLogic", managerAddress);
      safeTransactionData.push({
        to: managerAddress,
        value: "0",
        data: manager.interface.encodeFunctionData("changeAssets", [[{ asset: market, isDeposit: false }], []]),
      });
      registrationPairs.add(pair);
      console.log(`Pool ${poolLogic}: enabling GMX market ${market}`);
    }
  }

  return { safeTransactionData, registrationPairs };
};

/**
 * Discovers (poolLogic, market) pairs: whitelisted pools, supported assets of type 105
 * (Gmx Perps Market), preflighted against the real GMX Reader. Throws when the pool
 * factory owner is not the proposal Safe, so the batch can never be proposed unusably.
 */
const discoverSavedCallbackRegistrationPairs = async (
  hre: HardhatRuntimeEnvironment,
  dHedgeVaultsWhitelist: { poolLogic: string; withdrawalAsset: string }[],
  dataStore: string,
  reader: string,
  addresses: IAddresses,
): Promise<Set<string>> => {
  const ethers = hre.ethers;
  // Use an untyped contract: the generated IGmxReader typings resolve getMarket's return to the
  // wrong Props struct (Order.Props instead of Market.Props), so marketToken is unavailable on it.
  const readerArtifact = await hre.artifacts.readArtifact("IGmxReader");
  const readerContract = new ethers.Contract(reader, readerArtifact.abi, ethers.provider);
  const poolFactoryOwner = addresses.protocolDaoAddress.toLowerCase();

  const pairs = new Set<string>();
  const checkedFactories = new Set<string>();

  for (const poolSetting of dHedgeVaultsWhitelist) {
    const poolLogic = poolSetting.poolLogic.toLowerCase();
    const poolLogicContract = await ethers.getContractAt("PoolLogic", poolLogic);

    const poolManagerLogicAddress = await poolLogicContract.poolManagerLogic();
    const poolManagerLogicContract = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicAddress);
    const poolFactoryAddress = (await poolLogicContract.factory()).toLowerCase();
    const poolFactoryContract = await ethers.getContractAt("PoolFactory", poolFactoryAddress);

    if (!checkedFactories.has(poolFactoryAddress)) {
      const factoryOwner = (await poolFactoryContract.owner()).toLowerCase();
      if (factoryOwner !== poolFactoryOwner) {
        throw new Error(
          `Pool factory owner ${factoryOwner} is not the proposal Safe ${poolFactoryOwner}; aborting migration`,
        );
      }
      checkedFactories.add(poolFactoryAddress);
    }

    const supportedAssets = await poolManagerLogicContract.getSupportedAssets();
    for (const supportedAsset of supportedAssets) {
      const asset = supportedAsset.asset.toLowerCase();
      // Compare via string: the generated typing maps uint16 to number while ethers may return a BigNumber.
      const assetType = (await poolFactoryContract.getAssetType(asset)).toString();
      if (assetType !== GMX_MARKET_ASSET_TYPE.toString()) continue;

      const market = await readerContract.getMarket(dataStore, asset);
      if (market.marketToken.toLowerCase() !== asset) {
        throw new Error(`Supported asset ${asset} of pool ${poolLogic} is not a GMX market token; aborting migration`);
      }

      pairs.add(`${poolLogic}:${asset}`);
    }
  }

  return pairs;
};

/**
 * Groups registration pairs per pool into one PoolLogic.execTransactions call per pool.
 */
const buildPerPoolRegistrationCalls = async (
  hre: HardhatRuntimeEnvironment,
  registrationPairs: Set<string>,
  exchangeRouter: string,
  gmxExchangeRouterContractGuardAddress: string,
): Promise<MetaTransactionData[]> => {
  const ethers = hre.ethers;
  const exchangeRouterArtifact = await hre.artifacts.readArtifact("IGmxExchangeRouter");
  const poolLogicArtifact = await hre.artifacts.readArtifact("PoolLogic");
  const exchangeRouterInterface = new ethers.utils.Interface(exchangeRouterArtifact.abi);
  const poolLogicInterface = new ethers.utils.Interface(poolLogicArtifact.abi);

  const callsByPool = new Map<string, string[]>();
  for (const pair of registrationPairs) {
    const separatorIndex = pair.indexOf(":");
    const poolLogic = pair.substring(0, separatorIndex);
    const market = pair.substring(separatorIndex + 1);
    const calls = callsByPool.get(poolLogic) ?? [];
    calls.push(market);
    callsByPool.set(poolLogic, calls);
  }

  const safeTransactionData: MetaTransactionData[] = [];
  for (const [poolLogic, markets] of callsByPool) {
    const txs = markets.map((market) => ({
      to: exchangeRouter,
      data: exchangeRouterInterface.encodeFunctionData("setSavedCallbackContract", [
        market,
        gmxExchangeRouterContractGuardAddress,
      ]),
    }));

    safeTransactionData.push({
      to: poolLogic,
      value: "0",
      data: poolLogicInterface.encodeFunctionData("execTransactions", [txs]),
    });
    console.log(`Pool ${poolLogic}: registering saved callback on ${markets.length} market(s) (${markets.join(", ")})`);
  }

  return safeTransactionData;
};
