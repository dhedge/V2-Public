import { TestSystem, TestSystemContractsType } from "@lyrafinance/protocol";
import { IOptionMarket, IOptionToken } from "@lyrafinance/protocol/dist/typechain-types";
import { ethers } from "hardhat";
import { ChainDataOVM } from "../../../../config/chainData/chainDataTypes";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { ILyraRegistry } from "../../../../types";
import { IDeployments } from "../../utils/deployContracts/deployContracts";
import { assetSetting } from "../../utils/deployContracts/getChainAssets";

const MAX_LYRA_POSITIONS = 2;

export const deployLyraAndConfigureMarket = async (
  deployments: IDeployments,
  lyraConfig: {
    dhedgeLyraWrapper?: string;
    optionMarketWrapper: string;
    synthetixAdapter: string;
    optionMarketViewer: string;
    lyraRegistry: string;
    quoter: string;
  },
) => {
  const { assetHandler, governance } = deployments;
  const lyraRegistry: ILyraRegistry = (await ethers.getContractAt(
    "contracts/interfaces/lyra/ILyraRegistry.sol:ILyraRegistry",
    lyraConfig.lyraRegistry,
  )) as unknown as ILyraRegistry;
  const market = await lyraRegistry.optionMarkets(0);

  const marketAddresses = await lyraRegistry.getMarketAddresses(market);
  const optionTokenAddress = marketAddresses.optionToken;
  const baseAsset = marketAddresses.baseAsset;
  const quoteAsset = marketAddresses.quoteAsset;

  const optionToken = (await ethers.getContractAt(
    "@lyrafinance/protocol/contracts/interfaces/IOptionToken.sol:IOptionToken",
    optionTokenAddress,
  )) as unknown as IOptionToken;

  const optionMarket = (await ethers.getContractAt(
    "@lyrafinance/protocol/contracts/interfaces/IOptionMarket.sol:IOptionMarket",
    marketAddresses.optionMarket,
  )) as unknown as IOptionMarket;

  const baseAssetAgg = await assetHandler.priceAggregators(baseAsset);
  if (baseAsset == ethers.constants.AddressZero) {
    throw new Error("No agg for baseAsset");
  }
  const quoteAssetAgg = await assetHandler.priceAggregators(quoteAsset);
  if (quoteAsset == ethers.constants.AddressZero) {
    throw new Error("No agg for quoteAsset");
  }
  await assetHandler.addAssets([
    assetSetting(lyraConfig.optionMarketWrapper, 100, ovmChainData.price_feeds.susd),
    assetSetting(baseAsset, 1, baseAssetAgg),
    assetSetting(quoteAsset, 1, quoteAssetAgg),
  ]);

  const LyraOptionMarketWrapperContractGuardRollups = await ethers.getContractFactory(
    "LyraOptionMarketWrapperContractGuardRollups",
  );
  const lyraOptionMarketWrapperContractGuard = await LyraOptionMarketWrapperContractGuardRollups.deploy(
    lyraConfig.lyraRegistry,
    deployments.dhedgeNftTrackerStorage.address,
    MAX_LYRA_POSITIONS,
  );
  await lyraOptionMarketWrapperContractGuard.deployed();

  const DhedgeOptionMarketWrapperForLyra = await ethers.getContractFactory("DhedgeOptionMarketWrapperForLyra");
  const dhedgeOptionMarketWrapperForLyra = await DhedgeOptionMarketWrapperForLyra.deploy(
    lyraConfig.lyraRegistry,
    ovmChainData.aaveV3.lendingPool,
  );
  await dhedgeOptionMarketWrapperForLyra.deployed();

  const LyraOptionMarketWrapperAssetGuard = await ethers.getContractFactory("LyraOptionMarketWrapperAssetGuard");
  const lyraOptionMarketWrapperAssetGuard = await LyraOptionMarketWrapperAssetGuard.deploy(
    dhedgeOptionMarketWrapperForLyra.address,
  );
  await lyraOptionMarketWrapperAssetGuard.deployed();

  await governance.setAssetGuard(100, lyraOptionMarketWrapperAssetGuard.address);

  await governance.setContractGuard(lyraConfig.optionMarketWrapper, lyraOptionMarketWrapperContractGuard.address);

  await governance.setContractGuard(optionTokenAddress, deployments.erc721ContractGuard.address);

  return { optionToken, optionMarket, baseAsset, quoteAsset, lyraOptionMarketWrapperAssetGuard, baseAssetAgg };
};

export const deployLyraTestSystem = async (
  deployments: IDeployments,
  chainData: ChainDataOVM,
): Promise<TestSystemContractsType> => {
  const { assetHandler, governance, dhedgeNftTrackerStorage, erc721ContractGuard } = deployments;
  // deploy lyra
  const signer = (await ethers.getSigners())[0];
  const testSystem = await TestSystem.deploy(signer);
  await TestSystem.seed(signer, testSystem);

  const MockAggregatorV2V3 = await ethers.getContractFactory("MockAggregatorV2V3");
  const ethMockAggregator = await MockAggregatorV2V3.deploy();

  await assetHandler.addAssets([
    { asset: testSystem.optionMarketWrapper.address, assetType: 100, aggregator: chainData.price_feeds.susd },
    { asset: testSystem.snx.baseAsset.address, assetType: 1, aggregator: ethMockAggregator.address },
    { asset: testSystem.snx.quoteAsset.address, assetType: 1, aggregator: chainData.price_feeds.susd },
  ]);

  const LyraOptionMarketWrapperContractGuardRollups = await ethers.getContractFactory(
    "LyraOptionMarketWrapperContractGuardRollups",
  );
  const lyraOptionMarketWrapperContractGuard = await LyraOptionMarketWrapperContractGuardRollups.deploy(
    testSystem.lyraRegistry.address,
    dhedgeNftTrackerStorage.address,
    2,
  );
  await lyraOptionMarketWrapperContractGuard.deployed();

  const LyraOptionMarketContractGuard = await ethers.getContractFactory("LyraOptionMarketContractGuard");
  const lyraOptionMarketContractGuard = await LyraOptionMarketContractGuard.deploy(
    testSystem.lyraRegistry.address,
    dhedgeNftTrackerStorage.address,
    2,
  );

  await governance.setContractGuard(testSystem.optionMarket.address, lyraOptionMarketContractGuard.address);

  // prepare aave flashloan mock
  const AaveFlashloanMock = await ethers.getContractFactory("AaveFlashloanMock");
  const aaveFlashloanMock = await AaveFlashloanMock.deploy();
  await aaveFlashloanMock.deployed();

  const DhedgeOptionMarketWrapperForLyra = await ethers.getContractFactory("DhedgeOptionMarketWrapperForLyra");
  const dhedgeOptionMarketWrapperForLyra = await DhedgeOptionMarketWrapperForLyra.deploy(
    testSystem.lyraRegistry.address,
    aaveFlashloanMock.address,
  );
  await dhedgeOptionMarketWrapperForLyra.deployed();

  const LyraOptionMarketWrapperAssetGuard = await ethers.getContractFactory("LyraOptionMarketWrapperAssetGuard");
  const lyraOptionMarketWrapperAssetGuard = await LyraOptionMarketWrapperAssetGuard.deploy(
    dhedgeOptionMarketWrapperForLyra.address,
  );
  await lyraOptionMarketWrapperAssetGuard.deployed();

  await governance.setAssetGuard(100, lyraOptionMarketWrapperAssetGuard.address);

  await governance.setContractGuard(
    testSystem.optionMarketWrapper.address,
    lyraOptionMarketWrapperContractGuard.address,
  );
  await governance.setContractGuard(testSystem.optionToken.address, erc721ContractGuard.address);
  return testSystem;
};
