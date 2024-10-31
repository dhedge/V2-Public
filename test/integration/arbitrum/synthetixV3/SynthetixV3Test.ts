import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { launchSynthetixV3Tests } from "../../common/synthetixV3/SynthetixV3Test";
import { units } from "../../../testHelpers";

export const deployedNodeModule = "0x4dc9F78DE4B786e4F07d0DFe6981f014f9c8778E";

const collateralAssets = [
  {
    collateral: {
      address: arbitrumChainData.assets.usdcNative,
      usdPriceFeed: arbitrumChainData.usdPriceFeeds.usdc,
      balanceOfSlot: arbitrumChainData.assetsBalanceOfSlot.usdcNative,
      proxyTargetTokenState: arbitrumChainData.assets.usdcNative,
      ownerBalanceTotal: units(300, 6),
      balanceToThePool: units(200, 6),
      decimals: 6,
    },
    rewardDistributors: ["0x8B6D6416017de3d1dCac4158Fe8a401C6B951fA8"], // Spartan Council Pool ARB Rewards for USDC LP
  },
  {
    collateral: {
      address: arbitrumChainData.assets.arb,
      usdPriceFeed: arbitrumChainData.usdPriceFeeds.arb,
      balanceOfSlot: arbitrumChainData.assetsBalanceOfSlot.arb,
      proxyTargetTokenState: arbitrumChainData.assets.arb,
      ownerBalanceTotal: units(300, 18),
      balanceToThePool: units(200, 18),
      decimals: 18,
    },
    rewardDistributors: ["0x9Ac841f5716FDe2AbD5e966695B8BBCC29d7CeE5"], // Spartan Council Pool ARB Rewards for ARB LP
  },
  {
    collateral: {
      address: arbitrumChainData.assets.wsteth,
      usdPriceFeed: "0x478D8f26013184D7eEE8184dCB757E741a3C7EC1", // published wsteth oracle
      balanceOfSlot: arbitrumChainData.assetsBalanceOfSlot.wsteth,
      proxyTargetTokenState: arbitrumChainData.assets.wsteth,
      ownerBalanceTotal: units(3, 18),
      balanceToThePool: units(2, 18),
      decimals: 18,
    },
    rewardDistributors: [], // Spartan Council Pool ARB Rewards for WETH LP
  },
];

collateralAssets.forEach(({ collateral, rewardDistributors }) =>
  launchSynthetixV3Tests({
    network: "arbitrum",
    assets: arbitrumChainData.assets,
    usdPriceFeeds: arbitrumChainData.usdPriceFeeds,
    systemAssets: {
      collateral,
      debt: {
        address: arbitrumChainData.assets.usdx,
        usdPriceFeed: "0x16fE67E412AC7732F18Eeb318e24651C85AFcF76", //published usd price aggregator feed
      },
      extraRewardTokens: [
        {
          address: arbitrumChainData.assets.arb,
          usdPriceFeed: arbitrumChainData.usdPriceFeeds.arb,
        },
      ],
    },
    allowedLiquidityPoolId: 1, // Spartan Council Pool
    synthetixV3Core: arbitrumChainData.synthetixV3.core,
    synthetixAccountNFT: arbitrumChainData.synthetixV3.accountNFT,
    synthetixV3SpotMarket: arbitrumChainData.synthetixV3.spotMarket,
    allowedMarketIds: [
      {
        marketId: 2,
        collateralSynth: arbitrumChainData.assets.susdc,
        collateralAsset: arbitrumChainData.assets.usdcNative,
        atomicSwapSettings: {
          isAtomicSwapAllowed: true,
          isOneToOneSwap: false,
        },
      },
      {
        marketId: 3,
        collateralSynth: arbitrumChainData.assets.stbtc,
        collateralAsset: arbitrumChainData.assets.tbtc,
        atomicSwapSettings: {
          isAtomicSwapAllowed: false,
          isOneToOneSwap: false,
        },
      },
      {
        marketId: 4,
        collateralSynth: arbitrumChainData.assets.seth,
        collateralAsset: arbitrumChainData.assets.weth,
        atomicSwapSettings: {
          isAtomicSwapAllowed: false,
          isOneToOneSwap: false,
        },
      },
      {
        marketId: 5,
        collateralSynth: arbitrumChainData.assets.susde,
        collateralAsset: arbitrumChainData.assets.usde,
        atomicSwapSettings: {
          isAtomicSwapAllowed: false,
          isOneToOneSwap: false,
        },
      },
      {
        marketId: 6,
        collateralSynth: arbitrumChainData.assets.swsol,
        collateralAsset: arbitrumChainData.assets.wsol,
        atomicSwapSettings: {
          isAtomicSwapAllowed: false,
          isOneToOneSwap: false,
        },
      },
    ],
    collateralSource: "setBalance",
    mintingPositiveDebtForbidden: false,
    deployedNodeModule,
    rewardDistributors,
  }),
);
