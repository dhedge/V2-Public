import { ovmChainData } from "../../../../config/chainData/ovmData";
import { CreateSynthetixFuturesMarketAssetGuardWithdrawProcessingTests } from "../synthetixFuturesPerps/SynthetixFuturesMarketAssetGuardWithdrawProcessingTest";
import { perpsV2TestHelpers } from "../synthetixPerpsV2/SynthetixPerpsV2TestHelpers";

CreateSynthetixFuturesMarketAssetGuardWithdrawProcessingTests(perpsV2TestHelpers, {
  ethMarket: ovmChainData.futures.ethMarket,
});
