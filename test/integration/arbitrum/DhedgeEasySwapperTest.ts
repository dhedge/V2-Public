import { arbitrumChainData } from "../../../config/chainData/arbitrumData";
import { IVersions } from "../../../deployment/types";
import { units } from "../../testHelpers";
import { DhedgeEasySwapperTests, EasySwapperTestCase } from "../common/DhedgeEasySwapperTest";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const versions: IVersions = require("../../../publish/arbitrum/prod/versions.json");
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
const emptyNeverFundedPool = "0xd5aa51d85a31b041f7c40292546a66ded9249156";
const testCases: EasySwapperTestCase[] = [
  {
    testName: "Ramses USDC/swETH LP",
    dhedgePoolAddress: "0xf7d41e7fc42225f42139732cdc5c5b0453ac3a53", // https://dh-dev.vercel.app/vault/0xf7d41e7fc42225f42139732cdc5c5b0453ac3a53
    userDepositToken: arbitrumChainData.assets.usdcnative,
    depositAmount: units(4, 6),
    userDepositTokenSlot: arbitrumChainData.assetsBalanceOfSlot.usdcnative,
    poolDepositToken: arbitrumChainData.assets.usdcnative,
    withdrawToken: arbitrumChainData.assets.usdcnative,
    nativeAssetDepositAmount: units(1).div(1000),
  },
];

DhedgeEasySwapperTests(
  poolFactoryProxy,
  testCases[0].dhedgePoolAddress,
  testCases,
  [], // Withdraw sUSD
  {
    ...arbitrumChainData,
    assets: { ...arbitrumChainData.assets, usdc: arbitrumChainData.assets.usdcnative },
    assetsBalanceOfSlot: {
      ...arbitrumChainData.assetsBalanceOfSlot,
      usdc: arbitrumChainData.assetsBalanceOfSlot.usdcnative,
    },
  },
  arbitrumChainData.assets.weth,
  emptyNeverFundedPool,
);
