import { ovmChainData as chainData } from "../../../../config/chainData/ovmData";
import { testPoolTokenSwapperSwap } from "../../common/poolTokenSwapper/PoolTokenSwapperSwapTest";
import { units } from "../../../testHelpers";
import versionsUntyped from "../../../../publish/ovm/prod/versions.json";
import { IVersions } from "../../../../deployment/types";

const { assets, assetsBalanceOfSlot } = chainData;
const versions = versionsUntyped as unknown as IVersions;
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];
const poolFactory = versions[latestVersion].contracts.PoolFactoryProxy;

testPoolTokenSwapperSwap([
  {
    network: "ovm",
    chainData,
    poolFactory,
    swapFrom: {
      name: "USDC",
      type: "asset",
      address: assets.usdc,
      balanceOfSlot: assetsBalanceOfSlot.usdc,
      decimals: 6, // tests decimal conversions
    },
    swapTo: {
      name: "USDy",
      type: "pool",
      swapFee: 10, // 0.1%
      address: chainData.torosPools.USDY,
      balanceOfSlot: 0,
      decimals: 18,
    },
    swapAmount: units(100, 6),
  },
  {
    network: "ovm",
    chainData,
    poolFactory,
    swapFrom: {
      name: "USDy",
      type: "pool",
      swapFee: 20, // 0.2%
      address: chainData.torosPools.USDY,
      balanceOfSlot: 0,
      decimals: 18,
    },
    swapTo: {
      name: "USDC",
      type: "asset",
      address: assets.usdc,
      balanceOfSlot: assetsBalanceOfSlot.usdc,
      decimals: 6, // tests decimal conversions
    },
    swapAmount: units(1000, 18),
  },
  {
    network: "ovm",
    chainData,
    poolFactory,
    swapFrom: {
      name: "USDy",
      type: "pool",
      swapFee: 10, // 0.1%
      address: chainData.torosPools.USDY,
      balanceOfSlot: 0,
      decimals: 18,
    },
    swapTo: {
      name: "USDmny",
      type: "pool",
      swapFee: 30, // 0.3%
      address: chainData.torosPools.USDMNY,
      balanceOfSlot: 0,
      decimals: 18,
    },
    swapAmount: units(1000, 18),
  },
]);
