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
    maxCumulativeSlippage: 1e5, // 10%
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      ethereumChainData.torosPools.BTCBULL3X,
      ethereumChainData.torosPools.ETHBULL3X,
      ethereumChainData.torosPools.BTCBULL2X,
      ethereumChainData.torosPools.ETHBULL2X,
      ethereumChainData.torosPools.GOLDBULL2X,
      ethereumChainData.torosPools.GOLDBULL3X,
      ethereumChainData.torosPools.BTCBEAR1X,
      ethereumChainData.torosPools.ETHBEAR1X,
      ethereumChainData.torosPools.ETH1X,
      ethereumChainData.torosPools.BTC1X,
    ],
  },

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: ethereumChainData.assets.usdc,
    authorizedKeeperAddresses: [
      "0xfF5C66B0799bb1cD834e2178866225F020A87A7f",
      "0xD411D209d3C602bdB7F99A16775A2e30aEb51009",
      "0xc804F6F95973f3380D8f52fd7aFF475337e2eea2",
      "0x83336A07e2257c537EfcA180E9c89819fa40ECCd",
      "0xfB2f4AE9584c82d3dB9Cd00B5CB664c8cf44470B",
    ],
  },

  pendle: {
    pendleRouterV4: "0x888888888889758F76e7103c6CbF23ABbF58F946",
    knownMarkets: [
      "0x9Df192D13D61609D1852461c4850595e1F56E714", // USDe-31JUL2025
      "0x4339Ffe2B7592Dc783ed13cCE310531aB366dEac", // sUSDE-31JUL2025
      "0x6d98a2b6CDbF44939362a3E99793339Ba2016aF4", // USDe-25SEP2025
      "0xA36b60A14A1A5247912584768C6e53E1a269a9F7", // sUSDE-25SEP2025
      "0x4eaA571EaFCD96f51728756BD7F396459BB9B869", // USDe-27NOV2025
      "0xb6aC3d5da138918aC4E84441e924a20daA60dBdd", // sUSDE-27NOV2025
      "0xAADBC004DAcF10e1fdbd87ca1a40ecAF77CC5B02", // USDe-05FEB2026
      "0xed81f8bA2941C3979de2265C295748a6b6956567", // sUSDe-05FEB2026
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

  odosV3RouterAddress: "0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05",

  rewardAssetSetting: [
    {
      rewardToken: ethereumChainData.assets.usde,
      linkedAssetTypes: [],
      linkedAssets: [
        "0x917459337CaAC939D41d7493B3999f571D20D667", // PT-USDe-31JUL2025
        "0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a", // PT-USDe-25SEP2025
        "0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7", // PT-USDe-27NOV2025
        "0x1f84a51296691320478c98b8d77f2bbd17d34350", // PT-USDe-05FEB2026
      ],
    },
    {
      rewardToken: ethereumChainData.assets.susde,
      linkedAssetTypes: [],
      linkedAssets: [
        "0x3b3fB9C57858EF816833dC91565EFcd85D96f634", // PT-sUSDe-31JUL2025
        "0x9F56094C450763769BA0EA9Fe2876070c0fD5F77", // PT-sUSDE-25SEP2025
        "0xe6A934089BBEe34F832060CE98848359883749B3", // PT-sUSDe-27NOV2025
        "0xe8483517077afa11a9b07f849cee2552f040d7b2", // PT-sUSDe-05FEB2026
      ],
    },
  ],

  kyberSwap: {
    routerV2: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
  },

  angleProtocol: {
    distributor: "0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae",
    rewardTokenSupported: [
      {
        token: "0x3a4de44B29995a3D8Cd02d46243E1563E55bCc8b", // Wrapped aUSDe
        tokenType: 3,
      },
    ],
  },
};

export const ethereumProdFileNames: IFileNames = {
  versionsFileName: "./publish/ethereum/prod/versions.json",
  assetsFileName: "./config/ethereum/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/ethereum/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/ethereum/dHEDGE Governance Contract Guards.csv",
} as const;
