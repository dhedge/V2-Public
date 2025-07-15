import { ethereumChainData } from "../../config/chainData/ethereumData";
import { IAddresses, IFileNames } from "../types";

export const ethereumProdData: IAddresses = {
  protocolDaoAddress: ethereumChainData.protocolDao,
  protocolTreasuryAddress: ethereumChainData.protocolTreasury,
  proxyAdminAddress: ethereumChainData.proxyAdmin,

  v2RouterAddresses: [
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Uniswap V2 Router
    "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // SushiSwap V2 Router
  ],

  superSwapper: {
    routeHints: [],
  },

  assets: {
    nativeAssetWrapper: ethereumChainData.assets.weth,
    weth: ethereumChainData.assets.weth,
  },

  oneInchV6RouterAddress: ethereumChainData.oneInch.v6Router,

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 5e4, // 5%
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [],
  },

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: ethereumChainData.assets.usdc,
    authorizedKeeperAddresses: [],
  },

  pendle: {
    pendleRouterV4: "0x888888888889758F76e7103c6CbF23ABbF58F946",
    marketFactoryV3: "0x6fcf753f2C67b83f7B09746Bbc4FA0047b35D050",
    knownMarkets: [
      "0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4", // USDe-25SEP2025
      "0xA36b60A14A1A5247912584768C6e53E1a269a9F7", // sUSDE-25SEP2025
      "0x9Df192D13D61609D1852461c4850595e1F56E714", // USDe-31JUL2025
      "0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac", // sUSDE-31JUL2025
    ],
    yieldContractFactory: "0x35A338522a435D46f77Be32C70E215B813D0e3aC",
    staticRouter: "0x263833d47eA3fA4a30f269323aba6a107f9eB14C",
  },

  uniV2: {
    factory: ethereumChainData.uniswapV2.factory,
  },

  uniV3: {
    uniswapV3FactoryAddress: ethereumChainData.uniswapV3.factory,
    uniswapV3RouterAddress: ethereumChainData.uniswapV3.router,
  },

  flatMoney: {
    swapper: ethereumChainData.swapper,
  },

  aaveV3: {
    aaveLendingPoolAddress: ethereumChainData.aaveV3.lendingPool,
  },

  odosV2RouterAddress: "0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559",

  rewardAssetSetting: [
    {
      rewardToken: ethereumChainData.assets.usde,
      linkedAssetTypes: [],
      linkedAssets: ["0x917459337CaAC939D41d7493B3999f571D20D667", "0xbc6736d346a5ebc0debc997397912cd9b8fae10a"], // PTs for USDe
    },
    {
      rewardToken: ethereumChainData.assets.susde,
      linkedAssetTypes: [],
      linkedAssets: ["0x3b3fB9C57858EF816833dC91565EFcd85D96f634", "0x9F56094C450763769BA0EA9Fe2876070c0fD5F77"], // PTs for sUSDe
    },
  ],
};

export const ethereumProdFileNames: IFileNames = {
  versionsFileName: "./publish/ethereum/prod/versions.json",
  assetsFileName: "./config/ethereum/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/ethereum/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/ethereum/dHEDGE Governance Contract Guards.csv",
} as const;
