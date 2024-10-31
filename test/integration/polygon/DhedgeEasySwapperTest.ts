import { polygonChainData } from "../../../config/chainData/polygonData";
import { IVersions } from "../../../deployment/types";
import { units } from "../../testHelpers";
import { DhedgeEasySwapperTests, EasySwapperTestCase } from "../common/DhedgeEasySwapperTest";
import versionsUntyped from "../../../publish/polygon/prod/versions.json";

const { assets, assetsBalanceOfSlot, torosPools } = polygonChainData;

const versions = versionsUntyped as unknown as IVersions;
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
const emptyNeverFundedPool = "0x293d65ae529de876b942517c93682ef74c5ba507";
const testCases: EasySwapperTestCase[] = [
  {
    testName: "JAKES BROAD FUND - can deposit and withdraw - no swap in - but big swaps out",
    dhedgePoolAddress: "0x53cd6399ad01403cfa86aaed77a7553810459bf3",
    userDepositToken: assets.usdc,
    depositAmount: units(6, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(8000),
  },
  /* BULL */
  {
    testName: "ETHBULL3X - can deposit and withdraw - no swap in, exit to weth",
    dhedgePoolAddress: torosPools.ETHBULL3X,
    userDepositToken: assets.weth,
    depositAmount: units(8),
    userDepositTokenSlot: assetsBalanceOfSlot.weth,
    poolDepositToken: assets.weth,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(8000),
  },
  {
    testName: "ETHBULL3X - can deposit and withdraw - no swap in, exit to usdc",
    dhedgePoolAddress: torosPools.ETHBULL3X,
    userDepositToken: assets.weth,
    depositAmount: units(8),
    userDepositTokenSlot: assetsBalanceOfSlot.weth,
    poolDepositToken: assets.weth,
    withdrawToken: assets.usdcNative,
    nativeAssetDepositAmount: units(8000),
  },
  {
    testName: "BTCBULL3X - can deposit and withdraw - no swap in, exit to wbtc",
    dhedgePoolAddress: torosPools.BTCBULL3X,
    userDepositToken: assets.wbtc,
    depositAmount: units(1, 7),
    userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(8000),
  },
  {
    testName: "BTCBULL3X - can deposit and withdraw - no swap in, exit to usdc",
    dhedgePoolAddress: torosPools.BTCBULL3X,
    userDepositToken: assets.wbtc,
    depositAmount: units(1, 7),
    userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.usdcNative,
    nativeAssetDepositAmount: units(8000),
  },
  /* BEAR */
  {
    testName: "ETHBEAR1X - can deposit and withdraw - no swap in, exit to weth",
    dhedgePoolAddress: torosPools.ETHBEAR1X,
    userDepositToken: assets.usdcNative,
    depositAmount: units(20_000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(8000),
  },
  {
    testName: "ETHBEAR1X - can deposit and withdraw - no swap in, exit to usdc",
    dhedgePoolAddress: torosPools.ETHBEAR1X,
    userDepositToken: assets.usdcNative,
    depositAmount: units(20_000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.usdcNative,
    nativeAssetDepositAmount: units(8000),
  },
  {
    testName: "BTCBEAR1X - can deposit and withdraw - no swap in, exit to wbtc",
    dhedgePoolAddress: torosPools.BTCBEAR1X,
    userDepositToken: assets.usdcNative,
    depositAmount: units(20_000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(8000),
  },
  {
    testName: "BTCBEAR1X - can deposit and withdraw - no swap in, exit to usdc",
    dhedgePoolAddress: torosPools.BTCBEAR1X,
    userDepositToken: assets.usdcNative,
    depositAmount: units(20_000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.usdcNative,
    nativeAssetDepositAmount: units(8000),
  },
];

DhedgeEasySwapperTests(
  poolFactoryProxy,
  testCases[0].dhedgePoolAddress, // Must accept USDC (bridged)
  testCases,
  [], // Withdraw sUSD
  polygonChainData,
  assets.wmatic,
  emptyNeverFundedPool,
);
