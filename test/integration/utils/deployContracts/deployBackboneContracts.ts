import { ethers, upgrades } from "hardhat";

import { AssetHandler, IERC20, IERC20__factory, PoolFactory } from "../../../../types";
import { assetSetting } from "./getChainAssets";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

export const IERC20Path = "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20";

export const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

export type IBackboneDeploymentsParams = {
  assets: {
    weth: string;
    usdc: string;
    dai: string;
  };
  usdPriceFeeds: {
    eth: string;
    usdc: string;
    dai: string;
  };
};

export const deployBackboneContracts = async ({ assets, usdPriceFeeds }: IBackboneDeploymentsParams) => {
  const [owner, manager, dao, user] = await ethers.getSigners();

  const Governance = await ethers.getContractFactory("Governance");
  const governance = await Governance.deploy();
  await governance.deployed();

  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const poolLogic = await PoolLogic.deploy();
  await poolLogic.deployed();

  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  const poolManagerLogic = await PoolManagerLogic.deploy();
  await poolManagerLogic.deployed();

  const AssetHandler = await ethers.getContractFactory("AssetHandler");
  const assetHandler = <AssetHandler>(
    await upgrades.deployProxy(AssetHandler, [
      [
        assetSetting(assets.weth, AssetType["Lending Enable Asset"], usdPriceFeeds.eth),
        assetSetting(assets.usdc, AssetType["Lending Enable Asset"], usdPriceFeeds.usdc),
        assetSetting(assets.dai, AssetType["Lending Enable Asset"], usdPriceFeeds.dai),
      ],
    ])
  );
  await assetHandler.deployed();

  const PoolFactory = await ethers.getContractFactory("PoolFactory");
  const poolFactory = <PoolFactory>(
    await upgrades.deployProxy(PoolFactory, [
      poolLogic.address,
      poolManagerLogic.address,
      assetHandler.address,
      dao.address,
      governance.address,
    ])
  );
  await poolFactory.deployed();

  const SlippageAccumulator = await ethers.getContractFactory("SlippageAccumulator");
  const slippageAccumulator = await SlippageAccumulator.deploy(poolFactory.address, 21600, 5e4); // Decay time set to 6 hours and max cumulative slippage to 5%.
  await slippageAccumulator.deployed();

  const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
  const usdPriceAggregator = await USDPriceAggregator.deploy();
  await usdPriceAggregator.deployed();

  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const erc20Guard = await ERC20Guard.deploy();
  await erc20Guard.deployed();

  const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
  const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
  await lendingEnabledAssetGuard.deployed();

  await governance.setAssetGuard(AssetType["Chainlink direct USD price feed with 8 decimals"], erc20Guard.address);
  await governance.setAssetGuard(AssetType["Lending Enable Asset"], lendingEnabledAssetGuard.address);
  await governance.setAssetGuard(AssetType["Balancer LP"], erc20Guard.address);

  const WETH = <IERC20>await ethers.getContractAt(IERC20Path, assets.weth);
  const USDC = <IERC20>await ethers.getContractAt(IERC20Path, assets.usdc);
  const DAI = <IERC20>await ethers.getContractAt(IERC20Path, assets.dai);

  return {
    owner,
    manager,
    dao,
    user,
    governance,
    assetHandler,
    poolFactory,
    poolLogic,
    poolManagerLogic,
    slippageAccumulator,
    usdPriceAggregator,
    lendingEnabledAssetGuard,
    assets: {
      WETH,
      USDC,
      DAI,
    },
  };
};

export type IBackboneDeployments = Awaited<ReturnType<typeof deployBackboneContracts>>;
