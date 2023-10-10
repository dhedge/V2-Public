import { polygonChainData } from "../../../config/chainData/polygonData";
import { IVersions } from "../../../deployment/types";
import { units } from "../../testHelpers";
import {
  DhedgeEasySwapperTests,
  EasySwapperTestCase,
  EasySwapperNativeTestCase,
} from "../common/DhedgeEasySwapperTest";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const versions: IVersions = require("../../../publish/polygon/prod/versions.json");
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;

const { assets, assetsBalanceOfSlot, torosPools } = polygonChainData;

const jakesBroadFund = "0x53cd6399ad01403cfa86aaed77a7553810459bf3"; // deposit usdc
const emptyNeverFundedPool = "0x293d65ae529de876b942517c93682ef74c5ba507";
const testCases: (EasySwapperTestCase & EasySwapperNativeTestCase)[] = [
  {
    testName: "USD Market Neutral Yield - can deposit and withdraw",
    dhedgePoolAddress: "0xc4c6333afdd510066786e0d257eb91095fd729e3",
    userDepositToken: assets.usdc,
    depositAmount: units(100, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(200),
  },
  {
    testName: "ETHBEAR2X - can deposit and withdraw - no swap on in or out",
    dhedgePoolAddress: torosPools.ETHBEAR2X,
    userDepositToken: assets.usdc,
    depositAmount: units(200, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(200),
  },
  {
    testName: "ETHBEAR2X - can deposit and withdraw - swap in, swap out",
    dhedgePoolAddress: torosPools.ETHBEAR2X,
    userDepositToken: assets.weth,
    depositAmount: units(1),
    userDepositTokenSlot: assetsBalanceOfSlot.weth,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(2000),
  },
  {
    testName: "ETHBULL3X - can deposit and withdraw - no swap on the way in, swap out",
    dhedgePoolAddress: torosPools.ETHBULL3X,
    userDepositToken: assets.weth,
    depositAmount: units(3),
    userDepositTokenSlot: assetsBalanceOfSlot.weth,
    poolDepositToken: assets.weth,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(6000),
  },
  {
    testName: "ETHBULL3X - can deposit and withdraw - swap in, swap out",
    dhedgePoolAddress: torosPools.ETHBULL3X,
    userDepositToken: assets.usdc,
    depositAmount: units(1, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.weth,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(1),
  },
  {
    testName: "BTCBEAR2X - can deposit and withdraw - no swap on the way in, swap on way out",
    dhedgePoolAddress: torosPools.BTCBEAR2X,
    userDepositToken: assets.usdc,
    depositAmount: units(20000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(2000),
  },
  {
    testName: "BTCBEAR2X - can deposit and withdraw - swap in, swap out",
    dhedgePoolAddress: torosPools.BTCBEAR2X,
    userDepositToken: assets.weth,
    depositAmount: units(1),
    userDepositTokenSlot: assetsBalanceOfSlot.weth,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(2000),
  },
  {
    testName: "BTCBULL3X - can deposit and withdraw - no swap on the way in, swap out",
    dhedgePoolAddress: torosPools.BTCBULL3X,
    userDepositToken: assets.wbtc,
    depositAmount: units(1, 7), // 0.1 btc (I think)
    userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(200),
  },
  {
    testName: "BTCBULL3X - can deposit and withdraw - swap in, swap out",
    dhedgePoolAddress: torosPools.BTCBULL3X,
    userDepositToken: assets.usdc,
    depositAmount: units(100, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(100),
  },
  {
    testName: "BTCBULL3X - can deposit and withdraw - swap in, swap out to btc",
    dhedgePoolAddress: torosPools.BTCBULL3X,
    userDepositToken: assets.usdc,
    depositAmount: units(100, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(100),
  },
  {
    testName: "JAKES BROAD FUND - can deposit and withdraw - no swap in - but big swaps out",
    dhedgePoolAddress: jakesBroadFund,
    userDepositToken: assets.usdc,
    depositAmount: units(6, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(6),
  },
  {
    testName: "dUSD- can deposit and withdraw - no swap in - but big swaps out",
    dhedgePoolAddress: assets.dusd,
    userDepositToken: assets.usdc,
    depositAmount: units(10000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(1000),
  },
];

DhedgeEasySwapperTests(
  poolFactoryProxy,
  testCases[0].dhedgePoolAddress,
  [],
  [],
  testCases,
  polygonChainData,
  assets.wmatic,
  emptyNeverFundedPool,
);
