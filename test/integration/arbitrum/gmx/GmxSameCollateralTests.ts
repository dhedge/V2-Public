import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { launchGmxPerpsTests } from "../../common/gmx/GmxPerpsTest";
import { units } from "../../../testHelpers";
import { launchGmxLpTests } from "../../common/gmx/GmxLpTest";
import { IGmxTestsParams } from "../../common/gmx/gmxTestHelpers";
import { launchGmxClaimTests } from "../../common/gmx/GmxClaimTest";
import { arbitrumProdData } from "../../../../deployment/arbitrum/deploymentData";

const { assets, assetsBalanceOfSlot } = arbitrumChainData;

const testParams: IGmxTestsParams = {
  ...arbitrumChainData,
  vaultCollateralAsset: assets.tbtc,
  vaultWithdrawalAsset: assets.tbtc,
  sizeAmount: units(8, 30),
  multiplerToImpactForClaimCollateralTest: 2000,
  longCollateral: {
    amount: units(6, 14),
    address: assets.tbtc,
    priceFeed: arbitrumChainData.usdPriceFeeds.tbtc,
    balanceOfSlot: assetsBalanceOfSlot.tbtc,
    priceConfig: {
      oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.tbtc,
      maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
      priceId: "0x56a3121958b01f99fdc4e1fd01e81050602c7ace3a571918bb55c6a96657cca9",
      maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
      minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
    },
  },
  shortCollateral: {
    amount: units(6, 14),
    address: assets.tbtc,
    priceFeed: arbitrumChainData.usdPriceFeeds.tbtc,
    balanceOfSlot: assetsBalanceOfSlot.tbtc,
    priceConfig: {
      oracleContractAddressOnchain: arbitrumChainData.usdPriceFeeds.tbtc,
      maxAgeOnchain: 90_000, // 90_000 seconds => 25 hours,
      priceId: "0x56a3121958b01f99fdc4e1fd01e81050602c7ace3a571918bb55c6a96657cca9",
      maxAgeOffchain: 86_400, // 86400 seconds => 24 hours,
      minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
    },
  },
  gasToken: {
    amount: units(2, 18),
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
  ...arbitrumChainData.gmx,
  market: "0xd62068697bCc92AF253225676D618B0C9f17C663",
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
};

launchGmxPerpsTests(testParams);
launchGmxLpTests(testParams);
launchGmxClaimTests(testParams);
