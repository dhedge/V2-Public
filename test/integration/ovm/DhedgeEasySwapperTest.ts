import { ovmChainData } from "../../../config/chainData/ovmData";
import { IVersions } from "../../../deployment/types";
import { units } from "../../testHelpers";
import { DhedgeEasySwapperTests, EasySwapperTestCase } from "../common/DhedgeEasySwapperTest";
import versionsUntyped from "../../../publish/ovm/prod/versions.json";

const { assets, assetsBalanceOfSlot, torosPools } = ovmChainData;

const versions = versionsUntyped as unknown as IVersions;
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
const emptyNeverFundedPool = "0x6fe56ebe710017f51912b24a6df975890aceef27";
const testCases: EasySwapperTestCase[] = [
  {
    testName: "OVM Test",
    dhedgePoolAddress: "0xf36f550907872faaa02477f791df3ce33fe38854",
    userDepositToken: assets.usdc,
    depositAmount: units(4, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "dSNX",
    dhedgePoolAddress: "0x59babc14dd73761e38e5bda171b2298dc14da92d",
    userDepositToken: assets.usdcNative,
    depositAmount: units(100, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.susd,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "USDY",
    dhedgePoolAddress: torosPools.USDY,
    userDepositToken: assets.usdcNative,
    depositAmount: units(100, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.usdcNative,
    nativeAssetDepositAmount: units(10),
  },
  /* BULL */
  {
    testName: "ETHBULL2X - can deposit and withdraw - no swap in, no swap out",
    dhedgePoolAddress: torosPools.ETHBULL2X,
    userDepositToken: assets.weth,
    depositAmount: units(10),
    userDepositTokenSlot: assetsBalanceOfSlot.weth,
    poolDepositToken: assets.weth,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "ETHBULL3X - can deposit and withdraw - no swap in, no swap out",
    dhedgePoolAddress: torosPools.ETHBULL3X,
    userDepositToken: assets.weth,
    depositAmount: units(10),
    userDepositTokenSlot: assetsBalanceOfSlot.weth,
    poolDepositToken: assets.weth,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "BTCBULL2X - can deposit and withdraw - no swap in, swap out to wbtc",
    dhedgePoolAddress: torosPools.BTCBULL2X,
    userDepositToken: assets.wbtc,
    depositAmount: units(1, 7),
    userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "BTCBULL2X - can deposit and withdraw - no swap in, no swap out",
    dhedgePoolAddress: torosPools.BTCBULL2X,
    userDepositToken: assets.wbtc,
    depositAmount: units(1, 7),
    userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "BTCBULL3X - can deposit and withdraw - no swap in, swap out to wbtc",
    dhedgePoolAddress: torosPools.BTCBULL3X,
    userDepositToken: assets.wbtc,
    depositAmount: units(1, 7),
    userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "BTCBULL3X - can deposit and withdraw - no swap in, no swap out",
    dhedgePoolAddress: torosPools.BTCBULL3X,
    userDepositToken: assets.wbtc,
    depositAmount: units(1, 7),
    userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(10),
  },
  /* BEAR */
  {
    testName: "ETHBEAR1X - can deposit and withdraw - no swap in, swap out to usdc",
    dhedgePoolAddress: torosPools.ETHBEAR1X,
    userDepositToken: assets.usdcNative,
    depositAmount: units(20_000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.usdcNative,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "ETHBEAR1X - can deposit and withdraw - no swap in, no swap out",
    dhedgePoolAddress: torosPools.ETHBEAR1X,
    userDepositToken: assets.usdcNative,
    depositAmount: units(20_000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "BTCBEAR1X - can deposit and withdraw - no swap in, swap out to usdc",
    dhedgePoolAddress: torosPools.BTCBEAR1X,
    userDepositToken: assets.usdcNative,
    depositAmount: units(20_000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.usdcNative,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "BTCBEAR1X - can deposit and withdraw - no swap in, swap out to wbtc",
    dhedgePoolAddress: torosPools.BTCBEAR1X,
    userDepositToken: assets.usdcNative,
    depositAmount: units(20_000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "BTCBEAR1X - can deposit and withdraw - no swap in, no swap out",
    dhedgePoolAddress: torosPools.BTCBEAR1X,
    userDepositToken: assets.usdcNative,
    depositAmount: units(20_000, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(10),
  },
];

DhedgeEasySwapperTests(
  poolFactoryProxy,
  testCases[0].dhedgePoolAddress, // Must accept USDC (bridged)
  testCases,
  [testCases[1]], // Withdraw sUSD - dSNX
  ovmChainData,
  ovmChainData.assets.weth,
  emptyNeverFundedPool,
);
