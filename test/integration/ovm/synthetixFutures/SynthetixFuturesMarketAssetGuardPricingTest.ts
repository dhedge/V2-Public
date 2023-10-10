import { ovmChainData } from "../../../../config/chainData/ovmData";
import { CreateSynthetixFuturesMarketAssetGuardPricingTests } from "../synthetixFuturesPerps/SynthetixFuturesMarketAssetGuardPricingTest";
import { perpsV2TestHelpers } from "../synthetixPerpsV2/SynthetixPerpsV2TestHelpers";

CreateSynthetixFuturesMarketAssetGuardPricingTests(perpsV2TestHelpers, { ethMarket: ovmChainData.futures.ethMarket });
