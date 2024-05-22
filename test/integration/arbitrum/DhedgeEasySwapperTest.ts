import { arbitrumChainData } from "../../../config/chainData/arbitrumData";
import { IVersions } from "../../../deployment/types";
import { units } from "../../testHelpers";
import { DhedgeEasySwapperTests, EasySwapperTestCase } from "../common/DhedgeEasySwapperTest";
import versionsUntyped from "../../../publish/arbitrum/prod/versions.json";

const { assets, assetsBalanceOfSlot, torosPools } = arbitrumChainData;

const versions = versionsUntyped as unknown as IVersions;
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];

const poolFactoryProxy = versions[latestVersion].contracts.PoolFactoryProxy;
const emptyNeverFundedPool = "0xd5aa51d85a31b041f7c40292546a66ded9249156"; // https://dh-dev.vercel.app/vault/0xd5aa51d85a31b041f7c40292546a66ded9249156
const testCases: EasySwapperTestCase[] = [
  {
    testName: "Arbitrum Test",
    dhedgePoolAddress: "0x99875d806706888bd525fe123ea1a9982b70b0e2",
    userDepositToken: assets.usdc,
    depositAmount: units(4, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdc,
    poolDepositToken: assets.usdc,
    withdrawToken: assets.usdc,
    nativeAssetDepositAmount: units(10),
  },
  {
    testName: "Ramses USDC/swETH LP",
    dhedgePoolAddress: "0xf7d41e7fc42225f42139732cdc5c5b0453ac3a53", // https://dh-dev.vercel.app/vault/0xf7d41e7fc42225f42139732cdc5c5b0453ac3a53
    userDepositToken: assets.usdcNative,
    depositAmount: units(4, 6),
    userDepositTokenSlot: assetsBalanceOfSlot.usdcNative,
    poolDepositToken: assets.usdcNative,
    withdrawToken: assets.usdcNative,
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
];

DhedgeEasySwapperTests(
  poolFactoryProxy,
  testCases[0].dhedgePoolAddress, // Must accept USDC (bridged)
  testCases,
  [], // Withdraw sUSD
  arbitrumChainData,
  arbitrumChainData.assets.weth,
  emptyNeverFundedPool,
);
