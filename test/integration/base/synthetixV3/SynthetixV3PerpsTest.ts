import { baseChainData } from "../../../../config/chainData/baseData";
import { launchSynthetixV3PerpsTests } from "../../common/synthetixV3/SynthetixV3PerpsTest";
import { units } from "../../../testHelpers";

launchSynthetixV3PerpsTests({
  assets: baseChainData.assets,
  usdPriceFeeds: baseChainData.usdPriceFeeds,
  systemAssets: {
    collateral: {
      address: baseChainData.assets.susdc,
      usdPriceFeed: baseChainData.usdPriceFeeds.usdc,
      balanceOfSlot: 3, // Not sure how to know it on unverified contract
      proxyTargetTokenState: baseChainData.assets.susdc, // Not sure how to know it on unverified contract
      ownerBalanceTotal: units(200), // minimum delegation amount is 100
      balanceToThePool: units(200),
      decimals: 18,
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
    withdrawalAsset: {
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
  synthetixPerpsAccountNFT: baseChainData.synthetixV3.perpsAccountNFT,
  synthetixV3SpotMarket: baseChainData.synthetixV3.spotMarket,
  synthetixV3PerpsMarket: baseChainData.synthetixV3.perpsMarket,
  allowedMarketIds: [
    {
      marketId: 1,
      collateralSynth: baseChainData.assets.susdc,
      collateralAsset: baseChainData.assets.usdc,
      atomicSwapSettings: {
        isAtomicSwapAllowed: true,
        isOneToOneSwap: true,
      },
    },
  ],
  collateralSource: "transferFrom",
  transferCollateralFrom: "0x25ca6760fc0936127a6e34c3cbd63064b8a0de1f", // should be an account which holds sUSDC
  mintingPositiveDebtForbidden: true,
  deployedNodeModule: "0x4903E09E84259e5105190AaA33e714E1Eaf0bAcD",
  rewardDistributors: ["0x45063DCd92f56138686810eacB1B510C941d6593", "0xe92bcD40849BE5a5eb90065402e508aF4b28263b"], // Spartan Council Pool SNX Rewards, Spartan Council Pool USDC Rewards
  synthMarketId: 0, // snxUSD as margin
  perpMarketId: 100, // Perps Market ETH
  asyncSettlementModule: "0x4e3665bd00eccf0e6d781045fb7a8c4b88fbc84f",
  pyth: {
    priceFeedId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace", //ETH
    contract: "0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a",
  },
});
