import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  AssetHandler,
  DhedgeEasySwapper,
  DhedgeSuperSwapper,
  Governance,
  IERC20,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  SushiMiniChefV2Guard,
  SynthetixGuard,
  UniswapV2RouterGuard,
  UniswapV3AssetGuard,
  UniswapV3RouterGuard,
  DhedgeNftTrackerStorage,
  ERC721ContractGuard,
  SlippageAccumulator,
  BalancerV2Guard,
  OneInchV5Guard,
} from "../../../../types";
import { toBytes32 } from "../../../testHelpers";
import { polygonChainData } from "../../../../config/chainData/polygonData";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { getChainAssets } from "./getChainAssets";

export type NETWORK = "polygon" | "ovm";

export type IDeployments = {
  logicOwner: SignerWithAddress;
  manager: SignerWithAddress;
  dao: SignerWithAddress;
  user: SignerWithAddress;
  governance: Governance;
  assetHandler: AssetHandler;
  swapRouter: DhedgeSuperSwapper;
  poolFactory: PoolFactory;
  poolLogic: PoolLogic;
  poolManagerLogic: PoolManagerLogic;
  slippageAccumulator: SlippageAccumulator;
  sushiMiniChefV2Guard?: SushiMiniChefV2Guard;
  dhedgeEasySwapper?: DhedgeEasySwapper;
  synthetixGuard?: SynthetixGuard;
  uniV3AssetGuard: UniswapV3AssetGuard;
  uniswapV2RouterGuard: UniswapV2RouterGuard;
  uniswapV3RouterGuard: UniswapV3RouterGuard;
  balancerV2Guard?: BalancerV2Guard;
  oneInchV5Guard?: OneInchV5Guard;
  dhedgeNftTrackerStorage: DhedgeNftTrackerStorage;
  erc721ContractGuard: ERC721ContractGuard;
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
    OP?: IERC20;

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

  const SlippageAccumulator = await ethers.getContractFactory("SlippageAccumulator");
  const slippageAccumulator = <SlippageAccumulator>await SlippageAccumulator.deploy(poolFactory.address, "21600", 5e4); // Decay time set to 6 hours and max cumulative slippage to 5%.
  slippageAccumulator.deployed();

  const chainAssets = await getChainAssets(poolFactory, network);
  await assetHandler.addAssets(chainAssets);

  const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
  const dhedgeNftTrackerStorage = <DhedgeNftTrackerStorage>(
    await upgrades.deployProxy(DhedgeNftTrackerStorage, [poolFactory.address])
  );
  await dhedgeNftTrackerStorage.deployed();

  const ERC721ContractGuard = await ethers.getContractFactory("ERC721ContractGuard");
  const erc721ContractGuard = await ERC721ContractGuard.deploy();
  await erc721ContractGuard.deployed();

  if (network == "ovm") {
    // optimism

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    await erc20Guard.deployed();

    const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
    const openAssetGuard = await OpenAssetGuard.deploy([]);
    await openAssetGuard.deployed();

    const UniswapV2RouterGuard = await ethers.getContractFactory("UniswapV2RouterGuard");
    const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(slippageAccumulator.address);
    await uniswapV2RouterGuard.deployed();

    const UniswapV3RouterGuard = await ethers.getContractFactory("UniswapV3RouterGuard");
    const uniswapV3RouterGuard = await UniswapV3RouterGuard.deploy(slippageAccumulator.address);
    await uniswapV3RouterGuard.deployed();

    const UniswapV3AssetGuard = await ethers.getContractFactory("UniswapV3AssetGuard");
    const uniV3AssetGuard = await UniswapV3AssetGuard.deploy();
    await uniV3AssetGuard.deployed();

    const UniswapV3NonfungiblePositionGuard = await ethers.getContractFactory("UniswapV3NonfungiblePositionGuard");
    const uniswapV3NonfungiblePositionGuard = await UniswapV3NonfungiblePositionGuard.deploy(
      3,
      dhedgeNftTrackerStorage.address,
    );
    await uniswapV3NonfungiblePositionGuard.deployed();

    const SynthetixGuard = await ethers.getContractFactory("SynthetixGuard");
    const synthetixGuard = await SynthetixGuard.deploy(ovmChainData.synthetix.addressResolver);
    await synthetixGuard.deployed();

    const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuard = await AaveLendingPoolAssetGuard.deploy(
      ovmChainData.aaveV3.protocolDataProvider,
      ovmChainData.aaveV3.lendingPool,
    );
    await aaveLendingPoolAssetGuard.deployed();

    const AaveLendingL2PoolGuard = await ethers.getContractFactory("AaveLendingPoolGuardV3L2Pool");
    const aaveLendingPoolGuard = await AaveLendingL2PoolGuard.deploy(ovmChainData.aaveV3.lendingPool);
    await aaveLendingPoolGuard.deployed();

    const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
    const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
    await lendingEnabledAssetGuard.deployed();

    const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerV3Guard");
    const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy();
    await aaveIncentivesControllerGuard.deployed();

    const UniV3V2SwapRouter = await ethers.getContractFactory("DhedgeUniV3V2Router");
    const v3v2SwapRouter = await UniV3V2SwapRouter.deploy(
      ovmChainData.uniswapV3.factory,
      ovmChainData.uniswapV3.router,
    );
    await v3v2SwapRouter.deployed();

    const DhedgeVeloV2UniV2Router = await ethers.getContractFactory("DhedgeVeloV2UniV2Router");
    const dhedgeVeloV2UniV2Router = await DhedgeVeloV2UniV2Router.deploy(
      ovmChainData.velodromeV2.router,
      ovmChainData.velodromeV2.factory,
    );
    await dhedgeVeloV2UniV2Router.deployed();

    const SwapRouter = await ethers.getContractFactory("DhedgeSuperSwapper");
    const routeHints = [];
    const swapRouter = await SwapRouter.deploy([v3v2SwapRouter.address, dhedgeVeloV2UniV2Router.address], routeHints);
    await swapRouter.deployed();
    const VelodromeRouterGuard = await ethers.getContractFactory("VelodromeRouterGuard");
    const velodromeRouterGuard = await VelodromeRouterGuard.deploy();
    await velodromeRouterGuard.deployed();

    const VelodromeGaugeContractGuard = await ethers.getContractFactory("VelodromeGaugeContractGuard");
    const velodromeGaugeContractGuard = await VelodromeGaugeContractGuard.deploy();
    await velodromeGaugeContractGuard.deployed();

    const VelodromeLPAssetGuard = await ethers.getContractFactory("VelodromeLPAssetGuard");
    const velodromeLPAssetGuard = await VelodromeLPAssetGuard.deploy(ovmChainData.velodrome.voter);
    await velodromeLPAssetGuard.deployed();

    const VelodromeV2RouterGuard = await ethers.getContractFactory("VelodromeV2RouterGuard");
    const velodromeV2RouterGuard = await VelodromeV2RouterGuard.deploy();
    await velodromeV2RouterGuard.deployed();

    const VelodromeV2GaugeContractGuard = await ethers.getContractFactory("VelodromeV2GaugeContractGuard");
    const velodromeV2GaugeContractGuard = await VelodromeV2GaugeContractGuard.deploy();
    await velodromeV2GaugeContractGuard.deployed();

    const VelodromeV2LPAssetGuard = await ethers.getContractFactory("VelodromeV2LPAssetGuard");
    const velodromeV2LPAssetGuard = await VelodromeV2LPAssetGuard.deploy(ovmChainData.velodromeV2.voter);
    await velodromeV2LPAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(1, erc20Guard.address);
    await governance.setAssetGuard(3, aaveLendingPoolAssetGuard.address);
    await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
    await governance.setAssetGuard(14, lendingEnabledAssetGuard.address);
    await governance.setAssetGuard(6, erc20Guard.address); // set balancer lp asset guard to normal erc20 guard
    await governance.setAssetGuard(7, uniV3AssetGuard.address);
    await governance.setAssetGuard(15, velodromeLPAssetGuard.address);
    await governance.setAssetGuard(25, velodromeV2LPAssetGuard.address);

    await governance.setContractGuard(ovmChainData.zipswap.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(ovmChainData.uniswapV3.router, uniswapV3RouterGuard.address);
    await governance.setContractGuard(ovmChainData.aaveV3.lendingPool, aaveLendingPoolGuard.address);
    await governance.setContractGuard(ovmChainData.aaveV3.incentivesController, aaveIncentivesControllerGuard.address);
    await governance.setContractGuard(ovmChainData.assets.snxProxy, synthetixGuard.address);
    await governance.setContractGuard(
      ovmChainData.uniswapV3.nonfungiblePositionManager,
      uniswapV3NonfungiblePositionGuard.address,
    );
    await governance.setContractGuard(ovmChainData.velodrome.router, velodromeRouterGuard.address);
    await governance.setContractGuard(
      ovmChainData.velodrome.VARIABLE_WETH_USDC.gaugeAddress,
      velodromeGaugeContractGuard.address,
    );
    await governance.setContractGuard(
      ovmChainData.velodrome.STABLE_USDC_DAI.gaugeAddress,
      velodromeGaugeContractGuard.address,
    );

    await governance.setContractGuard(ovmChainData.velodromeV2.router, velodromeV2RouterGuard.address);
    await governance.setContractGuard(
      ovmChainData.velodromeV2.VARIABLE_WETH_USDC.gaugeAddress,
      velodromeV2GaugeContractGuard.address,
    );
    await governance.setContractGuard(
      ovmChainData.velodromeV2.STABLE_USDC_DAI.gaugeAddress,
      velodromeV2GaugeContractGuard.address,
    );

    await governance.setAddresses([
      { name: toBytes32("swapRouter"), destination: swapRouter.address },
      { name: toBytes32("weth"), destination: ovmChainData.assets.weth },
      { name: toBytes32("aaveProtocolDataProviderV3"), destination: ovmChainData.aaveV3.protocolDataProvider },
      { name: toBytes32("openAssetGuard"), destination: openAssetGuard.address },
    ]);

    const USDT = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", ovmChainData.assets.usdt)
    );
    const USDC = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", ovmChainData.assets.usdc)
    );
    const WETH = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", ovmChainData.assets.weth)
    );
    const SUSD = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", ovmChainData.assets.susd)
    );
    const DAI = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", ovmChainData.assets.dai)
    );
    const OP = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", ovmChainData.assets.op)
    );

    const AMUSDC = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        ovmChainData.aaveV3.aTokens.usdc,
      )
    );
    const AMWETH = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        ovmChainData.aaveV3.aTokens.weth,
      )
    );

    const VariableWETH = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        ovmChainData.aaveV3.variableDebtTokens.weth,
      )
    );
    const VariableUSDT = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        ovmChainData.aaveV3.variableDebtTokens.usdt,
      )
    );
    const VariableDAI = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        ovmChainData.aaveV3.variableDebtTokens.dai,
      )
    );

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
      slippageAccumulator,
      uniV3AssetGuard,
      uniswapV2RouterGuard,
      uniswapV3RouterGuard,
      synthetixGuard,
      dhedgeNftTrackerStorage,
      erc721ContractGuard,
      assets: {
        USDT,
        USDC,
        WETH,
        DAI,
        SUSD,
        OP,
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
    const uniswapV2RouterGuard = await UniswapV2RouterGuard.deploy(slippageAccumulator.address);
    await uniswapV2RouterGuard.deployed();

    const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
    const quickStakingRewardsGuard = await QuickStakingRewardsGuard.deploy();
    await quickStakingRewardsGuard.deployed();

    const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
    const quickLPAssetGuard = await QuickLPAssetGuard.deploy(polygonChainData.quickswap.stakingRewardsFactory);
    await quickLPAssetGuard.deployed();

    const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
    const sushiMiniChefV2Guard = await SushiMiniChefV2Guard.deploy([
      polygonChainData.assets.sushi,
      polygonChainData.assets.wmatic,
    ]);
    await sushiMiniChefV2Guard.deployed();

    const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
    const sushiLPAssetGuard = await SushiLPAssetGuard.deploy(polygonChainData.sushi.minichef); // initialise with Sushi staking pool Id
    await sushiLPAssetGuard.deployed();

    const AaveLendingPoolAssetGuardV3 = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuardV3 = await AaveLendingPoolAssetGuardV3.deploy(
      polygonChainData.aaveV3.protocolDataProvider,
      polygonChainData.aaveV3.lendingPool,
    );
    await aaveLendingPoolAssetGuardV3.deployed();

    const AaveLendingPoolGuardV3 = await ethers.getContractFactory("AaveLendingPoolGuardV3");
    const aaveLendingPoolGuardV3 = await AaveLendingPoolGuardV3.deploy();
    await aaveLendingPoolGuardV3.deployed();

    const AaveLendingPoolAssetGuardV2 = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
    const aaveLendingPoolAssetGuardV2 = await AaveLendingPoolAssetGuardV2.deploy(
      polygonChainData.aaveV2.protocolDataProvider,
      polygonChainData.aaveV2.lendingPool,
    );
    await aaveLendingPoolAssetGuardV2.deployed();

    const AaveLendingPoolGuardV2 = await ethers.getContractFactory("AaveLendingPoolGuardV2");
    const aaveLendingPoolGuardV2 = await AaveLendingPoolGuardV2.deploy();
    await aaveLendingPoolGuardV2.deployed();

    const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
    const lendingEnabledAssetGuard = await LendingEnabledAssetGuard.deploy();
    await lendingEnabledAssetGuard.deployed();

    const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerV3Guard");
    const aaveIncentivesControllerGuard = await AaveIncentivesControllerGuard.deploy();
    await aaveIncentivesControllerGuard.deployed();

    const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");
    const balancerV2Guard = await BalancerV2Guard.deploy(slippageAccumulator.address);
    await balancerV2Guard.deployed();

    const BalancerMerkleOrchardGuard = await ethers.getContractFactory("BalancerMerkleOrchardGuard");
    const balancerMerkleOrchardGuard = await BalancerMerkleOrchardGuard.deploy();
    await balancerMerkleOrchardGuard.deployed();

    const OneInchV5Guard = await ethers.getContractFactory("OneInchV5Guard");
    const oneInchV5Guard = await OneInchV5Guard.deploy(slippageAccumulator.address);
    await oneInchV5Guard.deployed();

    const SwapRouter = await ethers.getContractFactory("DhedgeSuperSwapper");
    const routeHints = [];
    const swapRouter = await SwapRouter.deploy(
      [polygonChainData.quickswap.router, polygonChainData.sushi.router],
      routeHints,
    );
    await swapRouter.deployed();

    const EasySwapperGuard = await ethers.getContractFactory("EasySwapperGuard");
    const easySwapperGuard = await EasySwapperGuard.deploy();
    await easySwapperGuard.deployed();

    const UniswapV3RouterGuard = await ethers.getContractFactory("UniswapV3RouterGuard");
    const uniswapV3RouterGuard = await UniswapV3RouterGuard.deploy(slippageAccumulator.address);
    uniswapV3RouterGuard.deployed();

    const UniswapV3AssetGuard = await ethers.getContractFactory("UniswapV3AssetGuard");
    const uniV3AssetGuard = await UniswapV3AssetGuard.deploy();
    await uniV3AssetGuard.deployed();

    const UniswapV3NonfungiblePositionGuard = await ethers.getContractFactory("UniswapV3NonfungiblePositionGuard");
    const uniswapV3NonfungiblePositionGuard = await UniswapV3NonfungiblePositionGuard.deploy(
      3,
      dhedgeNftTrackerStorage.address,
    );
    await uniswapV3NonfungiblePositionGuard.deployed();

    const DhedgeEasySwapper = await ethers.getContractFactory("DhedgeEasySwapper");
    const dhedgeEasySwapper = <DhedgeEasySwapper>await upgrades.deployProxy(DhedgeEasySwapper, [
      dao.address,
      0, // fee numerator
      0, // fee denominator
    ]);

    await dhedgeEasySwapper.deployed();
    await dhedgeEasySwapper.setWithdrawProps({
      swapRouter: polygonChainData.quickswap.router,
      weth: polygonChainData.assets.weth,
      synthetixProps: {
        snxProxy: polygonChainData.ZERO_ADDRESS,
        swapSUSDToAsset: polygonChainData.assets.dai,
        sUSDProxy: polygonChainData.ZERO_ADDRESS,
      },
      nativeAssetWrapper: polygonChainData.assets.wmatic,
    });

    await poolFactory.addCustomCooldownWhitelist(dhedgeEasySwapper.address);

    const BalancerV2GaugeContractGuard = await ethers.getContractFactory("BalancerV2GaugeContractGuard");
    const balancerV2GaugeContractGuard = await BalancerV2GaugeContractGuard.deploy();
    await balancerV2GaugeContractGuard.deployed();

    const BalancerV2GaugeAssetGuard = await ethers.getContractFactory("BalancerV2GaugeAssetGuard");
    const balancerV2GaugeAssetGuard = await BalancerV2GaugeAssetGuard.deploy();
    await balancerV2GaugeAssetGuard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(2, sushiLPAssetGuard.address);
    await governance.setAssetGuard(3, aaveLendingPoolAssetGuardV2.address);
    await governance.setAssetGuard(4, lendingEnabledAssetGuard.address);
    await governance.setAssetGuard(14, lendingEnabledAssetGuard.address);
    await governance.setAssetGuard(5, quickLPAssetGuard.address);
    await governance.setAssetGuard(6, erc20Guard.address); // set balancer lp asset guard to normal erc20 guard
    await governance.setAssetGuard(7, uniV3AssetGuard.address);
    await governance.setAssetGuard(8, aaveLendingPoolAssetGuardV3.address);
    await governance.setAssetGuard(10, balancerV2GaugeAssetGuard.address);

    await governance.setContractGuard(polygonChainData.quickswap.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(
      polygonChainData.quickswap.pools.usdc_weth.stakingRewards,
      quickStakingRewardsGuard.address,
    );
    await governance.setContractGuard(polygonChainData.sushi.router, uniswapV2RouterGuard.address);
    await governance.setContractGuard(polygonChainData.sushi.minichef, sushiMiniChefV2Guard.address);
    await governance.setContractGuard(polygonChainData.aaveV2.lendingPool, aaveLendingPoolGuardV2.address);
    await governance.setContractGuard(polygonChainData.aaveV3.lendingPool, aaveLendingPoolGuardV3.address);
    await governance.setContractGuard(
      polygonChainData.aaveV3.incentivesController,
      aaveIncentivesControllerGuard.address,
    );
    await governance.setContractGuard(polygonChainData.balancer.v2Vault, balancerV2Guard.address);
    await governance.setContractGuard(polygonChainData.balancer.merkleOrchard, balancerMerkleOrchardGuard.address);
    await governance.setContractGuard(polygonChainData.oneinch.v5Router, oneInchV5Guard.address);
    await governance.setContractGuard(dhedgeEasySwapper.address, easySwapperGuard.address);
    await governance.setContractGuard(polygonChainData.uniswapV3.router, uniswapV3RouterGuard.address);
    await governance.setContractGuard(
      polygonChainData.uniswapV3.nonfungiblePositionManager,
      uniswapV3NonfungiblePositionGuard.address,
    );
    await governance.setContractGuard(
      polygonChainData.balancer.gaugePools.stMATIC.gauge,
      balancerV2GaugeContractGuard.address,
    );

    await governance.setAddresses([
      { name: toBytes32("swapRouter"), destination: swapRouter.address },
      { name: toBytes32("aaveProtocolDataProviderV2"), destination: polygonChainData.aaveV2.protocolDataProvider },
      { name: toBytes32("aaveProtocolDataProviderV3"), destination: polygonChainData.aaveV3.protocolDataProvider },
      { name: toBytes32("weth"), destination: polygonChainData.assets.weth },
      { name: toBytes32("openAssetGuard"), destination: openAssetGuard.address },
    ]);

    const WMATIC = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.assets.wmatic,
      )
    );
    const USDT = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", polygonChainData.assets.usdt)
    );
    const DAI = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", polygonChainData.assets.dai)
    );
    const USDC = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", polygonChainData.assets.usdc)
    );
    const WETH = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", polygonChainData.assets.weth)
    );
    const SUSHI = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", polygonChainData.assets.sushi)
    );
    const BALANCER = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.assets.balancer,
      )
    );
    const QUICK = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", polygonChainData.assets.quick)
    );

    const SushiLPUSDCWETH = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.sushi.pools.usdc_weth.address,
      )
    );
    const QuickLPUSDCWETH = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.quickswap.pools.usdc_weth.address,
      )
    );

    const AMUSDC = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.aaveV2.aTokens.usdc,
      )
    );
    const AMWETH = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.aaveV2.aTokens.weth,
      )
    );

    const VariableWETH = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.aaveV2.variableDebtTokens.weth,
      )
    );
    const VariableUSDT = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.aaveV2.variableDebtTokens.usdt,
      )
    );
    const VariableDAI = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.aaveV2.variableDebtTokens.dai,
      )
    );

    const BALANCERLP_STABLE = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.balancer.stablePools.BPSP,
      )
    );
    const BALANCERLP_WETH_BALANCER = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        polygonChainData.balancer.pools.bal80weth20,
      )
    );

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
      slippageAccumulator,
      sushiMiniChefV2Guard,
      dhedgeEasySwapper,
      uniV3AssetGuard,
      uniswapV2RouterGuard,
      uniswapV3RouterGuard,
      balancerV2Guard,
      oneInchV5Guard,
      dhedgeNftTrackerStorage,
      erc721ContractGuard,
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
