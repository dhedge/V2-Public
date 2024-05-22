import { baseChainData } from "../../../../config/chainData/baseData";
import { launchSynthetixV3Tests } from "../../common/synthetixV3/SynthetixV3Test";
import { units } from "../../../testHelpers";

launchSynthetixV3Tests({
  assets: { ...baseChainData.assets },
  usdPriceFeeds: baseChainData.usdPriceFeeds,
  systemAssets: {
    collateral: {
      address: baseChainData.assets.susdc,
      usdPriceFeed: baseChainData.usdPriceFeeds.usdc,
      balanceOfSlot: 3, // Not sure how to know it on unverified contract
      proxyTargetTokenState: baseChainData.assets.susdc, // Not sure how to know it on unverified contract
      ownerBalanceTotal: units(300), // minimum delegation amount is 100
      balanceToThePool: units(200),
    },
    debt: {
      address: baseChainData.assets.snxUSD,
      usdPriceFeed: baseChainData.usdPriceFeeds.usdc,
    },
    tokenToCollateral: {
      address: baseChainData.assets.usdc,
      usdPriceFeed: baseChainData.usdPriceFeeds.usdc,
      decimals: 6,
    },
    extraRewardTokens: [
      {
        address: baseChainData.assets.snx,
        usdPriceFeed: baseChainData.usdPriceFeeds.snx,
      },
    ],
  },
  allowedLiquidityPoolId: 1,
  synthetixV3Core: baseChainData.synthetixV3.core,
  synthetixAccountNFT: baseChainData.synthetixV3.accountNFT,
  synthetixV3SpotMarket: baseChainData.synthetixV3.spotMarket,
  allowedMarketIds: [
    { marketId: 1, collateralSynth: baseChainData.assets.susdc, collateralAsset: baseChainData.assets.usdc },
  ],
  collateralSource: "transferFrom",
  transferCollateralFrom: "0x25ca6760fc0936127a6e34c3cbd63064b8a0de1f", // should be an account which holds sUSDC
  mintingPositiveDebtForbidden: true,
  deployedNodeModule: "0x67a5a7785D0ebd65e44eaB4FeC55ca81c80c95b1",
  rewardDistributors: ["0x45063DCd92f56138686810eacB1B510C941d6593", "0xe92bcD40849BE5a5eb90065402e508aF4b28263b"], // Spartan Council Pool SNX Rewards, Spartan Council Pool USDC Rewards
});
