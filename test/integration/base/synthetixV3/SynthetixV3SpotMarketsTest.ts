import { ethers } from "ethers";
import { baseChainData } from "../../../../config/chainData/baseData";
import { units } from "../../../testHelpers";
import { launchSynthetixSpotMarketsV3Tests } from "../../common/synthetixV3/SynthetixV3SpotMarketsTest";
import { toBytes32 } from "../../utils/getAccountTokens";

const LIQUIDATION_REWARDS_DISTRIBUTOR = [
  {
    distributor: "0x7656bDEE9f4e7A507fd0C5b2431D3F3690E20711", // Perps cbBTC Liquidation Rewards Distributor
    rewardToken: "0xEDE1d04C864EeEC40393ED4cb454B85A5ABD071C",
    unwrapToAsset: baseChainData.assets.cbbtc,
    requiredMarketId: 4,
  },
  {
    distributor: "0x2F64ad511C33a78080b114c5ef51370B31488e65", // Perps sETH Liquidation Rewards Distributor
    rewardToken: "0xFA24Be208408F20395914Ba82Def333d987E0080",
    unwrapToAsset: baseChainData.assets.weth,
    requiredMarketId: 6,
  },
  {
    distributor: "0xE8183A61d64ea44a430bB361467063535B769052", // Perps swstETH Liquidation Rewards Distributor
    rewardToken: "0x3526D453D1Edb105E4e2b8448760fC501050d976",
    unwrapToAsset: baseChainData.assets.wsteth,
    requiredMarketId: 7,
  },
];

launchSynthetixSpotMarketsV3Tests({
  assets: baseChainData.assets,
  usdPriceFeeds: baseChainData.usdPriceFeeds,
  systemAssets: {
    collateral: {
      address: baseChainData.assets.susdc,
      usdPriceFeed: baseChainData.usdPriceFeeds.usdc,
      balanceOfSlot: toBytes32(
        ethers.BigNumber.from(
          ethers.utils.keccak256(
            ethers.utils.defaultAbiCoder.encode(["string"], ["io.synthetix.core-contracts.ERC20"]),
          ),
        ).add(3),
      ),

      proxyTargetTokenState: baseChainData.assets.susdc, // Not sure how to know it on unverified contract
      ownerBalanceTotal: units(300), // minimum delegation amount is 100
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
    {
      marketId: 1,
      collateralSynth: baseChainData.assets.susdc,
      collateralAsset: baseChainData.assets.usdc,
      atomicSwapSettings: {
        isAtomicSwapAllowed: true,
        isOneToOneSwap: true,
      },
    },
    {
      marketId: 4,
      collateralSynth: "0xEDE1d04C864EeEC40393ED4cb454B85A5ABD071C", // Synthetic Coinbase Wrapped BTC https://basescan.org/address/0xEDE1d04C864EeEC40393ED4cb454B85A5ABD071C
      collateralAsset: baseChainData.assets.cbbtc,
      atomicSwapSettings: {
        isAtomicSwapAllowed: false,
        isOneToOneSwap: false,
      },
    },
    {
      marketId: 6,
      collateralSynth: "0xFA24Be208408F20395914Ba82Def333d987E0080", // Synthetic Wrapped ETH https://basescan.org/address/0xFA24Be208408F20395914Ba82Def333d987E0080
      collateralAsset: baseChainData.assets.weth,
      atomicSwapSettings: {
        isAtomicSwapAllowed: false,
        isOneToOneSwap: false,
      },
    },
    {
      marketId: 7,
      collateralSynth: "0x3526D453D1Edb105E4e2b8448760fC501050d976", // Synthetic Lido Wrapped Staked ETH https://basescan.org/address/0x3526D453D1Edb105E4e2b8448760fC501050d976
      collateralAsset: baseChainData.assets.wsteth,
      atomicSwapSettings: {
        isAtomicSwapAllowed: false,
        isOneToOneSwap: false,
      },
    },
  ],
  collateralSource: "setBalance",
  transferCollateralFrom: "0x25ca6760fc0936127a6e34c3cbd63064b8a0de1f", // should be an account which holds sUSDC
  mintingPositiveDebtForbidden: true,
  deployedNodeModule: "0x4903E09E84259e5105190AaA33e714E1Eaf0bAcD",
  rewardDistributors: ["0x45063DCd92f56138686810eacB1B510C941d6593", "0xe92bcD40849BE5a5eb90065402e508aF4b28263b"], // Spartan Council Pool SNX Rewards, Spartan Council Pool USDC Rewards
  rewardsDistributorLiquidation: LIQUIDATION_REWARDS_DISTRIBUTOR,
  allowedMarketCollateralAssetBalanceSlot: {
    [baseChainData.assets.usdc]: baseChainData.assetsBalanceOfSlot.usdc,
    [baseChainData.assets.cbbtc]: 9,
    [baseChainData.assets.weth]: baseChainData.assetsBalanceOfSlot.weth,
    [baseChainData.assets.wsteth]: 1,
  },
  poolToTestLiquidationRewardClaim: baseChainData.torosPools.sUSDCy,
});
