import { ovmChainData as chainData } from "../../../config/chainData/ovmData";
import { testStargateLpContractGuard } from "../common/stargate/StargateLpContractGuardTest";
import { testStargateLpAssetGuard } from "../common/stargate/StargateLpAssetGuardTest";
import { units } from "../../testHelpers";

const { assets, assetsBalanceOfSlot } = chainData;

testStargateLpAssetGuard([
  {
    network: "ovm",
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

testStargateLpContractGuard([
  {
    network: "ovm",
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
