import { ovmChainData } from "../../../config/chainData/ovm-data";
import { IVersions } from "../../../deployment-scripts/types";
import { units } from "../../TestHelpers";
import {
  DhedgeEasySwapperTests,
  EasySwapperNativeTestCase,
  EasySwapperTestCase,
} from "../common/DhedgeEasySwapperTest";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const versions: IVersions = require("../../../publish/ovm/prod/versions.json");
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
const emptyNeverFundedPool = "0x6fe56ebe710017f51912b24a6df975890aceef27";
const testCases: (EasySwapperTestCase & EasySwapperNativeTestCase)[] = [
  {
    testName: "dSNX",
    dhedgePoolAddress: "0x59babc14dd73761e38e5bda171b2298dc14da92d",
    userDepositToken: ovmChainData.assets.usdc,
    depositAmount: units(10, 6),
    userDepositTokenSlot: ovmChainData.assetsBalanceOfSlot.usdc,
    poolDepositToken: ovmChainData.assets.usdc,
    withdrawToken: ovmChainData.assets.weth,
    nativeAssetDepositAmount: units(1).div(100),
  },
  {
    testName: "Ethereum Long Volatility",
    dhedgePoolAddress: "0x44ca2d499e6254dfdc17fdef8c23e7283e7c24e4",
    userDepositToken: ovmChainData.assets.usdc,
    depositAmount: units(100, 6),
    userDepositTokenSlot: ovmChainData.assetsBalanceOfSlot.usdc,
    poolDepositToken: ovmChainData.assets.susd,
    withdrawToken: ovmChainData.assets.susd,
    nativeAssetDepositAmount: units(1).div(10),
  },
  {
    testName: "Pure Boomer Alpha 0/10 fees by Bogg Dann",
    dhedgePoolAddress: "0x189a36c62c1ce9d9fd7a543df0a6dbe3a73a2c14",
    userDepositToken: ovmChainData.assets.usdc,
    depositAmount: units(1000, 6),
    userDepositTokenSlot: ovmChainData.assetsBalanceOfSlot.usdc,
    poolDepositToken: ovmChainData.assets.usdc,
    withdrawToken: ovmChainData.assets.usdc,
    nativeAssetDepositAmount: units(1).div(2),
  },
  {
    testName: "Alpha+Omega Fund (AOF2) Optimism",
    dhedgePoolAddress: "0x8c2d5f3c8602ae767e78d818edb1266961602b2c",
    userDepositToken: ovmChainData.assets.usdc,
    depositAmount: units(100, 6),
    userDepositTokenSlot: ovmChainData.assetsBalanceOfSlot.usdc,
    poolDepositToken: ovmChainData.assets.usdc,
    withdrawToken: ovmChainData.assets.dai,
    nativeAssetDepositAmount: units(1).div(10),
  },
  {
    testName: "OVM Test",
    dhedgePoolAddress: "0xf36f550907872faaa02477f791df3ce33fe38854",
    userDepositToken: ovmChainData.assets.usdc,
    depositAmount: units(4, 6),
    userDepositTokenSlot: ovmChainData.assetsBalanceOfSlot.usdc,
    poolDepositToken: ovmChainData.assets.usdc,
    withdrawToken: ovmChainData.assets.usdc,
    nativeAssetDepositAmount: units(1).div(1000),
  },
];

DhedgeEasySwapperTests(
  poolFactoryProxy,
  testCases[0].dhedgePoolAddress,
  testCases, // Withdraw
  [testCases[0]], // withdrawSUSD
  testCases, //withdrawNative
  ovmChainData,
  ovmChainData.assets.weth,
  emptyNeverFundedPool,
);
