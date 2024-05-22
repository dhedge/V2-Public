import { baseChainData } from "../../../config/chainData/baseData";
import { IVersions } from "../../../deployment/types";
import { units } from "../../testHelpers";
import { DhedgeEasySwapperTests, EasySwapperTestCase } from "../common/DhedgeEasySwapperTest";
import versionsUntyped from "../../../publish/base/prod/versions.json";

const versions = versionsUntyped as unknown as IVersions;
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
const emptyNeverFundedPool = "0x7085b9a7b461758e5905ddd5cea44963c9474421"; // https://dhedge.org/vault/0x7085b9a7b461758e5905ddd5cea44963c9474421
const testCases: EasySwapperTestCase[] = [
  {
    testName: "Aerodrome WETH/USDC LP",
    dhedgePoolAddress: "0xcc4d4e673046e843c0e41ed150ad7a4be95b62ea", // https://dhedge.org/vault/0xcc4d4e673046e843c0e41ed150ad7a4be95b62ea
    userDepositToken: baseChainData.assets.usdc,
    depositAmount: units(10, 6),
    userDepositTokenSlot: baseChainData.assetsBalanceOfSlot.usdc,
    poolDepositToken: baseChainData.assets.usdc,
    withdrawToken: baseChainData.assets.usdc,
    nativeAssetDepositAmount: units(1).div(1000),
  },
  {
    testName: "USDmny",
    dhedgePoolAddress: baseChainData.torosPools.USDMNY,
    userDepositToken: baseChainData.assets.usdc,
    depositAmount: units(100_000, 6),
    userDepositTokenSlot: baseChainData.assetsBalanceOfSlot.usdc,
    poolDepositToken: baseChainData.assets.usdc,
    withdrawToken: baseChainData.assets.usdc,
    nativeAssetDepositAmount: units(10),
  },
];

DhedgeEasySwapperTests(
  poolFactoryProxy,
  testCases[0].dhedgePoolAddress,
  testCases,
  [], // Withdraw sUSD
  {
    ...baseChainData,
    velodromeV2: { router: baseChainData.aerodrome.router, factory: baseChainData.aerodrome.factory },
  },
  baseChainData.assets.weth,
  emptyNeverFundedPool,
);
