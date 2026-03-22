import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { launchGmxPerpsTests } from "../../common/gmx/GmxPerpsTest";
import { units } from "../../../testHelpers";
import { launchGmxSwapTests } from "../../common/gmx/GmxSwapTest";
import { launchGmxLpTests } from "../../common/gmx/GmxLpTest";
import { launchGmxClaimTests } from "../../common/gmx/GmxClaimTest";
import { IGmxTestsParams } from "../../common/gmx/gmxTestHelpers";
import { arbitrumProdData } from "../../../../deployment/arbitrum/deploymentData";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";

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
  {
    market: "0xBcb8FE13d02b023e8f94f6881Cc0192fd918A5C0", //  HYPE/USD [WBTC-USDC]
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
    market: "0x065577D05c3D4C11505ed7bc97BBF85d462A6A6f", // BNB/USD [WBTC.e-USDC]
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
    market: "0x0e46941F9bfF8d0784BFfa3d0D7883CDb82D7aE7", // CRV/USD - [WETH-USDC]
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
    market: "0x4C0Bb704529Fa49A26bD854802d70206982c6f1B", //  PUMP/USD [WBTC-USDC]
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
    market: "0xeb28aD1a2e497F4Acc5D9b87e7B496623C93061E", //  XAUT/USD [WBTC-USDC]
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
    market: "0x1CbBa6346F110c8A5ea739ef2d1eb182990e4EB2", // AAVE/USD [AAVE-USDC]
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
      amount: units(5, 18),
      address: assets.aave, // AAVE token
      priceFeed: arbitrumChainData.usdPriceFeeds.aave,
      balanceOfSlot: assetsBalanceOfSlot.aave,
      priceConfig: {
        oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.aave,
        maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
        priceId: arbitrumChainData.pyth.priceIds.aave,
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

  pythOracleContract: "0xff1a0f4744e8582DF1aE09D5611b887B6a12925C",
  uiFeeReceiver: "0xff00000000000000000000000000000000000001",
  orderVault: "0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5",
  depositVault: "0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55",
  withdrawalVault: "0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55",
  orderHandler: "0x04315E233C1c6FfA61080B76E29d5e8a1f7B4A35",
  depositHandler: "0x563E8cDB5Ba929039c2Bb693B78CE12dC0AAfaDa",
  withdrawalHandler: "0x1EC018d2b6ACCA20a0bEDb86450b7E27D1D8355B",
  chainlinkDataStreamProviderArray: ["0xE1d5a068c5b75E0c7Ea1A9Fe8EA056f9356C6fFD"],
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
      assetType: AssetType["Chainlink direct USD price feed with 8 decimals"],
    },
    {
      address: assets.wrappedbnb,
      oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.bnb,
      maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
      priceId: "0x2f95862b045670cd22bee3114c39763a4a08beeb663b145d283c31d7d1101c4f",
      maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
      minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      assetType: AssetType["Chainlink direct USD price feed with 8 decimals"],
    },
    {
      address: "0x7624cccCc59361D583F28BEC40D37e7771d2ef5D", // virtual XAUT, Tether Gold
      oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.xau,
      maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
      priceId: arbitrumChainData.pyth.priceIds.xaut,
      maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
      minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
      assetType: AssetType["Virtual Token Asset"],
    },
  ],
  vitrualTokenOracleSettings: arbitrumProdData.gmx?.virtualTokenResolver,
};

// v2.2b keepers execution, with asset-guard and contract-guard updated
testCases.forEach((testParams) => {
  const oneTestParams: IGmxTestsParams = {
    ...commonTestParams,
    ...testParams,
    orderHandler: "0x63492B775e30a9E6b4b4761c12605EB9d071d5e9",
    depositHandler: "0x33871b8568eDC4adf33338cdD8cF52a0eCC84D42",
    withdrawalHandler: "0x11e9E7464f3Bc887a7290ec41fCd22f619b177fd",
  };
  launchGmxClaimTests(oneTestParams);
  launchGmxPerpsTests(oneTestParams);
  launchGmxSwapTests(oneTestParams);
  launchGmxLpTests(oneTestParams);
});
