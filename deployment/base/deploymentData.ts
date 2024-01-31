import { baseChainData } from "../../config/chainData/baseData";
import { IAddresses } from "../types";

export const baseProdData: IAddresses = {
  protocolDaoAddress: baseChainData.dHEDGE.daoMultisig,
  protocolTreasuryAddress: baseChainData.dHEDGE.treasury,
  proxyAdminAddress: baseChainData.proxyAdmin,

  // Gnosis safe multicall/send address
  // https://github.com/gnosis/safe-deployments
  gnosisMultiSendAddress: "0x998739BFdAAdde7C933B942a68053933098f9EDa",
  gnosisApi: "https://safe-transaction-base.safe.global",

  easySwapperConfig: {
    customLockupAllowedPools: [], // Add here Toros pools on Base
    feeByPassManagers: ["0x5619AD05b0253a7e647Bd2E4C01c7f40CEaB0879"], // Add here Toros manager address on Base
    feeNumerator: 10,
    feeDenominator: 10000,
  },

  v2RouterAddresses: [],

  superSwapper: {
    routeHints: [], // Add here what hints we will need for Base
  },

  assets: {
    nativeAssetWrapper: baseChainData.assets.weth,
    weth: baseChainData.assets.weth,
    dai: baseChainData.assets.dai,
  },

  uniV3: {
    uniswapV3FactoryAddress: baseChainData.uniswapV3.factory,
    uniswapV3RouterAddress: baseChainData.uniswapV3.swapRouter,
  },

  oneInchV5RouterAddress: baseChainData.oneInch.v5Router,

  velodrome: {
    factoryV2: baseChainData.velodromeV2.factory,
    routerV2: baseChainData.velodromeV2.router,
  },

  zeroExExchangeProxy: baseChainData.zeroEx.exchangeProxy,

  synthetixV3: {
    core: baseChainData.synthetixV3.core,
    dHedgeVaultsWhitelist: [
      {
        poolLogic: "0xE404FA05a4298dC657EA826ddAEec8BD630e414A",
        collateralAsset: baseChainData.assets.susdc,
        debtAsset: baseChainData.assets.snxUSD,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: "0xC1E02884AF4A283cA25ab63C45360d220d69DA52",
        collateralAsset: baseChainData.assets.susdc,
        debtAsset: baseChainData.assets.snxUSD,
        snxLiquidityPoolId: 1,
      },
    ],
    spotMarket: baseChainData.synthetixV3.spotMarket,
    allowedMarkets: [
      {
        marketId: 1,
        collateralSynth: baseChainData.assets.susdc,
        collateralAsset: baseChainData.assets.usdc,
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
  },
};

export const baseProdFileNames = {
  versionsFileName: "./publish/base/prod/versions.json",
  assetsFileName: "./config/base/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/base/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/base/dHEDGE Governance Contract Guards.csv",
  governanceNamesFileName: "./config/base/dHEDGE Governance Names.csv",
} as const;
