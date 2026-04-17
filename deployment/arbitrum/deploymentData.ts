import { BigNumber, ethers } from "ethers";
import { arbitrumChainData } from "../../config/chainData/arbitrumData";
import { IAddresses, IFileNames } from "../types";
import { FLAT_MONEY_PERP_MARKET_BOT_TEST } from "../base/deploymentData";
import { baseChainData } from "../../config/chainData/baseData";
import { ovmChainData } from "../../config/chainData/ovmData";

export const arbitrumProdData: IAddresses = {
  protocolDaoAddress: arbitrumChainData.dHEDGE.daoMultisig,
  protocolTreasuryAddress: arbitrumChainData.dHEDGE.treasury,
  proxyAdminAddress: arbitrumChainData.proxyAdmin,

  easySwapperConfig: {
    customLockupAllowedPools: [
      arbitrumChainData.torosPools.ETHBULL3X,
      arbitrumChainData.torosPools.BTCBULL3X,
      arbitrumChainData.torosPools.ETHBULL2X,
      arbitrumChainData.torosPools.BTCBULL2X,
      arbitrumChainData.torosPools.ETHBEAR1X,
      arbitrumChainData.torosPools.BTCBEAR1X,
    ],
    feeByPassManagers: ["0xfbD2B4216f422DC1eEe1Cff4Fb64B726F099dEF5"], // Toros Manager
    feeNumerator: 10,
    feeDenominator: 10000,
  },

  v2RouterAddresses: arbitrumChainData.v2Routers,

  superSwapper: {
    routeHints: arbitrumChainData.routeHints,
  },

  assets: {
    nativeAssetWrapper: arbitrumChainData.assets.weth,
    weth: arbitrumChainData.assets.weth,
    usdc: arbitrumChainData.assets.usdc,
    dai: arbitrumChainData.assets.dai,
    dht: arbitrumChainData.assets.dht,
  },

  uniV2: {
    factory: arbitrumChainData.uniswapV2.factory,
  },

  uniV3: {
    uniswapV3FactoryAddress: arbitrumChainData.uniswapV3.factory,
    uniswapV3RouterAddress: arbitrumChainData.uniswapV3.router,
    uniSwapV3NonfungiblePositionManagerAddress: arbitrumChainData.uniswapV3.nonfungiblePositionManager,
  },

  aaveV3: {
    aaveIncentivesControllerAddress: arbitrumChainData.aaveV3.incentivesController,
    aaveLendingPoolAddress: arbitrumChainData.aaveV3.lendingPool,
  },

  oneInchV5RouterAddress: arbitrumChainData.oneInch.v5Router,
  oneInchV6RouterAddress: arbitrumChainData.oneInch.v6Router,

  balancerV2VaultAddress: arbitrumChainData.balancer.v2Vault,

  ramses: {
    voter: arbitrumChainData.ramses.voter,
    router: arbitrumChainData.ramses.router,
    xRam: arbitrumChainData.ramses.xoRAM,
  },

  ramsesCL: {
    nonfungiblePositionManager: arbitrumChainData.ramsesCL.nonfungiblePositionManager,
    voter: arbitrumChainData.ramses.voter, // same as the ramses voter
  },

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  zeroExExchangeProxy: arbitrumChainData.zeroEx.exchangeProxy,

  synthetixV3: {
    core: arbitrumChainData.synthetixV3.core,
    dHedgeVaultsWhitelist: [
      {
        poolLogic: arbitrumChainData.torosPools.sUSDy, // https://dhedge.org/vault/0xc3198eb5102fb3335c0e911ef1da4bc07e403dd1
        collateralAsset: arbitrumChainData.assets.usdcNative,
        debtAsset: arbitrumChainData.assets.usdx,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: arbitrumChainData.torosPools.sARBy, // https://dhedge.org/vault/0xddd6b1f34e12c0230ab23cbd4514560b24438514
        collateralAsset: arbitrumChainData.assets.arb,
        debtAsset: arbitrumChainData.assets.usdx,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: arbitrumChainData.torosPools.sETHy, // https://dhedge.org/vault/0xddd6b1f34e12c0230ab23cbd4514560b24438514
        collateralAsset: arbitrumChainData.assets.wsteth,
        debtAsset: arbitrumChainData.assets.usdx,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: "0xae150ffd7b5b986ecd1cd4b5c78ef7c5f042a08b", // Synthetix USDC Test, https://dhedge.org/vault/0xae150ffd7b5b986ecd1cd4b5c78ef7c5f042a08b
        collateralAsset: arbitrumChainData.assets.usdcNative,
        debtAsset: arbitrumChainData.assets.usdx,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: "0xe19f8ee8f0cc96b8a95587f1f8b8ee2a0915e5b6", // Synthetix WETH Test, https://dhedge.org/vault/0xe19f8ee8f0cc96b8a95587f1f8b8ee2a0915e5b6
        collateralAsset: arbitrumChainData.assets.wsteth,
        debtAsset: arbitrumChainData.assets.usdx,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: "0xc205b7ab524b7022e7a93bed347a23465d2feeab", // Synthetix Arb Test, https://dhedge.org/vault/0xc205b7ab524b7022e7a93bed347a23465d2feeab
        collateralAsset: arbitrumChainData.assets.arb,
        debtAsset: arbitrumChainData.assets.usdx,
        snxLiquidityPoolId: 1,
      },
    ],
    spotMarket: arbitrumChainData.synthetixV3.spotMarket,
    perpsMarket: arbitrumChainData.synthetixV3.perpsMarket,
    allowedMarkets: [
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
    windows: {
      delegationWindow: {
        start: {
          dayOfWeek: 2,
          hour: 0,
        },
        end: {
          dayOfWeek: 4,
          hour: 12,
        },
      },
      undelegationWindow: {
        start: {
          dayOfWeek: 4,
          hour: 12,
        },
        end: {
          dayOfWeek: 5,
          hour: 0,
        },
      },
    },
    withdrawalLimit: {
      usdValue: BigNumber.from(50_000).mul(BigNumber.from(10).pow(18)), // $50k
      percent: BigNumber.from(90).mul(BigNumber.from(10).pow(16)), // 90%
    },
  },

  rewardDistribution: [
    {
      amountPerSecond: BigNumber.from(3124)
        .mul(BigNumber.from(10).pow(18))
        .div(30 * 24 * 60 * 60), // 30 days in seconds,
      token: arbitrumChainData.assets.arb,
      whitelistedPools: [arbitrumChainData.torosPools.ETHy],
    },
    {
      amountPerSecond: BigNumber.from(100_000)
        .mul(BigNumber.from(10).pow(18))
        .div(8 * 24 * 60 * 60), // 8 days in seconds,
      token: arbitrumChainData.assets.arb,
      whitelistedPools: [arbitrumChainData.torosPools.ETHy],
    },
    {
      amountPerSecond: BigNumber.from(22_500)
        .mul(BigNumber.from(10).pow(6))
        .div(30 * 24 * 60 * 60), // 30 days in seconds,
      token: arbitrumChainData.assets.usdcNative,
      whitelistedPools: [arbitrumChainData.torosPools.sETHy],
    },
    {
      amountPerSecond: BigNumber.from(25_000)
        .mul(BigNumber.from(10).pow(18))
        .div(90 * 24 * 60 * 60), // 90 days in seconds,
      token: arbitrumChainData.assets.arb,
      whitelistedPools: [arbitrumChainData.torosPools.BTCy],
    },
  ],

  compoundV3: {
    rewards: arbitrumChainData.compoundV3.rewards,
  },

  flatMoney: {
    swapper: arbitrumChainData.flatMoney.swapper,
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      arbitrumChainData.torosPools.BTCBEAR1X,
      arbitrumChainData.torosPools.BTCBULL2X,
      arbitrumChainData.torosPools.BTCBULL3X,
      arbitrumChainData.torosPools.ETHBEAR1X,
      arbitrumChainData.torosPools.ETHBULL2X,
      arbitrumChainData.torosPools.ETHBULL3X,
      arbitrumChainData.torosPools.SOLBULL2X,
      arbitrumChainData.torosPools.SOLBULL3X,
      arbitrumChainData.torosPools.SOLBEAR1X,
      arbitrumChainData.torosPools.BTCBULL4X,
      arbitrumChainData.torosPools.ETHBULL4X,
      arbitrumChainData.torosPools.SUIBULL2X,
      arbitrumChainData.torosPools.DOGEBULL2X,
      arbitrumChainData.torosPools.SOL1X,
      arbitrumChainData.torosPools.SUI1X,
      arbitrumChainData.torosPools.DOGE1X,
      arbitrumChainData.torosPools.XRP1X,
      arbitrumChainData.torosPools.HYPE1X,
      arbitrumChainData.torosPools.XRPBULL2X,
      arbitrumChainData.torosPools.BNB1X,
      arbitrumChainData.torosPools.CRV1X,
      arbitrumChainData.torosPools.BTCy,
      arbitrumChainData.torosPools.LINK1X,
      arbitrumChainData.torosPools.LINKBULL2X,
      arbitrumChainData.torosPools.HYPEBULL2X,
      arbitrumChainData.torosPools.CRVBULL2X,
      arbitrumChainData.torosPools.PUMP1X,
      arbitrumChainData.torosPools.PUMPBULL2X,
      arbitrumChainData.torosPools.BNBBULL2X,
      arbitrumChainData.torosPools.ETHBEAR2X,
      arbitrumChainData.torosPools.BTCBEAR2X,
      arbitrumChainData.torosPools.SOLBEAR2X,
      arbitrumChainData.torosPools.XRPBEAR1X,
      arbitrumChainData.torosPools.BNBBEAR1X,
      arbitrumChainData.torosPools.DOGEBEAR1X,
      arbitrumChainData.torosPools.LINKBEAR1X,
      arbitrumChainData.torosPools.HYPEBEAR1X,
      arbitrumChainData.torosPools.SUIBEAR1X,
      arbitrumChainData.torosPools.PUMPBEAR1X,
      arbitrumChainData.torosPools.CRVBEAR1X,
      arbitrumChainData.torosPools.SUIBULL3X,
      arbitrumChainData.torosPools.XRPBULL3X,
      arbitrumChainData.torosPools.GOLD1X,
      arbitrumChainData.torosPools.GOLDBULL2X,
      arbitrumChainData.torosPools.GOLDBULL3X,
      arbitrumChainData.torosPools.GOLDBEAR1X,
      arbitrumChainData.torosPools.BTC1X,
      arbitrumChainData.torosPools.ETH1X,
      arbitrumChainData.torosPools.AAVEBEAR1X,
      arbitrumChainData.torosPools.AAVEBULL2X,
      arbitrumChainData.torosPools.BTCHOSRTVOL,
      arbitrumChainData.torosPools.BTCCOVCALL,
      arbitrumChainData.torosPools.HYPEBULL3X,
      arbitrumChainData.dytmTestVaults.DYTMTesting, // for testing Dytm as the index vault(yield basket)
    ],
  },

  gmx: {
    ...arbitrumChainData.gmx,
    feeReceiver: arbitrumChainData.dHEDGE.treasury, // ui fee, https://gmx-docs.io/docs/api/contracts-v2/#ui-fee
    dHedgeVaultsWhitelist: [
      {
        poolLogic: arbitrumChainData.torosPools.BTCy, // https://dhedge.org/vault/0x319fd1d1d74607b7a224eb4e31a4aa75837d7d01
        withdrawalAsset: arbitrumChainData.assets.wbtc,
      },
      {
        poolLogic: "0xe24f85a5a5c8a9417537d82dfaa3e14efa8fb322", // GMX Test, https://dhedge.org/vault/0xe24f85a5a5c8a9417537d82dfaa3e14efa8fb322
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.gmxTestVaults.gmxTest2,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: "0xBF30FfE47111ae5D0a5A9F9a187EAD0170BA4D8f", // GMX Test 3, https://dhedge.org/vault/0xBF30FfE47111ae5D0a5A9F9a187EAD0170BA4D8f
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: "0x2b1d9fbbeadad547a8053119e0b8cb290c487e9d", // GMX Test 4, https://dhedge.org/vault/0x2b1d9fbbeadad547a8053119e0b8cb290c487e9d
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: "0x8A948d8D843593bF8c50eeDa5f1140846b40a95E", // GMX Test 5, https://dhedge.org/vault/0x8A948d8D843593bF8c50eeDa5f1140846b40a95E
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.gmxTestVaults.gmxTest6,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.ETHy,
        withdrawalAsset: arbitrumChainData.assets.weth,
      },
      {
        poolLogic: arbitrumChainData.torosPools.USDmny,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.SOLBULL3X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.SOLBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.SOLBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.ETHBULL4X,
        withdrawalAsset: arbitrumChainData.assets.weth,
      },
      {
        poolLogic: arbitrumChainData.torosPools.BTCBULL4X,
        withdrawalAsset: arbitrumChainData.assets.wbtc,
      },
      {
        poolLogic: arbitrumChainData.torosPools.SUIBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.SOL1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.SUI1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.DOGEBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.DOGE1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.XRP1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.HYPE1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.XRPBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.BNB1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.CRV1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.LINK1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.LINKBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.HYPEBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.CRVBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.PUMP1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.PUMPBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.BNBBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.SOLBEAR2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.XRPBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.BNBBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.DOGEBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.LINKBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.HYPEBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.SUIBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.PUMPBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.CRVBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.SUIBULL3X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.XRPBULL3X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.GOLD1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.GOLDBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.GOLDBULL3X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.GOLDBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.AAVEBEAR1X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.AAVEBULL2X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
      {
        poolLogic: arbitrumChainData.torosPools.HYPEBULL3X,
        withdrawalAsset: arbitrumChainData.assets.usdcNative,
      },
    ],
    virtualTokenResolver: [
      {
        virtualToken: "0x47904963fc8b2340414262125aF798B9655E58Cd", // virtual BTC
        virtualTokenMultiplier: BigNumber.from(10).pow(44), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 8 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: arbitrumChainData.usdPriceFeeds.btc,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: arbitrumChainData.pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43", // BTC pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0x197aa2DE1313c7AD50184234490E12409B2a1f95", // virtual SUI
        virtualTokenMultiplier: BigNumber.from(10).pow(43), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 9 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: arbitrumChainData.usdPriceFeeds.sui,
          maxAge: 90_000,
        },
        pythOracleContract: arbitrumChainData.pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744", // SUI pyth price id
          maxAge: 1500, // 1500 seconds => 25 mins
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0xC4da4c24fd591125c3F47b340b6f4f76111883d8", // virtual Doge
        virtualTokenMultiplier: BigNumber.from(10).pow(44), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 8 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: arbitrumChainData.usdPriceFeeds.dogecoin,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: arbitrumChainData.pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0xdcef50dd0a4cd2dcc17e45df1676dcb336a11a61c69df7a0299b0150c672d25c", // Doge pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0xc14e065b0067dE91534e032868f5Ac6ecf2c6868", // virtual XRP
        virtualTokenMultiplier: BigNumber.from(10).pow(46), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 6 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: arbitrumChainData.usdPriceFeeds.xrp,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: arbitrumChainData.pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0xec5d399846a9209f3fe5881d70aae9268c94339ff9817e8d18ff19fa05eea1c8", // XRP pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0xfDFA0A749dA3bCcee20aE0B4AD50E39B26F58f7C", // virtual HYPE
        virtualTokenMultiplier: BigNumber.from(10).pow(44), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 8 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: arbitrumChainData.usdPriceFeeds.hype,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: arbitrumChainData.pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0x4279e31cc369bbcc2faf022b382b080e32a8e689ff20fbc530d2a603eb6cd98b", // HYPE pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0xe5f01aeAcc8288E9838A60016AB00d7b6675900b", // virtual CRV
        virtualTokenMultiplier: BigNumber.from(10).pow(34), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 18 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: arbitrumChainData.usdPriceFeeds.crv,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: arbitrumChainData.pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0xa19d04ac696c7a6616d291c7e5d1377cc8be437c327b75adb5dc1bad745fcae8", // CRV pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0x9c060B2fA953b5f69879a8B7B81f62BFfEF360be", // virtual PUMP
        virtualTokenMultiplier: BigNumber.from(10).pow(34), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 18 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: arbitrumChainData.usdPriceFeeds.pump, // note: this onchain oracle decimals is 18, but getTokenMinMaxPrice returns price with 8 decimals
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: arbitrumChainData.pyth.priceFeedContract,
        pythOracleData: {
          priceId: arbitrumChainData.pyth.priceIds.pump, // PUMP pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0x7624cccCc59361D583F28BEC40D37e7771d2ef5D", // virtual XAUT, Tether Gold
        virtualTokenMultiplier: BigNumber.from(10).pow(34), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 18 (token decimals)
        oracleLookupType: 2, // 2 = PythLib
        onchainOracle: {
          oracleContract: ethers.constants.AddressZero,
          maxAge: 0,
        },
        pythOracleContract: arbitrumChainData.pyth.priceFeedContract,
        pythOracleData: {
          priceId: arbitrumChainData.pyth.priceIds.xaut, // XAUT pyth price id
          maxAge: 1500, // 1500 seconds => 25 mins
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
    ],
  },

  across: {
    spokePool: "0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A",
    approvedDestinations: [
      {
        sourcePool: arbitrumChainData.gmxTestVaults.gmxTest2,
        sourceToken: arbitrumChainData.assets.usdcNative,
        destinationChainId: 8453,
        destinationPool: FLAT_MONEY_PERP_MARKET_BOT_TEST,
        destinationToken: baseChainData.assets.usdc,
      },
      {
        sourcePool: arbitrumChainData.gmxTestVaults.gmxTest6,
        sourceToken: arbitrumChainData.assets.usdcNative,
        destinationChainId: 8453,
        destinationPool: FLAT_MONEY_PERP_MARKET_BOT_TEST,
        destinationToken: baseChainData.assets.usdc,
      },
      {
        sourcePool: arbitrumChainData.gmxTestVaults.gmxTest2,
        sourceToken: arbitrumChainData.assets.usdcNative,
        destinationChainId: 10,
        destinationPool: ovmChainData.flatMoneyV2Vaults.flatMoneyV2MarketMaker,
        destinationToken: ovmChainData.assets.usdcNative,
      },
    ],
  },

  pancakeswap: {
    nonfungiblePositionManager: "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
    masterChefV3: "0x5e09ACf80C0296740eC5d6F643005a4ef8DaA694",
  },

  flatMoneyOptions: {
    orderAnnouncementModule: "0x2326BB21B769D81E134C9b305ca156f989249fE7",
    orderExecutionModule: "0x7e50AD6E467D9FAFC3B4BFd003247cEaA2F17e5b",
    flatcoinVault: "0x29fAD9d44C550e5D8081AB35763797B39d75b858",
    whitelistedVaultsForLP: [
      {
        poolLogic: "0x3696652233468ab827e5af5155a9f2a0c07682c4", // Test Vault
        withdrawalAsset: arbitrumChainData.assets.wbtc,
      },
      {
        poolLogic: arbitrumChainData.torosPools.BTCHOSRTVOL,
        withdrawalAsset: arbitrumChainData.assets.wbtc,
      },
      {
        poolLogic: arbitrumChainData.torosPools.BTCCOVCALL,
        withdrawalAsset: arbitrumChainData.assets.wbtc,
      },
    ],
    collateral: arbitrumChainData.assets.wbtc,
  },

  odosV2RouterAddress: arbitrumChainData.odosEx.v2Router,

  odosV3RouterAddress: "0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05",

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: arbitrumChainData.assets.usdcNative,
    authorizedKeeperAddresses: [
      "0xfF5C66B0799bb1cD834e2178866225F020A87A7f",
      "0xD411D209d3C602bdB7F99A16775A2e30aEb51009",
      "0xc804F6F95973f3380D8f52fd7aFF475337e2eea2",
      "0x83336A07e2257c537EfcA180E9c89819fa40ECCd",
      "0xfB2f4AE9584c82d3dB9Cd00B5CB664c8cf44470B",
    ],
  },

  fluid: {
    merkleDistributor: "0x94312a608246Cecfce6811Db84B3Ef4B2619054E",
  },

  angleProtocol: {
    distributor: "0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae",
    rewardTokenSupported: [
      {
        token: "0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8", // aArbWETH
        tokenType: 2,
      },
      {
        token: "0x513c7E3a9c69cA3e22550eF58AC1C0088e918FFf", // aArbwstETH
        tokenType: 2,
      },
      {
        token: "0x6533afac2E7BCCB20dca161449A13A32D391fb00", // aArbARB
        tokenType: 2,
      },
      {
        token: arbitrumChainData.assets.arb,
        tokenType: 1,
      },
      {
        token: "0x2c63f9da936624Ac7313b972251D340260A4bF08", // Wrapped aArbARB
        tokenType: 3,
      },
    ],
  },

  kyberSwap: {
    routerV2: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
  },

  rewardAssetSetting: [
    {
      rewardToken: arbitrumChainData.assets.wsteth, // wstETH
      linkedAssetTypes: [],
      linkedAssets: [
        "0x71fBF40651E9D4278a74586AfC99F307f369Ce9A", // PT-wstETH-25JUN2026
      ],
    },
  ],

  pendle: {
    pendleRouterV4: "0x888888888889758F76e7103c6CbF23ABbF58F946",
    knownMarkets: [
      "0xf78452e0f5C0B95fc5dC8353B8CD1e06E53fa25B", // wstETH-25JUN2026
    ],
    yieldContractFactory: "0xFF29e023910FB9bfc86729c1050AF193A45a0C0c",
    staticRouter: "0xAdB09F65bd90d19e3148D9ccb693F3161C6DB3E8",
  },

  dytm: {
    dytmOffice: arbitrumChainData.dytm.dytmOffice,
    dytmPeriphery: arbitrumChainData.dytm.dytmPeriphery,
    accountSplitterAndMerger: arbitrumChainData.dytm.accountSplitterAndMerger,
    whitelistedPools: [arbitrumChainData.dytmTestVaults.DYTMTesting2, arbitrumChainData.dytmTestVaults.DYTMTesting3],
    whitelistedMarkets: [
      1, // for testing
    ],
    maxDytmMarkets: 1,
    mismatchDeltaNumerator: 5, // 0.05% allowed mismatch
  },

  easyLimitBuyManager: {
    permit2: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
    authorizedKeeperAddresses: [
      "0xFBFE87a8665cE77e4F1f47d0256b7e68Be966498",
      "0xBA2A62aFAfC662afbE5C726910C101225aDeF591",
      "0x4C6ced5164042150A63Cd7610af3Efc7fF2fe4B6",
      "0x3D8D80d65EF8df009AF576dF44d4d06bf39A94DF",
    ],
  },
};

export const arbitrumProdFileNames: IFileNames = {
  versionsFileName: "./publish/arbitrum/prod/versions.json",
  assetsFileName: "./config/arbitrum/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/arbitrum/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/arbitrum/dHEDGE Governance Contract Guards.csv",
  governanceNamesFileName: "./config/arbitrum/dHEDGE Governance Names.csv",
  deprecatedContractGuardsFileName: "./config/arbitrum/dHEDGE Deprecated Contract Guards.csv",
} as const;
