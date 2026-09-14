import { ethers } from "ethers";

import { IAddresses, IFileNames } from "../types";

// For protocol upgrades
const protocolDao = "0x5a76f841bFe5182f04bf511fC0Ecf88C27189FCB";
// For protocol fees
const protocolTreasury = "0xfF44B48abad9cb7A2485f829E5c9A4d1cee623c9";
// Should be fetched from the oz file
const proxyAdmin = "0xad17E5020954eB3c6d77be9DCDF9DBAB44EdD16E";

export const assets = {
  weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
};

const torosPools = {
  BTCBULL3X: "0x778176Be78245808BB4572Dd86B9B796213E5992",
  ETHBULL3X: "0xcE09FAD0dd5e70041402dF947aB3ECF8E430Becb",
  BTCBULL2X: "0x447b12841ed275636a7719d162D2Df379Cc81152",
  ETHBULL2X: "0x907BD45742D811Ad535d2445185E73bc367751d1",
  GOLDBULL2X: "0x6FCB08c5f8A69cc8C663BB4a2FaAAD017631577F",
  GOLDBULL3X: "0x74A60dAE44DedA8e6C6445Cbbb067097e08b682c",
  BTCBEAR1X: "0x6316eBe9DFA8DE65A39af8bfD2523146b3c3239F",
  ETHBEAR1X: "0xbc176E9CaDa297c7B7142dd7447Bb114ad90d143",
  ETH1X: "0xf91706c1B55CE14AA8e89260E1F1734BbF41dD5F",
  BTC1X: "0x74DEa818734caD7Ca485D47be2742F3c464b84f0",
  SP500BULL1X: "0x3587750815461057E4d97a2C11338063A75F2b9B", // S&P 500 Bull 1X — https://chamberfi.com/vault/0x3587750815461057E4d97a2C11338063A75F2b9B
  SP500BULL2X: "0x4c930125d360Cb429E225666C01C00220d0112F1", // S&P 500 Bull 2X — https://chamberfi.com/vault/0x4c930125d360Cb429E225666C01C00220d0112F1
  SP500BULL3X: "0xcEDF80d23A80Bd7c88BFc73bfB8fd988D477ddd6", // S&P 500 Bull 3X — https://chamberfi.com/vault/0xcEDF80d23A80Bd7c88BFc73bfB8fd988D477ddd6
  NVDABULL1X: "0xfBecA8B134aC99b12f573410133512b15d1e319a", // Nvidia Bull 1X — https://chamberfi.com/vault/0xfBecA8B134aC99b12f573410133512b15d1e319a
  NVDABULL2X: "0xC237cDdeD5b4882b212436e9BBfa84b79629801a", // Nvidia Bull 2X — https://chamberfi.com/vault/0xC237cDdeD5b4882b212436e9BBfa84b79629801a
  MUBULL1X: "0x1B4EF8d297AF9C0fe968D40A376d9aBBec3B440B", // Micron Bull 1X — https://chamberfi.com/vault/0x1B4EF8d297AF9C0fe968D40A376d9aBBec3B440B
  MUBULL2X: "0x16C449F0725Ab5029F074A18BF7ff7696cF8E2b1", // Micron Bull 2X — https://chamberfi.com/vault/0x16C449F0725Ab5029F074A18BF7ff7696cF8E2b1
  IRENBULL1X: "0xf8F7EDA0BAAcD3701E2c583a6207E099C9C625A7", // IREN Bull 1X — https://chamberfi.com/vault/0xf8F7EDA0BAAcD3701E2c583a6207E099C9C625A7
  IRENBULL2X: "0x0d2341b20579EDB51e78Dc93bE537feAc5C3BdDB", // IREN Bull 2X — https://chamberfi.com/vault/0x0d2341b20579EDB51e78Dc93bE537feAc5C3BdDB
  STRCBULL1X: "0x32A97d1B619E96584e786B6D350f06043757c279", // Strategy STRC Preferred Bull 1X — https://chamberfi.com/vault/0x32A97d1B619E96584e786B6D350f06043757c279
  STRCBULL2X: "0xE25Fb378b2d98e6320CAc3b32DcFF2B2AE710879", // Strategy STRC Preferred Bull 2X — https://chamberfi.com/vault/0xE25Fb378b2d98e6320CAc3b32DcFF2B2AE710879
  AMATBULL1X: "0x3407C0AB7C48717900895DD20252d7e0A75a3f12", // Applied Materials Bull 1X — https://chamberfi.com/vault/0x3407C0AB7C48717900895DD20252d7e0A75a3f12
  AMATBULL2X: "0x98Fdd7fD03CbA362B54bCD2d5CB309A3E10df53d", // Applied Materials Bull 2X — https://chamberfi.com/vault/0x98Fdd7fD03CbA362B54bCD2d5CB309A3E10df53d
  SPCXBULL1X: "0x7e29a04739362172f98E983D68b47679997baD53", // SpaceX Bull 1X — https://chamberfi.com/vault/0x7e29a04739362172f98E983D68b47679997baD53
  SPCXBULL2X: "0x1E0adCFDd0F2CfF7C5CcA916503622a815740c05", // SpaceX Bull 2X — https://chamberfi.com/vault/0x1E0adCFDd0F2CfF7C5CcA916503622a815740c05
};

const dytm = {
  dytmOffice: "0x0ff1ceB93DbADfB13722058D60c4B8cD122b06ea",
  dytmPeriphery: "0xfA03F9Ce907006133a0E77796a31c40AC22151d5",
  accountSplitterAndMerger: "0x2439089A93eedc9f7fFfbc8CD32b85143D0E591C",
};

const dytmWhitelistedVaults = {
  DYTMMainnetTesting1: "0x89163E4Cd81619019e22e8a62f0c96D86c89C984", // https://chamberfi.com/vault/0x89163E4Cd81619019e22e8a62f0c96D86c89C984
};

export const ondoHyperliquidMarketMaking = {
  ondoVault: "0x66bb96e6587247862433FEA40E1ef59145c91976", // Ondo <-> Hyperliquid — https://chamberfi.com/vault/0x66bb96e6587247862433FEA40E1ef59145c91976
  ondoVault2: "0xc34912598a7471fbFf03C74D5138baDF96FBb1F3", // Ondo <-> Hyperliquid 2 — https://chamberfi.com/vault/0xc34912598a7471fbFf03C74D5138baDF96FBb1F3
  ondoVault3: "0x6fa2B89A386d74dbAcdC1fB6dE18F55385c7bd07", // Ondo <-> Hyperliquid 3 — https://chamberfi.com/vault/0x6fa2B89A386d74dbAcdC1fB6dE18F55385c7bd07
};

export const ethereumProdData: IAddresses = {
  protocolDaoAddress: protocolDao,
  protocolTreasuryAddress: protocolTreasury,
  proxyAdminAddress: proxyAdmin,

  v2RouterAddresses: [
    "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Uniswap V2 Router
    "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F", // SushiSwap V2 Router
  ],

  superSwapper: {
    routeHints: [],
  },

  assets: {
    nativeAssetWrapper: assets.weth,
    usdc: assets.usdc,
  },

  oneInchV6RouterAddress: "0x111111125421cA6dc452d289314280a0f8842A65",

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 1e5, // 10%
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      torosPools.BTCBULL3X,
      torosPools.ETHBULL3X,
      torosPools.BTCBULL2X,
      torosPools.ETHBULL2X,
      torosPools.GOLDBULL2X,
      torosPools.GOLDBULL3X,
      torosPools.BTCBEAR1X,
      torosPools.ETHBEAR1X,
      torosPools.ETH1X,
      torosPools.BTC1X,
      torosPools.SP500BULL1X,
      torosPools.SP500BULL2X,
      torosPools.SP500BULL3X,
      torosPools.NVDABULL1X,
      torosPools.NVDABULL2X,
      torosPools.MUBULL1X,
      torosPools.MUBULL2X,
      torosPools.IRENBULL1X,
      torosPools.IRENBULL2X,
      torosPools.STRCBULL1X,
      torosPools.STRCBULL2X,
      torosPools.AMATBULL1X,
      torosPools.AMATBULL2X,
      torosPools.SPCXBULL1X,
      torosPools.SPCXBULL2X,
    ],
  },

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: assets.usdc,
    authorizedKeeperAddresses: [
      "0x99c9F65a486C0567495ec58722916c73292D585f",
      "0xC0F49445a9B8A60778EF8bCa99059Ceabb066e19",
      "0x962976AA38665fc59B2F981C2457a6f95fFB2aD5",
      "0x5048d4630c51d02A281Cb77E63a1A3af4Fd8dc33",
    ],
  },

  pendle: {
    pendleRouterV4: "0x888888888889758F76e7103c6CbF23ABbF58F946",
    knownMarkets: [
      "0x9C560eBaF78e596cbcC27411d633a74D628dd7dC", // sUSDS-26NOV2026
    ],
    yieldContractFactory: "0x35A338522a435D46f77Be32C70E215B813D0e3aC",
    staticRouter: "0x263833d47eA3fA4a30f269323aba6a107f9eB14C",
  },

  uniV2: {
    factory: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
  },

  uniV3: {
    uniswapV3FactoryAddress: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    uniswapV3RouterAddress: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
  },

  flatMoney: {
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
  },

  aaveV3: {
    aaveLendingPoolAddress: "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
  },

  rewardAssetSetting: [
    {
      rewardToken: "0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD", // sUSDS
      linkedAssetTypes: [],
      linkedAssets: [
        "0xdC169AbE56461A2E0c034Da431Ac2a3ebf596094", // PT-sUSDS-26NOV2026
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

  ondo: {
    gmTokenManager: "0x2c158BC456e027b2AfFCCadF1BDBD9f5fC4c5C8c",
    attestationOracle: {
      allowedUserId: "0x474d000000000000b50d13795402932300000000000000000000000000000000",
      maxProofAge: 24 * 60 * 60, // 24 hours
      sanityDeviationBps: 1000, // 10%
      minQuoteValue: ethers.utils.parseEther("10").toString(), // $10
      maxQuoteValue: ethers.utils.parseEther("10000").toString(), // $10,000
    },
    ondoGMSwapContractGuard: {
      maxSlippagePerSwapBps: 500, // 5%
    },
    ondoGMTokenAssetGuard: {
      mismatchDeltaNumerator: 5, // 0.05%
      // Skip the redeem when a depositor's GM portion is worth less than this. Set above
      // Ondo's ~$1 attestation-swap minimum to absorb oracle-vs-attestation price drift.
      minRedeemValue: ethers.utils.parseEther("1.1").toString(), // $1.10
    },
    ondoGMSwap: {
      // Non-pool OndoGMSwap callers.
      authorizedCallers: [
        "0x159d5cE26dBDCB1f2e34EC5C689f9411De0C85FE", // DytmWithdrawProcessor
      ],
    },
  },

  midas: {
    depositVault: "0xc21511EDd1E6eCdc36e8aD4c82117033e50D5921", // mAPOLLO DepositVault
    redemptionVault: "0x5aeA6D35ED7B3B7aE78694B7da2Ee880756Af5C0", // mAPOLLO RedemptionVaultWithSwapper
    whitelistedPools: [
      "0x80B119f36f81032cd87C182AdC2b0145D901bA8b", // test vault
      "0xfec2adfa296fe189f53089fd5ccd8c28dd559cf2", // mStable
    ],
  },

  dytm: {
    dytmOffice: dytm.dytmOffice,
    dytmPeriphery: dytm.dytmPeriphery,
    accountSplitterAndMerger: dytm.accountSplitterAndMerger,
    whitelistedPools: [
      dytmWhitelistedVaults.DYTMMainnetTesting1,
      torosPools.SP500BULL2X,
      torosPools.SP500BULL3X,
      torosPools.NVDABULL2X,
      torosPools.MUBULL2X,
      torosPools.IRENBULL2X,
      torosPools.STRCBULL2X,
      torosPools.AMATBULL2X,
      torosPools.SPCXBULL2X,
    ],
    whitelistedMarkets: [
      1, // for testing
    ],
    maxDytmMarkets: 1,
    mismatchDeltaNumerator: 5, // 0.05% allowed mismatch
  },
  across: {
    spokePool: "0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5", // Across SpokePool on Ethereum
  },
};

export const ethereumProdFileNames: IFileNames = {
  versionsFileName: "./publish/ethereum/prod/versions.json",
  assetsFileName: "./config/ethereum/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/ethereum/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/ethereum/dHEDGE Governance Contract Guards.csv",
  deprecatedContractGuardsFileName: "./config/ethereum/dHEDGE Deprecated Contract Guards.csv",
} as const;
