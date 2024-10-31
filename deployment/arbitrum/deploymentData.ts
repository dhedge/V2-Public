import { BigNumber } from "ethers";
import { arbitrumChainData } from "../../config/chainData/arbitrumData";
import { IAddresses } from "../types";

export const arbitrumProdData: IAddresses = {
  protocolDaoAddress: arbitrumChainData.dHEDGE.daoMultisig,
  protocolTreasuryAddress: arbitrumChainData.dHEDGE.treasury,
  proxyAdminAddress: arbitrumChainData.proxyAdmin,

  // Gnosis safe multicall/send address
  // https://github.com/gnosis/safe-deployments
  gnosisMultiSendAddress: "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761",
  gnosisApi: "https://safe-transaction-arbitrum.safe.global",

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
    aaveProtocolDataProviderAddress: arbitrumChainData.aaveV3.protocolDataProvider,
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
    maxCumulativeSlippage: 125e3, // 12.5%
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
      percent: BigNumber.from(10).pow(17), // 10%
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
    ],
  },

  rewardAssetSetting: [
    {
      rewardToken: arbitrumChainData.assets.arb,
      linkedAssetTypes: [
        29, //   "Ramses CL NFT Position Asset" = 29,
      ],
      underlyingAssetType: 4, //   "Lending Enable Asset" = 4,
    },
  ],
};

export const arbitrumProdFileNames = {
  versionsFileName: "./publish/arbitrum/prod/versions.json",
  assetsFileName: "./config/arbitrum/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/arbitrum/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/arbitrum/dHEDGE Governance Contract Guards.csv",
  governanceNamesFileName: "./config/arbitrum/dHEDGE Governance Names.csv",
  deprecatedContractGuardsFileName: "./config/arbitrum/dHEDGE Deprecated Contract Guards.csv",
} as const;
