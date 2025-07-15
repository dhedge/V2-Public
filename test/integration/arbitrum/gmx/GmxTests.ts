import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { launchGmxPerpsTests } from "../../common/gmx/GmxPerpsTest";
import { units } from "../../../testHelpers";
import { launchGmxSwapTests } from "../../common/gmx/GmxSwapTest";
import { launchGmxLpTests } from "../../common/gmx/GmxLpTest";
import { launchGmxClaimTests } from "../../common/gmx/GmxClaimTest";
import { IGmxTestsParams } from "../../common/gmx/gmxTestHelpers";
import { arbitrumProdData } from "../../../../deployment/arbitrum/deploymentData";

const { assets, assetsBalanceOfSlot } = arbitrumChainData;

const testCases = [
  {
    market: "0x47c031236e19d024b42f8AE6780E44A573170703", // BTC/USD [WBTC.e-USDC]
    vaultCollateralAsset: assets.usdcNative,
    vaultWithdrawalAsset: assets.usdcNative,
    sizeAmount: units(1000, 30),
    multiplerToImpactForClaimCollateralTest: 20_000, // need to adjust based on the real time lp condition
    shortCollateral: {
      amount: units(1000, 6),
      address: assets.usdcNative,
      priceFeed: arbitrumChainData.usdPriceFeeds.usdc,
      balanceOfSlot: assetsBalanceOfSlot.usdcNative,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.usdc,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    longCollateral: {
      amount: units(1, 6),
      address: assets.wbtc,
      priceFeed: arbitrumChainData.usdPriceFeeds.wbtc,
      balanceOfSlot: assetsBalanceOfSlot.wbtc,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.wbtc,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    gasToken: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
  },
  {
    market: "0x70d95587d40A2caf56bd97485aB3Eec10Bee6336", // ETH/USD [WETH-USDC]
    vaultCollateralAsset: assets.usdcNative,
    vaultWithdrawalAsset: assets.usdcNative,
    sizeAmount: units(1000, 30),
    multiplerToImpactForClaimCollateralTest: 20_000, // need to adjust based on the real time lp condition
    shortCollateral: {
      amount: units(1000, 6),
      address: assets.usdcNative,
      priceFeed: arbitrumChainData.usdPriceFeeds.usdc,
      balanceOfSlot: assetsBalanceOfSlot.usdcNative,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.usdc,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    longCollateral: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    gasToken: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
  },
  {
    market: "0x09400D9DB990D5ed3f35D7be61DfAEB900Af03C9", // SOL/USD [SOL-USDC]
    vaultCollateralAsset: assets.usdcNative,
    vaultWithdrawalAsset: assets.usdcNative,
    sizeAmount: units(1000, 30),
    multiplerToImpactForClaimCollateralTest: 20_000, // need to adjust based on the real time lp condition
    shortCollateral: {
      amount: units(1000, 6),
      address: assets.usdcNative,
      priceFeed: arbitrumChainData.usdPriceFeeds.usdc,
      balanceOfSlot: assetsBalanceOfSlot.usdcNative,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.usdc,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    longCollateral: {
      amount: units(5, 9),
      address: assets.wrappedsol,
      priceFeed: arbitrumChainData.usdPriceFeeds.sol,
      balanceOfSlot: assetsBalanceOfSlot.wrappedsol,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.sol,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xef0d8b6fda2ceba41da15d4095d1da392a0d2f8ed0c6c7bc0f4cfac8c280b56d",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    gasToken: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
  },
  {
    market: "0x6Ecf2133E2C9751cAAdCb6958b9654baE198a797", // SUI/USD [WETH-USDC]
    vaultCollateralAsset: assets.usdcNative,
    vaultWithdrawalAsset: assets.usdcNative,
    sizeAmount: units(1000, 30),
    multiplerToImpactForClaimCollateralTest: 20_000, // need to adjust based on the real time lp condition
    shortCollateral: {
      amount: units(1000, 6),
      address: assets.usdcNative,
      priceFeed: arbitrumChainData.usdPriceFeeds.usdc,
      balanceOfSlot: assetsBalanceOfSlot.usdcNative,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.usdc,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    longCollateral: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    gasToken: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
  },
  {
    market: "0x6853EA96FF216fAb11D2d930CE3C508556A4bdc4", // DOGE/USD [WETH-USDC]
    vaultCollateralAsset: assets.usdcNative,
    vaultWithdrawalAsset: assets.usdcNative,
    sizeAmount: units(1000, 30),
    multiplerToImpactForClaimCollateralTest: 20_000, // need to adjust based on the real time lp condition
    shortCollateral: {
      amount: units(1000, 6),
      address: assets.usdcNative,
      priceFeed: arbitrumChainData.usdPriceFeeds.usdc,
      balanceOfSlot: assetsBalanceOfSlot.usdcNative,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.usdc,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    longCollateral: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    gasToken: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
  },
  {
    market: "0x0CCB4fAa6f1F1B30911619f1184082aB4E25813c", //  XRP/USD [WETH-USDC]
    vaultCollateralAsset: assets.usdcNative,
    vaultWithdrawalAsset: assets.usdcNative,
    sizeAmount: units(1000, 30),
    multiplerToImpactForClaimCollateralTest: 20_000, // need to adjust based on the real time lp condition
    shortCollateral: {
      amount: units(1000, 6),
      address: assets.usdcNative,
      priceFeed: arbitrumChainData.usdPriceFeeds.usdc,
      balanceOfSlot: assetsBalanceOfSlot.usdcNative,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.usdc,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    longCollateral: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
    gasToken: {
      amount: units(1, 18),
      address: assets.weth,
      priceFeed: arbitrumChainData.usdPriceFeeds.eth,
      balanceOfSlot: assetsBalanceOfSlot.weth,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.eth,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: "0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace",
        maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      },
    },
  },
];

const commonTestParams = {
  ...arbitrumChainData,
  ...arbitrumChainData.gmx,
  chainlinkDataStreamProviderArray: ["0xF4122dF7Be4Ccd46D7397dAf2387B3A14e53d967"],
  pythOracleContract: "0xff1a0f4744e8582DF1aE09D5611b887B6a12925C",
  uiFeeReceiver: "0xff00000000000000000000000000000000000001",
  orderVault: "0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5",
  depositVault: "0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55",
  withdrawalVault: "0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55",
  orderHandler: "0xe68CAAACdf6439628DFD2fe624847602991A31eB",
  depositHandler: "0xfe2Df84627950A0fB98EaD49c69a1DE3F66867d6",
  withdrawalHandler: "0x64fbD82d9F987baF5A59401c64e823232182E8Ed",
  keeper: "0x8E66ee36F2C7B9461F50aA0b53eF0E4e47F4ABBf",
  apiUrl: "https://arbitrum-api.gmxinfra.io/signed_prices/latest",
  underlyingTokensToAdd: [
    {
      address: assets.wbtc,
      oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.wbtc,
      maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
      priceId: "0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33",
      maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
      minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
    },
  ],
  vitrualTokenOracleSettings: arbitrumProdData.gmx?.virtualTokenResolver,
};

testCases.forEach((testParams) => {
  const oneTestParams: IGmxTestsParams = { ...commonTestParams, ...testParams };
  launchGmxClaimTests(oneTestParams);
  launchGmxPerpsTests(oneTestParams);
  launchGmxSwapTests(oneTestParams);
  launchGmxLpTests(oneTestParams);
});
