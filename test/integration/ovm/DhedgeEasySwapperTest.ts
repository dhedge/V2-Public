import { ovmChainData } from "../../../config/chainData/ovmData";
import { IVersions } from "../../../deployment/types";
import { units } from "../../testHelpers";
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
    depositAmount: units(100, 6),
    userDepositTokenSlot: ovmChainData.assetsBalanceOfSlot.usdc,
    poolDepositToken: ovmChainData.assets.usdc,
    withdrawToken: ovmChainData.assets.susd,
    nativeAssetDepositAmount: units(1).div(100),
  },
  {
    testName: "usdy",
    dhedgePoolAddress: ovmChainData.torosPools.USDY,
    userDepositToken: ovmChainData.assets.usdc,
    depositAmount: units(100, 6),
    userDepositTokenSlot: ovmChainData.assetsBalanceOfSlot.usdc,
    poolDepositToken: ovmChainData.assets.usdc,
    withdrawToken: ovmChainData.assets.weth,
    nativeAssetDepositAmount: units(1).div(100),
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
  testCases,
  ovmChainData,
  ovmChainData.assets.weth,
  emptyNeverFundedPool,
);
