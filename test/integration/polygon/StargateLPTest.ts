import { polygonChainData as chainData } from "../../../config/chainData/polygonData";
import { testStargateLpContractGuard } from "../common/stargate/StargateLpContractGuardTest";
import { testStargateLpAssetGuard } from "../common/stargate/StargateLpAssetGuardTest";
import { units } from "../../testHelpers";

const { assets, assetsBalanceOfSlot } = chainData;

testStargateLpAssetGuard([
  {
    network: "polygon",
    chainData: chainData,
    asset: {
      lpAssetName: "susdc",
      address: assets.usdc,
      balanceOfSlot: assetsBalanceOfSlot.usdc,
    },
    depositAmount: units(10000, 6),
    testScope: "all",
  },
  {
    network: "polygon",
    chainData: chainData,
    asset: {
      lpAssetName: "sdai",
      address: assets.dai,
      balanceOfSlot: assetsBalanceOfSlot.dai,
    },
    depositAmount: units(10000, 18),
    testScope: "minimum",
  },
]);

testStargateLpContractGuard([
  {
    network: "polygon",
    chainData: chainData,
    asset: {
      lpAssetName: "sdai",
      address: assets.dai,
      balanceOfSlot: assetsBalanceOfSlot.dai,
    },
    depositAmount: units(10000, 18),
    testScope: "all",
  },
]);
