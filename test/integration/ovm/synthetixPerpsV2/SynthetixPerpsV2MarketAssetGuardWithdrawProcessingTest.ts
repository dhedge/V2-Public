import { CreateSynthetixFuturesMarketAssetGuardWithdrawProcessingTests } from "../synthetixFuturesPerps/SynthetixFuturesMarketAssetGuardWithdrawProcessingTest";
import { perpsV2TestHelpers } from "./SynthetixPerpsV2TestHelpers";
import { ovmChainData } from "../../../../config/chainData/ovmData";

CreateSynthetixFuturesMarketAssetGuardWithdrawProcessingTests(perpsV2TestHelpers, {
  ethMarket: ovmChainData.perpsV2.ethMarket,
});
