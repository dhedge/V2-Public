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
  uint256 public constant FORK_BLOCK_NUMBER = 355401572;

  address public constant GMX_EXCHANGE_ROUTER = 0x900173A66dbD345006C51fA35fA3aB760FcD843b;
  address public constant GMX_FEE_RECEIVER = 0x26f7cbd49A4DC3321780AE8e7e0cb460f55a7511;
  address public constant GMX_DATA_STORE = 0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8;
  address public constant GMX_READER = 0x0537C767cDAC0726c76Bb89e92904fe28fd02fE1;
  address public constant GMX_REFERRAL_STORAGE = 0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d;
  uint16 public constant GMX_PEPRS_MARKET_ASSET_TYPE = 105;

  address public constant GMX_BTC_VIRTUAL_TOKEN = 0x47904963fc8b2340414262125aF798B9655E58Cd;

  address public constant GMX_SUI_MARKET = 0x6Ecf2133E2C9751cAAdCb6958b9654baE198a797;
  address public constant GMX_DOGECOIN_MARKET = 0x6853EA96FF216fAb11D2d930CE3C508556A4bdc4;
  address public constant GMX_XRP_MARKET = 0x0CCB4fAa6f1F1B30911619f1184082aB4E25813c;

  address public constant GMX_SUI_VIRTURAL_TOKEN = 0x197aa2DE1313c7AD50184234490E12409B2a1f95;
  address public constant GMX_DOGECOIN_VIRTURAL_TOKEN = 0xC4da4c24fd591125c3F47b340b6f4f76111883d8;
  address public constant GMX_XRP_VIRTURAL_TOKEN = 0xc14e065b0067dE91534e032868f5Ac6ecf2c6868;

  bytes32 public constant PYTH_SUI_PRICE_ID = 0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744;
  bytes32 public constant PYTH_WBTC_PRICE_ID = 0xc9d8b075a5c69303365ae23633d4e085199bf5c520a3b90fed1322a0342ffc33;
  bytes32 public constant PYTH_DOGECOIN_PRICE_ID = 0xdcef50dd0a4cd2dcc17e45df1676dcb336a11a61c69df7a0299b0150c672d25c;
  bytes32 public constant PYTH_XRP_PRICE_ID = 0xec5d399846a9209f3fe5881d70aae9268c94339ff9817e8d18ff19fa05eea1c8;

  // Define the whitelist entries
  function getDHedgeVaultsWhitelist() internal pure returns (GmxStructs.PoolSetting[] memory) {
    GmxStructs.PoolSetting[] memory whitelist = new GmxStructs.PoolSetting[](13);

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
    GmxStructs.VirtualTokenOracleSetting[] memory virtualTokenResolver = new GmxStructs.VirtualTokenOracleSetting[](4);
    virtualTokenResolver[0] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_BTC_VIRTUAL_TOKEN,
      virtualTokenMultiplier: 1e44,
      oracleLookupType: GmxStructs.OracleLookupType.ChainlinkPythLib,
      onchainOracle: ChainlinkPythPriceLib.OnchainOracle({
        oracleContract: IChainlinkAggregatorV3(ArbitrumConfig.WBTC_CHAINLINK_ORACLE),
        maxAge: 90000 // 90_000 seconds => 25 hours,
      }),
      pythOracleContract: ArbitrumConfig.PYTH_PRICE_FEED_CONTRACT,
      pythOracleData: PythPriceLib.OffchainOracle({
        priceId: PYTH_WBTC_PRICE_ID,
        maxAge: 86400, // 86400 seconds => 24 hours,
        minConfidenceRatio: 50 // 100/50 => +-2% price deviation acceptable,
      })
    });
    virtualTokenResolver[1] = GmxStructs.VirtualTokenOracleSetting({
      virtualToken: GMX_SUI_VIRTURAL_TOKEN,
      virtualTokenMultiplier: 1e43,
      oracleLookupType: GmxStructs.OracleLookupType.PythLib,
      onchainOracle: emptyOnchainOracle(),
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
    return virtualTokenResolver;
  }

  function getAdditonalAssetSetupData() internal pure returns (IAssetHandler.Asset[] memory) {
    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);
    IAssetHandler.Asset memory asset = IAssetHandler.Asset({
      asset: GMX_XRP_MARKET,
      assetType: GMX_PEPRS_MARKET_ASSET_TYPE,
      aggregator: ArbitrumConfig.USD_PRICE_AGGREGATOR_PROD
    });
    assets[0] = asset;
    return assets;
  }
}
