import { ovmChainData } from "../../../../config/chainData/ovmData";
import { CreateSynthetixFuturesMarketAssetGuardPricingTests } from "../synthetixFuturesPerps/SynthetixFuturesMarketAssetGuardPricingTest";
import { perpsV2TestHelpers } from "./SynthetixPerpsV2TestHelpers";

CreateSynthetixFuturesMarketAssetGuardPricingTests(perpsV2TestHelpers, { ethMarket: ovmChainData.perpsV2.ethMarket });
