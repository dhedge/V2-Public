import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  AssetHandler,
  DhedgeEasySwapper,
  DhedgeSwapRouter,
  Governance,
  IERC20,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  PoolPerformance,
  SushiMiniChefV2Guard,
  SynthetixGuard,
  UniswapV2RouterGuard,
  UniswapV3AssetGuard,
  UniswapV3RouterGuard,
} from "../../../../types";
import { toBytes32 } from "../../../TestHelpers";
import * as polygonData from "../../../../config/chainData/polygon-data";
import * as ovmData from "../../../../config/chainData/ovm-data";
import { getChainAssets } from "./getChainAssets";

export type NETWORK = "polygon" | "ovm";

export type IDeployments = {
  logicOwner: SignerWithAddress;
  manager: SignerWithAddress;
  dao: SignerWithAddress;
  user: SignerWithAddress;
  governance: Governance;
  assetHandler: AssetHandler;
  swapRouter: DhedgeSwapRouter;
  poolFactory: PoolFactory;
  poolLogic: PoolLogic;
  poolManagerLogic: PoolManagerLogic;
  poolPerformance: PoolPerformance;
  sushiMiniChefV2Guard?: SushiMiniChefV2Guard;
  dhedgeEasySwapper?: DhedgeEasySwapper;
  synthetixGuard?: SynthetixGuard;
  uniV3AssetGuard: UniswapV3AssetGuard;
  uniswapV2RouterGuard: UniswapV2RouterGuard;
  uniswapV3RouterGuard: UniswapV3RouterGuard;
  assets: {
    USDT: IERC20;
    USDC: IERC20;
    WETH: IERC20;
    DAI: IERC20;

    WMATIC?: IERC20;
    SUSHI?: IERC20;
    QUICK?: IERC20;
    BALANCER?: IERC20;
    SUSD?: IERC20;

    SushiLPUSDCWETH?: IERC20;
    QuickLPUSDCWETH?: IERC20;
    BALANCERLP_STABLE?: IERC20;
    BALANCERLP_WETH_BALANCER?: IERC20;

    AMUSDC?: IERC20;
    AMWETH?: IERC20;
    VariableWETH?: IERC20;
    VariableUSDT?: IERC20;
    VariableDAI?: IERC20;
  };
};

export type IAssetSetting = { asset: string; assetType: number; aggregator: string };

export const deployContracts = async (network: NETWORK): Promise<IDeployments> => {
  const [logicOwner, manager, dao, user] = await ethers.getSigners();

  const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

  const Governance = await ethers.getContractFactory("Governance");
  const governance = await Governance.deploy();

  const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
  const poolPerformance = <PoolPerformance>await upgrades.deployProxy(PoolPerformance);
  await poolPerformance.deployed();
  await poolPerformance.enable();

  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const poolLogic = await PoolLogic.deploy();

  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  const poolManagerLogic = await PoolManagerLogic.deploy();

  const assetHandler = <AssetHandler>await upgrades.deployProxy(AssetHandlerLogic, [[]]);
  await assetHandler.deployed();
  await assetHandler.setChainlinkTimeout((3600 * 24 * 365 * 10).toString()); // 10 year expiry

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

  await poolFactory.setPoolPerformanceAddress(poolPerformance.address);

  const chainAssets = await getChainAssets(poolFactory, network);
  await assetHandler.addAssets(chainAssets);

  if (network == "ovm") {
    // optimism
    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    await erc20Guard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    const openAssetGuard = await OpenAssetGuard.deploy([]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    await uniswapV2RouterGuard.deployed();

    const UniswapV3RouterGuard = await ethers.getContractFactory("UniswapV3RouterGuard");
    const uniswapV3RouterGuard = await UniswapV3RouterGuard.deploy(10, 100); // set slippage 10%
    await uniswapV3RouterGuard.deployed();

    const UniswapV3AssetGuard = await ethers.getContractFactory("UniswapV3AssetGuard");
    const uniV3AssetGuard = await UniswapV3AssetGuard.deploy();
    await uniV3AssetGuard.deployed();

    const UniswapV3NonfungiblePositionGuard = await ethers.getContractFactory("UniswapV3NonfungiblePositionGuard");
    const uniswapV3NonfungiblePositionGuard = await UniswapV3NonfungiblePositionGuard.deploy(3);
    await uniswapV3NonfungiblePositionGuard.deployed();

    const SynthetixGuard = await ethers.getContractFactory("SynthetixGuard");
    const synthetixGuard = await SynthetixGuard.deploy(ovmData.synthetix.addressResolver);
    await synthetixGuard.deployed();

    const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(
      ovmData.aaveV3.protocolDataProvider,
      ovmData.aaveV3.lendingPool,
    );
    await aaveLendingPoolAssetGuard.deployed();

    const AaveLendingL2PoolGuard = await ethers.getContractFactory("AaveLendingPoolGuardV3L2Pool");
    const aaveLendingPoolGuard = await AaveLendingL2PoolGuard.deploy(ovmData.aaveV3.lendingPool);
    await aaveLendingPoolGuard.deployed();

    const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
    const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
    await lendingEnabledAssetGuard.deployed();

    const SwapRouter = await ethers.getContractFactory("DhedgeSwapRouter");
    const swapRouter = await SwapRouter.deploy([ovmData.zipswap.router], []);
    await swapRouter.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(1, erc20Guard.address);
    await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
    await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
    await governance.setAssetGuard(6, erc20Guard.address); // set balancer lp asset guard to normal erc20 guard
    await governance.setAssetGuard(7, uniV3AssetGuard.address);
    await governance.setContractGuard(ovmData.zipswap.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(ovmData.uniswapV3.router, uniswapV3RouterGuard.address);
    await governance.setContractGuard(ovmData.aaveV3.lendingPool, aaveLendingPoolGuard.address);
    await governance.setContractGuard(ovmData.assets.snxProxy, synthetixGuard.address);
    await governance.setContractGuard(
      ovmData.uniswapV3.nonfungiblePositionManager,
      uniswapV3NonfungiblePositionGuard.address,
    );

    await governance.setAddresses([
      { name: toBytes32("swapRouter"), destination: swapRouter.address },
      { name: toBytes32("weth"), destination: ovmData.assets.weth },
      { name: toBytes32("aaveProtocolDataProviderV3"), destination: ovmData.aaveV3.protocolDataProvider },
      { name: toBytes32("openAssetGuard"), destination: openAssetGuard.address },
    ]);

    await poolFactory.setExitFee(5, 1000); // 0.5%

    const USDT = await ethers.getContractAt("IERC20", ovmData.assets.usdt);
    const USDC = await ethers.getContractAt("IERC20", ovmData.assets.usdc);
    const WETH = await ethers.getContractAt("IERC20", ovmData.assets.weth);
    const SUSD = await ethers.getContractAt("IERC20", ovmData.assets.susd);
    const DAI = await ethers.getContractAt("IERC20", ovmData.assets.dai);

    const AMUSDC = await ethers.getContractAt("IERC20", ovmData.aaveV3.aTokens.usdc);
    const AMWETH = await ethers.getContractAt("IERC20", ovmData.aaveV3.aTokens.weth);

    const VariableWETH = await ethers.getContractAt("IERC20", ovmData.aaveV3.variableDebtTokens.weth);
    const VariableUSDT = await ethers.getContractAt("IERC20", ovmData.aaveV3.variableDebtTokens.usdt);
    const VariableDAI = await ethers.getContractAt("IERC20", ovmData.aaveV3.variableDebtTokens.dai);

    return {
      logicOwner,
      manager,
      dao,
      user,
      governance,
      assetHandler,
      swapRouter,
      poolFactory,
      poolLogic,
      poolManagerLogic,
      poolPerformance,
      uniV3AssetGuard,
      uniswapV2RouterGuard,
      uniswapV3RouterGuard,
      synthetixGuard,
      assets: {
        USDT,
        USDC,
        WETH,
        DAI,
        SUSD,
        AMUSDC,
        AMWETH,
        VariableWETH,
        VariableUSDT,
        VariableDAI,
      },
    };
  } else {
    // polygon network
    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    await erc20Guard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    const openAssetGuard = await OpenAssetGuard.deploy([]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(2, 100); // set slippage 2% for testing
    await uniswapV2RouterGuard.deployed();

    const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
    const quickStakingRewardsGuard = await QuickStakingRewardsGuard.deploy();
    await quickStakingRewardsGuard.deployed();

    const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
    const quickLPAssetGuard = await QuickLPAssetGuard.deploy(polygonData.quickswap.stakingRewardsFactory);
    await quickLPAssetGuard.deployed();

    const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
    const sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy([
      polygonData.assets.sushi,
      polygonData.assets.wmatic,
    ]);
    await sushiMiniChefV2Guard.deployed();

    const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
    const sushiLPAssetGuard = await SushiLPAssetGuard.deploy(polygonData.sushi.minichef); // initialise with Sushi staking pool Id
    await sushiLPAssetGuard.deployed();

    const AaveLendingPoolAssetGuardV3 = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuardV3 = await AaveLendingPoolAssetGuardV3.deploy(
      polygonData.aaveV3.protocolDataProvider,
      polygonData.aaveV3.lendingPool,
    );
    await aaveLendingPoolAssetGuardV3.deployed();

    const AaveLendingPoolGuardV3 = await ethers.getContractFactory("AaveLendingPoolGuardV3");
    const aaveLendingPoolGuardV3 = await AaveLendingPoolGuardV3.deploy();
    await aaveLendingPoolGuardV3.deployed();

    const AaveLendingPoolAssetGuardV2 = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuardV2 = await AaveLendingPoolAssetGuardV2.deploy(
      polygonData.aaveV2.protocolDataProvider,
      polygonData.aaveV2.lendingPool,
    );
    await aaveLendingPoolAssetGuardV2.deployed();

    const AaveLendingPoolGuardV2 = await ethers.getContractFactory("AaveLendingPoolGuardV2");
    const aaveLendingPoolGuardV2 = await AaveLendingPoolGuardV2.deploy();
    await aaveLendingPoolGuardV2.deployed();

    const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
    const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
    await lendingEnabledAssetGuard.deployed();

    const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
    const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy(polygonData.assets.wmatic);
    await aaveIncentivesControllerGuard.deployed();

    const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
    const balancerV2Guard = await BalancerV2Guard.deploy(2, 100); // set slippage 2%
    await balancerV2Guard.deployed();

    const BalancerMerkleOrchardGuard = await ethers.getContractFactory("BalancerMerkleOrchardGuard");
    const balancerMerkleOrchardGuard = await BalancerMerkleOrchardGuard.deploy();
    await balancerMerkleOrchardGuard.deployed();

    const OneInchV4Guard = await ethers.getContractFactory("OneInchV4Guard");
    const oneInchV4Guard = await OneInchV4Guard.deploy(2, 100); // set slippage 2%
    await oneInchV4Guard.deployed();

    const SwapRouter = await ethers.getContractFactory("DhedgeSwapRouter");
    const swapRouter = await SwapRouter.deploy([polygonData.quickswap.router, polygonData.sushi.router], []);
    await swapRouter.deployed();

    const EasySwapperGuard = await ethers.getContractFactory("EasySwapperGuard");
    const easySwapperGuard = await EasySwapperGuard.deploy();
    await easySwapperGuard.deployed();

    const UniswapV3RouterGuard = await ethers.getContractFactory("UniswapV3RouterGuard");
    const uniswapV3RouterGuard = await UniswapV3RouterGuard.deploy(10, 100); // set slippage 10%
    uniswapV3RouterGuard.deployed();

    const UniswapV3AssetGuard = await ethers.getContractFactory("UniswapV3AssetGuard");
    const uniV3AssetGuard = await UniswapV3AssetGuard.deploy();
    await uniV3AssetGuard.deployed();

    const UniswapV3NonfungiblePositionGuard = await ethers.getContractFactory("UniswapV3NonfungiblePositionGuard");
    const uniswapV3NonfungiblePositionGuard = await UniswapV3NonfungiblePositionGuard.deploy(3);
    await uniswapV3NonfungiblePositionGuard.deployed();
    const DhedgeEasySwapper = await ethers.getContractFactory("DhedgeEasySwapper");
    const dhedgeEasySwapper = await DhedgeEasySwapper.deploy(dao.address, {
      swapRouter: polygonData.quickswap.router,
      weth: polygonData.assets.weth,
      assetType2Router: polygonData.sushi.router,
      assetType5Router: polygonData.quickswap.router,
      poolFactory: poolFactory.address,
    });
    await dhedgeEasySwapper.deployed();
    await dhedgeEasySwapper.setFee(0, 0);

    await poolFactory.addTransferWhitelist(dhedgeEasySwapper.address);

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(2, sushiLPAssetGuard.address);
    await governance.setAssetGuard(3, aaveLendingPoolAssetGuardV2.address);
    await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
    await governance.setAssetGuard(5, quickLPAssetGuard.address);
    await governance.setAssetGuard(6, erc20Guard.address); // set balancer lp asset guard to normal erc20 guard
    await governance.setAssetGuard(7, uniV3AssetGuard.address);
    await governance.setAssetGuard(8, aaveLendingPoolAssetGuardV3.address);
    await governance.setContractGuard(polygonData.quickswap.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(
      polygonData.quickswap.pools.usdc_weth.stakingRewards,
      quickStakingRewardsGuard.address,
    );
    await governance.setContractGuard(polygonData.sushi.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(polygonData.sushi.minichef, sushiMiniChefV2Guard.address);
    await governance.setContractGuard(polygonData.aaveV2.lendingPool, aaveLendingPoolGuardV2.address);
    await governance.setContractGuard(polygonData.aaveV3.lendingPool, aaveLendingPoolGuardV3.address);
    await governance.setContractGuard(polygonData.aaveV2.incentivesController, aaveIncentivesControllerGuard.address);
    await governance.setContractGuard(polygonData.balancer.v2Vault, balancerV2Guard.address);
    await governance.setContractGuard(polygonData.balancer.merkleOrchard, balancerMerkleOrchardGuard.address);
    await governance.setContractGuard(polygonData.oneinch.v3Router, oneInchV4Guard.address);
    await governance.setContractGuard(dhedgeEasySwapper.address, easySwapperGuard.address);
    await governance.setContractGuard(polygonData.uniswapV3.router, uniswapV3RouterGuard.address);
    await governance.setContractGuard(
      polygonData.uniswapV3.nonfungiblePositionManager,
      uniswapV3NonfungiblePositionGuard.address,
    );

    await governance.setAddresses([
      { name: toBytes32("swapRouter"), destination: swapRouter.address },
      { name: toBytes32("aaveProtocolDataProviderV2"), destination: polygonData.aaveV2.protocolDataProvider },
      { name: toBytes32("aaveProtocolDataProviderV3"), destination: polygonData.aaveV3.protocolDataProvider },
      { name: toBytes32("weth"), destination: polygonData.assets.weth },
      { name: toBytes32("openAssetGuard"), destination: openAssetGuard.address },
    ]);

    await poolFactory.setExitFee(5, 1000); // 0.5%

    const WMATIC = await ethers.getContractAt("IERC20", polygonData.assets.wmatic);
    const USDT = await ethers.getContractAt("IERC20", polygonData.assets.usdt);
    const DAI = await ethers.getContractAt("IERC20", polygonData.assets.dai);
    const USDC = await ethers.getContractAt("IERC20", polygonData.assets.usdc);
    const WETH = await ethers.getContractAt("IERC20", polygonData.assets.weth);
    const SUSHI = await ethers.getContractAt("IERC20", polygonData.assets.sushi);
    const BALANCER = await ethers.getContractAt("IERC20", polygonData.assets.balancer);
    const QUICK = await ethers.getContractAt("IERC20", polygonData.assets.quick);

    const SushiLPUSDCWETH = await ethers.getContractAt("IERC20", polygonData.sushi.pools.usdc_weth.address);
    const QuickLPUSDCWETH = await ethers.getContractAt("IERC20", polygonData.quickswap.pools.usdc_weth.address);

    const AMUSDC = await ethers.getContractAt("IERC20", polygonData.aaveV2.aTokens.usdc);
    const AMWETH = await ethers.getContractAt("IERC20", polygonData.aaveV2.aTokens.weth);

    const VariableWETH = await ethers.getContractAt("IERC20", polygonData.aaveV2.variableDebtTokens.weth);
    const VariableUSDT = await ethers.getContractAt("IERC20", polygonData.aaveV2.variableDebtTokens.usdt);
    const VariableDAI = await ethers.getContractAt("IERC20", polygonData.aaveV2.variableDebtTokens.dai);

    const BALANCERLP_STABLE = await ethers.getContractAt("IERC20", polygonData.balancer.stablePools.BPSP);
    const BALANCERLP_WETH_BALANCER = await ethers.getContractAt("IERC20", polygonData.balancer.pools.bal80weth20);

    return {
      logicOwner,
      manager,
      dao,
      user,
      governance,
      assetHandler,
      swapRouter,
      poolFactory,
      poolLogic,
      poolManagerLogic,
      poolPerformance,
      sushiMiniChefV2Guard,
      dhedgeEasySwapper,
      uniV3AssetGuard,
      uniswapV2RouterGuard,
      uniswapV3RouterGuard,
      assets: {
        WMATIC,
        USDT,
        USDC,
        DAI,
        WETH,
        SUSHI,
        QUICK,
        BALANCER,
        SushiLPUSDCWETH,
        QuickLPUSDCWETH,
        AMUSDC,
        AMWETH,
        VariableWETH,
        VariableUSDT,
        VariableDAI,
        BALANCERLP_STABLE,
        BALANCERLP_WETH_BALANCER,
      },
    };
  }
};
