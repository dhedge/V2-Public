import { ovmChainData } from "../../../config/chainData/ovmData";
import { IVersions } from "../../../deployment/types";
import { units } from "../../testHelpers";
import { DhedgeEasySwapperTests, EasySwapperTestCase } from "../common/DhedgeEasySwapperTest";

const { assets, assetsBalanceOfSlot, torosPools } = ovmChainData;

// eslint-disable-next-line @typescript-eslint/no-var-requires
const versions: IVersions = require("../../../publish/ovm/prod/versions.json");
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
const emptyNeverFundedPool = "0x6fe56ebe710017f51912b24a6df975890aceef27";
const testCases: EasySwapperTestCase[] = [
  {
    testName: "dSNX",
    dhedgePoolAddress: "0x59babc14dd73761e38e5bda171b2298dc14da92d",
    userDepositToken: assets.usdc,
    depositAmount: units(100, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.susd,
    nativeAssetDepositAmount: units(1).div(100),
  },
  {
    testName: "USDY",
    dhedgePoolAddress: torosPools.USDY,
    userDepositToken: assets.usdc,
    depositAmount: units(100, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(1).div(100),
  },
  {
    testName: "OVM Test",
    dhedgePoolAddress: "0xf36f550907872faaa02477f791df3ce33fe38854",
    userDepositToken: assets.usdc,
    depositAmount: units(4, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(1).div(1000),
  },
  /* BULL */
  {
    testName: "ETHBULL2X - can deposit and withdraw - no swap in, swap out to usdc",
    dhedgePoolAddress: torosPools.ETHBULL2X,
    userDepositToken: assets.weth,
    depositAmount: units(10), // 10 ETH - does not matter how many, directly deposited into aave
    userDepositTokenSlot: assetsBalanceOfSlot.weth,
    poolDepositToken: assets.weth,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "ETHBULL2X - can deposit and withdraw - no swap in, no swap out",
    dhedgePoolAddress: torosPools.ETHBULL2X,
    userDepositToken: assets.weth,
    depositAmount: units(10), // 10 ETH - does not matter how many, directly deposited into aave
    userDepositTokenSlot: assetsBalanceOfSlot.weth,
    poolDepositToken: assets.weth,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "ETHBULL2X - can deposit and withdraw - swap in, swap out to usdc",
    dhedgePoolAddress: torosPools.ETHBULL2X,
    userDepositToken: assets.usdc,
    depositAmount: units(100_000, 6), // can deposit with low slippage even 100k$ USDC
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.weth,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "ETHBULL2X - can deposit and withdraw - swap in, no swap out",
    dhedgePoolAddress: torosPools.ETHBULL2X,
    userDepositToken: assets.usdc,
    depositAmount: units(100_000, 6), // can deposit with low slippage even 100k$ USDC
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.weth,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "BTCBULL2X - can deposit and withdraw - no swap in, swap out to usdc",
    dhedgePoolAddress: torosPools.BTCBULL2X,
    userDepositToken: assets.wbtc,
    depositAmount: units(2, 8), // 2 WBTC - does not matter how many, directly deposited into aave
    userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "BTCBULL2X - can deposit and withdraw - no swap in, swap out to wbtc",
    dhedgePoolAddress: torosPools.BTCBULL2X,
    userDepositToken: assets.wbtc,
    depositAmount: units(2, 8), // 2 WBTC - does not matter how many, directly deposited into aave
    userDepositTokenSlot: assetsBalanceOfSlot.wbtc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "BTCBULL2X - can deposit and withdraw - swap in, swap out to usdc",
    dhedgePoolAddress: torosPools.BTCBULL2X,
    userDepositToken: assets.usdc,
    depositAmount: units(1_000, 6), // 1.000 USDC
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "BTCBULL2X - can deposit and withdraw - swap in, swap out to wbtc",
    dhedgePoolAddress: torosPools.BTCBULL2X,
    userDepositToken: assets.usdc,
    depositAmount: units(1_000, 6), // 1.000 USDC
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.wbtc,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(2),
  },
  /* BEAR */
  {
    testName: "ETHBEAR1X - can deposit and withdraw - no swap in, no swap out",
    dhedgePoolAddress: torosPools.ETHBEAR1X,
    userDepositToken: assets.usdc,
    depositAmount: units(16_000, 6), // 16.000 USDC
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.weth,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "ETHBEAR1X - can deposit and withdraw - no swap in, swap out to usdc",
    dhedgePoolAddress: torosPools.ETHBEAR1X,
    userDepositToken: assets.usdc,
    depositAmount: units(16_000, 6), // 16.000 USDC
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "BTCBEAR1X - can deposit and withdraw - no swap in, swap out to wbtc",
    dhedgePoolAddress: torosPools.BTCBEAR1X,
    userDepositToken: assets.usdc,
    depositAmount: units(16_000, 6), // 16.000 USDC
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.wbtc,
    nativeAssetDepositAmount: units(2),
  },
  {
    testName: "BTCBEAR1X - can deposit and withdraw - no swap in, swap out to usdc",
    dhedgePoolAddress: torosPools.BTCBEAR1X,
    userDepositToken: assets.usdc,
    depositAmount: units(16_000, 6), // 16.000 USDC
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(2),
  },
];

DhedgeEasySwapperTests(
  poolFactoryProxy,
  testCases[0].dhedgePoolAddress,
  testCases,
  [], // Withdraw sUSD
  ovmChainData,
  ovmChainData.assets.weth,
  emptyNeverFundedPool,
);
