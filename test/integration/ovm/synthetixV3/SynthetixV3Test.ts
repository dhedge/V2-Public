import { launchSynthetixV3Tests } from "../../common/synthetixV3/SynthetixV3Test";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { units } from "../../../testHelpers";

launchSynthetixV3Tests({
  assets: ovmChainData.assets,
  usdPriceFeeds: ovmChainData.usdPriceFeeds,
  systemAssets: {
    collateral: {
      address: ovmChainData.assets.snxProxy,
      usdPriceFeed: ovmChainData.usdPriceFeeds.snx,
      balanceOfSlot: ovmChainData.assetsBalanceOfSlot.snx,
      proxyTargetTokenState: ovmChainData.synthetix.SNXProxy_target_tokenState,
      ownerBalanceTotal: units(50_000),
      balanceToThePool: units(25_000),
    },
    debt: {
      address: ovmChainData.assets.snxUSD,
      usdPriceFeed: ovmChainData.usdPriceFeeds.susd, // Using sUSD price feed for snxUSD
    },
  },
  allowedLiquidityPoolId: 1,
  synthetixV3Core: ovmChainData.synthetix.v3Core,
  synthetixAccountNFT: ovmChainData.synthetix.accountNFT,
  synthetixV3SpotMarket: ovmChainData.synthetix.v3SpotMarket,
  allowedMarketIds: [],
  collateralSource: "setBalance",
  mintingPositiveDebtForbidden: false,
});
