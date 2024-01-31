import { launchSynthetixV3Tests } from "../../common/synthetixV3/SynthetixV3Test";

const fUSDC = "0x4967d1987930b2CD183dAB4B6C40B8745DD2eba1"; // Fake USDC (Collateral) Token $fUSDC https://goerli.basescan.org/address/0x4967d1987930b2CD183dAB4B6C40B8745DD2eba1
const sUSDC = "0x367Fed42283FeBC9D8A6D78c5ab62F78B6022e27"; // https://goerli.basescan.org/address/0x367Fed42283FeBC9D8A6D78c5ab62F78B6022e27

launchSynthetixV3Tests({
  // stub assets and oracles with random addresses for tests to setup (they're not used in the SynthetixV3 tests)
  assets: {
    dai: "0x30acaa617db983dcbd635461ca96d911da9724c3",
    usdc: "0xb36B6A4d67951C959CE22A8f30aF083fAc215088",
    usdt: "0xf99faf12efe98c6b67a4a96cbb5265af846d6319",
    weth: "0xa2464c1c8aa66b6430c50d85434b2579e66b4cac",
  },
  usdPriceFeeds: {
    dai: "0xb36B6A4d67951C959CE22A8f30aF083fAc215088",
    usdc: "0x30acaa617db983dcbd635461ca96d911da9724c3",
    usdt: "0xa2464c1c8aa66b6430c50d85434b2579e66b4cac",
    eth: "0xf99faf12efe98c6b67a4a96cbb5265af846d6319",
  },
  systemAssets: {
    collateral: {
      address: sUSDC,
      balanceOfSlot: 3, // Not sure how to know it on unverified contract
      proxyTargetTokenState: sUSDC, // Not sure how to know it on unverified contract
    },
    debt: {
      address: "0xa89163A087fe38022690C313b5D4BBF12574637f", // new sUSD https://goerli.basescan.org/address/0xa89163A087fe38022690C313b5D4BBF12574637f
    },
    tokenToCollateral: {
      address: fUSDC,
    },
  },
  allowedLiquidityPoolId: 1,
  synthetixV3Core: "0xF4Df9Dd327Fd30695d478c3c8a2fffAddcdD0d31",
  synthetixAccountNFT: "0xa88694d0025dd96194D1B0237fDEbf7D1D34B02F",
  synthetixV3SpotMarket: "0x26f3EcFa0Aa924649cfd4b74C57637e910A983a4",
  allowedMarketIds: [{ marketId: 1, collateralSynth: sUSDC, collateralAsset: fUSDC }],
  collateralSource: "transferFrom",
  transferCollateralFrom: "0x3239a95a9262034ca28b9a03133775f716f119f8", // should be an account which holds sUSDC
});
