// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {GmxStructs} from "contracts/utils/gmx/GmxStructs.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {PythPriceLib} from "contracts/utils/pyth/PythPriceLib.sol";
import {ChainlinkPythPriceLib} from "contracts/utils/chainlinkPyth/ChainlinkPythPriceLib.sol";
import {IAggregatorV3Interface as IChainlinkAggregatorV3} from "contracts/interfaces/IAggregatorV3Interface.sol";

library GmxTestSharedData {
  uint256 public constant FORK_BLOCK_NUMBER = 443306920;

  address public constant GMX_EXCHANGE_ROUTER = 0x1C3fa76e6E1088bCE750f23a5BFcffa1efEF6A41;
  address public constant GMX_FEE_RECEIVER = 0x26f7cbd49A4DC3321780AE8e7e0cb460f55a7511;
  address public constant GMX_DATA_STORE = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
  address public constant GMX_READER = 0x470fbC46bcC0f16532691Df360A07d8Bf5ee0789;
  address public constant GMX_REFERRAL_STORAGE = 0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d;
  uint16 public constant GMX_PEPRS_MARKET_ASSET_TYPE = 105;

  address public constant GMX_BTC_VIRTUAL_TOKEN = 0x47904963fc8b2340414262125aF798B9655E58Cd;

  address public constant GMX_SUI_MARKET = 0x6Ecf2133E2C9751cAAdCb6958b9654baE198a797;
  address public constant GMX_DOGECOIN_MARKET = 0x6853EA96FF216fAb11D2d930CE3C508556A4bdc4;
  address public constant GMX_XRP_MARKET = 0x0CCB4fAa6f1F1B30911619f1184082aB4E25813c;
  address public constant GMX_HYPE_MARKET = 0xBcb8FE13d02b023e8f94f6881Cc0192fd918A5C0;
  address public constant GMX_CRV_MARKET = 0x0e46941F9bfF8d0784BFfa3d0D7883CDb82D7aE7;
  address public constant GMX_PUMP_MARKET = 0x4C0Bb704529Fa49A26bD854802d70206982c6f1B;
  address public constant GMX_BNB_BTCUSDC_MARKET = 0x065577D05c3D4C11505ed7bc97BBF85d462A6A6f;
  address public constant GMX_XAUT_BTCUSDC_MARKET = 0xeb28aD1a2e497F4Acc5D9b87e7B496623C93061E;
  address public constant GMX_AAVE_AAVEUSDC_MARKET = 0x1CbBa6346F110c8A5ea739ef2d1eb182990e4EB2;

  address public constant GMX_SUI_VIRTURAL_TOKEN = 0x197aa2DE1313c7AD50184234490E12409B2a1f95;
  address public constant GMX_DOGECOIN_VIRTURAL_TOKEN = 0xC4da4c24fd591125c3F47b340b6f4f76111883d8;
  address public constant GMX_XRP_VIRTURAL_TOKEN = 0xc14e065b0067dE91534e032868f5Ac6ecf2c6868;
  address public constant GMX_HYPE_VIRTURAL_TOKEN = 0xfDFA0A749dA3bCcee20aE0B4AD50E39B26F58f7C;
  address public constant GMX_CRV_VIRTURAL_TOKEN = 0xe5f01aeAcc8288E9838A60016AB00d7b6675900b;
  address public constant GMX_PUMP_VIRTURAL_TOKEN = 0x9c060B2fA953b5f69879a8B7B81f62BFfEF360be;
  address public constant GMX_GOLD_VIRTURAL_TOKEN = 0x7624cccCc59361D583F28BEC40D37e7771d2ef5D;

  bytes32 public constant PYTH_SUI_PRICE_ID = 0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744;
  bytes32 public constant PYTH_WBTC_PRICE_ID = 0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33;
  bytes32 public constant PYTH_BTC_PRICE_ID = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
  bytes32 public constant PYTH_DOGECOIN_PRICE_ID = 0xdcef50dd0a4cd2dcc17e45df1676dcb336a11a61c69df7a0299b0150c672d25c;
  bytes32 public constant PYTH_XRP_PRICE_ID = 0xec5d399846a9209f3fe5881d70aae9268c94339ff9817e8d18ff19fa05eea1c8;
  bytes32 public constant PYTH_HYPE_PRICE_ID = 0x4279e31cc369bbcc2faf022b382b080e32a8e689ff20fbc530d2a603eb6cd98b;
  bytes32 public constant PYTH_BNB_PRICE_ID = 0x2f95862b045670cd22bee3114c39763a4a08beeb663b145d283c31d7d1101c4f;
  bytes32 public constant PYTH_CRV_PRICE_ID = 0xa19d04ac696c7a6616d291c7e5d1377cc8be437c327b75adb5dc1bad745fcae8;
  bytes32 public constant PYTH_LINK_PRICE_ID = 0x8ac0c70fff57e9aefdf5edf44b51d62c2d433653cbb2cf5cc06bb115af04d221;
  bytes32 public constant PYTH_PUMP_PRICE_ID = 0x7a01fca212788bba7c5bf8c9efd576a8a722f070d2c17596ff7bb609b8d5c3b9;
  bytes32 public constant PYTH_GOLD_PRICE_ID = 0x44465e17d2e9d390e70c999d5a11fda4f092847fcd2e3e5aa089d96c98a30e67;

  // Define the whitelist entries
  function getDHedgeVaultsWhitelist() internal pure returns (GmxStructs.PoolSetting[] memory) {
    GmxStructs.PoolSetting[] memory whitelist = new GmxStructs.PoolSetting[](43);

    whitelist[0] = GmxStructs.PoolSetting(ArbitrumConfig.ETHy, ArbitrumConfig.WETH);
    whitelist[1] = GmxStructs.PoolSetting(ArbitrumConfig.SOLBULL3X, ArbitrumConfig.USDC);
    whitelist[2] = GmxStructs.PoolSetting(ArbitrumConfig.SOLBULL2X, ArbitrumConfig.USDC);
    whitelist[3] = GmxStructs.PoolSetting(ArbitrumConfig.SOLBEAR1X, ArbitrumConfig.USDC);
    whitelist[4] = GmxStructs.PoolSetting(ArbitrumConfig.ETHBULL4X, ArbitrumConfig.WETH);
    whitelist[5] = GmxStructs.PoolSetting(ArbitrumConfig.BTCBULL4X, ArbitrumConfig.WBTC);
    whitelist[6] = GmxStructs.PoolSetting(ArbitrumConfig.SUIBULL2X, ArbitrumConfig.USDC);
    whitelist[7] = GmxStructs.PoolSetting(ArbitrumConfig.SUI1X, ArbitrumConfig.USDC);
    whitelist[8] = GmxStructs.PoolSetting(ArbitrumConfig.SOL1X, ArbitrumConfig.USDC);
    whitelist[9] = GmxStructs.PoolSetting(ArbitrumConfig.BTCy, ArbitrumConfig.WBTC);
    whitelist[10] = GmxStructs.PoolSetting(ArbitrumConfig.DOGEBULL2X, ArbitrumConfig.USDC);
    whitelist[11] = GmxStructs.PoolSetting(ArbitrumConfig.DOGE1X, ArbitrumConfig.USDC);
    whitelist[12] = GmxStructs.PoolSetting(ArbitrumConfig.XRP1X, ArbitrumConfig.USDC);
    whitelist[13] = GmxStructs.PoolSetting(ArbitrumConfig.HYPE1X, ArbitrumConfig.USDC);
    whitelist[14] = GmxStructs.PoolSetting(ArbitrumConfig.XRPBULL2X, ArbitrumConfig.USDC);
    whitelist[15] = GmxStructs.PoolSetting(ArbitrumConfig.BNB1X, ArbitrumConfig.USDC);
    whitelist[16] = GmxStructs.PoolSetting(ArbitrumConfig.CRV1X, ArbitrumConfig.USDC);
    whitelist[17] = GmxStructs.PoolSetting(ArbitrumConfig.LINK1X, ArbitrumConfig.USDC);
    whitelist[18] = GmxStructs.PoolSetting(ArbitrumConfig.LINKBULL2X, ArbitrumConfig.USDC);
    whitelist[19] = GmxStructs.PoolSetting(ArbitrumConfig.CRVBULL2X, ArbitrumConfig.USDC);
    whitelist[20] = GmxStructs.PoolSetting(ArbitrumConfig.PUMP1X, ArbitrumConfig.USDC);
    whitelist[21] = GmxStructs.PoolSetting(ArbitrumConfig.PUMPBULL2X, ArbitrumConfig.USDC);
    whitelist[22] = GmxStructs.PoolSetting(ArbitrumConfig.BNBBULL2X, ArbitrumConfig.USDC);
    whitelist[23] = GmxStructs.PoolSetting(ArbitrumConfig.SOLBEAR2X, ArbitrumConfig.USDC);
    whitelist[24] = GmxStructs.PoolSetting(ArbitrumConfig.XRPBEAR1X, ArbitrumConfig.USDC);
    whitelist[25] = GmxStructs.PoolSetting(ArbitrumConfig.BNBBEAR1X, ArbitrumConfig.USDC);
    whitelist[26] = GmxStructs.PoolSetting(ArbitrumConfig.DOGEBEAR1X, ArbitrumConfig.USDC);
    whitelist[27] = GmxStructs.PoolSetting(ArbitrumConfig.LINKBEAR1X, ArbitrumConfig.USDC);
    whitelist[28] = GmxStructs.PoolSetting(ArbitrumConfig.HYPEBEAR1X, ArbitrumConfig.USDC);
    whitelist[29] = GmxStructs.PoolSetting(ArbitrumConfig.SUIBEAR1X, ArbitrumConfig.USDC);
    whitelist[30] = GmxStructs.PoolSetting(ArbitrumConfig.PUMPBEAR1X, ArbitrumConfig.USDC);
    whitelist[31] = GmxStructs.PoolSetting(ArbitrumConfig.CRVBEAR1X, ArbitrumConfig.USDC);
    whitelist[32] = GmxStructs.PoolSetting(ArbitrumConfig.ETHBEAR2X, ArbitrumConfig.USDC);
    whitelist[33] = GmxStructs.PoolSetting(ArbitrumConfig.BTCBEAR2X, ArbitrumConfig.USDC);
    whitelist[34] = GmxStructs.PoolSetting(ArbitrumConfig.SUIBULL3X, ArbitrumConfig.USDC);
    whitelist[35] = GmxStructs.PoolSetting(ArbitrumConfig.XRPBULL3X, ArbitrumConfig.USDC);
    whitelist[36] = GmxStructs.PoolSetting(ArbitrumConfig.GOLD1X, ArbitrumConfig.USDC);
    whitelist[37] = GmxStructs.PoolSetting(ArbitrumConfig.GOLDBULL2X, ArbitrumConfig.USDC);
    whitelist[38] = GmxStructs.PoolSetting(ArbitrumConfig.GOLDBULL3X, ArbitrumConfig.USDC);
    whitelist[39] = GmxStructs.PoolSetting(ArbitrumConfig.GOLDBEAR1X, ArbitrumConfig.USDC);
    whitelist[40] = GmxStructs.PoolSetting(ArbitrumConfig.AAVEBEAR1X, ArbitrumConfig.USDC);
    whitelist[41] = GmxStructs.PoolSetting(ArbitrumConfig.AAVEBULL2X, ArbitrumConfig.USDC);
    whitelist[42] = GmxStructs.PoolSetting(ArbitrumConfig.HYPEBULL3X, ArbitrumConfig.USDC);

    return whitelist;
  }

  function getGmxContractGuardConfig() internal pure returns (GmxStructs.GmxContractGuardConfig memory) {
    GmxStructs.GmxContractGuardConfig memory config = GmxStructs.GmxContractGuardConfig({
      gmxExchangeRouter: GMX_EXCHANGE_ROUTER,
      feeReceiver: GMX_FEE_RECEIVER,
      dataStore: GMX_DATA_STORE,
      reader: GMX_READER,
      referralStorage: GMX_REFERRAL_STORAGE
    });

    return config;
  }

  function emptyOffchainOracle() internal pure returns (PythPriceLib.OffchainOracle memory) {
    return PythPriceLib.OffchainOracle({priceId: bytes32(0), maxAge: 0, minConfidenceRatio: 0});
  }

  function emptyOnchainOracle() internal pure returns (ChainlinkPythPriceLib.OnchainOracle memory) {
    return ChainlinkPythPriceLib.OnchainOracle({oracleContract: IChainlinkAggregatorV3(0), maxAge: 0});
  }

  function getVirtualTokenResolver() internal pure returns (GmxStructs.VirtualTokenOracleSetting[] memory) {
    GmxStructs.VirtualTokenOracleSetting[] memory virtualTokenResolver = new GmxStructs.VirtualTokenOracleSetting[](8);
    virtualTokenResolver[0] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_BTC_VIRTUAL_TOKEN,
      virtualTokenMultiplier: 1e44,
      oracleLookupType: GmxStructs.OracleLookupType.ChainlinkPythLib,
      onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
        oracleContract: IChainlinkAggregatorV3(ArbitrumConfig.BTC_CHAINLINK_ORACLE),
        maxAge: 90000 // 90_000 seconds => 25 hours,
      }),
      pythOracleContract: ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      pythOracleData: PythPriceLib.OffchainOracle({
        priceId: PYTH_BTC_PRICE_ID,
        maxAge: 86400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50 // 100/50 => +-2% price deviation acceptable,
      })
    });
    virtualTokenResolver[1] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_SUI_VIRTURAL_TOKEN,
      virtualTokenMultiplier: 1e43,
      oracleLookupType: GmxStructs.OracleLookupType.ChainlinkPythLib,
      onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
        oracleContract: IChainlinkAggregatorV3(ArbitrumConfig.SUI_CHAINLINK_ORACLE),
        maxAge: 90000 // 90_000 seconds => 25 hours,
      }),
      pythOracleContract: ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      pythOracleData: PythPriceLib.OffchainOracle({
        priceId: PYTH_SUI_PRICE_ID,
        maxAge: 1500, // 1500 seconds => 25 mins
        minConfidenceRatio: 50 // 100/50 => +-2% price deviation acceptable,
      })
    });
    virtualTokenResolver[2] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_DOGECOIN_VIRTURAL_TOKEN,
      virtualTokenMultiplier: 1e44,
      oracleLookupType: GmxStructs.OracleLookupType.ChainlinkPythLib,
      onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
        oracleContract: IChainlinkAggregatorV3(ArbitrumConfig.DOGECOIN_CHAINLINK_ORACLE),
        maxAge: 90000 // 90_000 seconds => 25 hours,
      }),
      pythOracleContract: ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      pythOracleData: PythPriceLib.OffchainOracle({
        priceId: PYTH_DOGECOIN_PRICE_ID,
        maxAge: 86400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50 // 100/50 => +-2% price deviation acceptable,
      })
    });
    virtualTokenResolver[3] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_XRP_VIRTURAL_TOKEN,
      virtualTokenMultiplier: 1e46,
      oracleLookupType: GmxStructs.OracleLookupType.ChainlinkPythLib,
      onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
        oracleContract: IChainlinkAggregatorV3(ArbitrumConfig.XRP_CHAINLINK_ORACLE),
        maxAge: 90000 // 90_000 seconds => 25 hours,
      }),
      pythOracleContract: ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      pythOracleData: PythPriceLib.OffchainOracle({
        priceId: PYTH_XRP_PRICE_ID,
        maxAge: 86400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50 // 100/50 => +-2% price deviation acceptable,
      })
    });
    virtualTokenResolver[4] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_HYPE_VIRTURAL_TOKEN,
      virtualTokenMultiplier: 1e44,
      oracleLookupType: GmxStructs.OracleLookupType.ChainlinkPythLib,
      onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
        oracleContract: IChainlinkAggregatorV3(ArbitrumConfig.HYPE_CHAINLINK_ORACLE),
        maxAge: 90000 // 90_000 seconds => 25 hours,
      }),
      pythOracleContract: ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      pythOracleData: PythPriceLib.OffchainOracle({
        priceId: PYTH_HYPE_PRICE_ID,
        maxAge: 86400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50 // 100/50 => +-2% price deviation acceptable,
      })
    });
    virtualTokenResolver[5] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_CRV_VIRTURAL_TOKEN,
      virtualTokenMultiplier: 1e34,
      oracleLookupType: GmxStructs.OracleLookupType.ChainlinkPythLib,
      onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
        oracleContract: IChainlinkAggregatorV3(ArbitrumConfig.CRV_CHAINLINK_ORACLE),
        maxAge: 90000 // 90_000 seconds => 25 hours,
      }),
      pythOracleContract: ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      pythOracleData: PythPriceLib.OffchainOracle({
        priceId: PYTH_CRV_PRICE_ID,
        maxAge: 86400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50 // 100/50 => +-2% price deviation acceptable,
      })
    });
    virtualTokenResolver[6] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_PUMP_VIRTURAL_TOKEN,
      virtualTokenMultiplier: 1e34,
      oracleLookupType: GmxStructs.OracleLookupType.ChainlinkPythLib,
      onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
        oracleContract: IChainlinkAggregatorV3(ArbitrumConfig.PUMP_CHAINLINK_ORACLE),
        maxAge: 90000 // 90_000 seconds => 25 hours,
      }),
      pythOracleContract: ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      pythOracleData: PythPriceLib.OffchainOracle({
        priceId: PYTH_PUMP_PRICE_ID,
        maxAge: 86400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50 // 100/50 => +-2% price deviation acceptable,
      })
    });
    virtualTokenResolver[7] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_GOLD_VIRTURAL_TOKEN,
      virtualTokenMultiplier: 1e34,
      oracleLookupType: GmxStructs.OracleLookupType.PythLib,
      onchainOracle: emptyOnchainOracle(),
      pythOracleContract: ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      pythOracleData: PythPriceLib.OffchainOracle({
        priceId: PYTH_GOLD_PRICE_ID,
        maxAge: 1500, // 1500 seconds => 25 minutes,
        minConfidenceRatio: 50 // 100/50 => +-2% price deviation acceptable,
      })
    });
    return virtualTokenResolver;
  }

  function getAdditonalAssetSetupData() internal pure returns (IAssetHandler.Asset[] memory) {
    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);

    IAssetHandler.Asset memory asset_aave_aaveusdc_market = IAssetHandler.Asset({
      asset: GMX_AAVE_AAVEUSDC_MARKET,
      assetType: GMX_PEPRS_MARKET_ASSET_TYPE,
      aggregator: ArbitrumConfig.USD_PRICE_AGGREGATOR_PROD
    });

    assets[0] = asset_aave_aaveusdc_market;

    return assets;
  }
}
