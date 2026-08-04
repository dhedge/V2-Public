import { ethers } from "ethers";

import { ethereumChainData } from "../../config/chainData/ethereumData";
import { hyperevmChainData } from "../../config/chainData/hyperevmData";
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
    usdc: ethereumChainData.assets.usdc,
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
      ethereumChainData.torosPools.SP500BULL1X,
      ethereumChainData.torosPools.SP500BULL2X,
      ethereumChainData.torosPools.SP500BULL3X,
      ethereumChainData.torosPools.NVDABULL1X,
      ethereumChainData.torosPools.NVDABULL2X,
      ethereumChainData.torosPools.MUBULL1X,
      ethereumChainData.torosPools.MUBULL2X,
      ethereumChainData.torosPools.IRENBULL1X,
      ethereumChainData.torosPools.IRENBULL2X,
      ethereumChainData.torosPools.STRCBULL1X,
      ethereumChainData.torosPools.STRCBULL2X,
      ethereumChainData.torosPools.AMATBULL1X,
      ethereumChainData.torosPools.AMATBULL2X,
      ethereumChainData.torosPools.SPCXBULL1X,
      ethereumChainData.torosPools.SPCXBULL2X,
    ],
  },

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: ethereumChainData.assets.usdc,
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
      "0x50DCE085af29CABa28f7308beA57C4043757b491", // apxUSD-18JUN2026
      "0xaf0349FB9B1bA07D34381870c59b560b31412660", // apxUSD-05NOV2026
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

  rewardAssetSetting: [
    {
      rewardToken: "0x98A878b1Cd98131B271883B390f68D2c90674665", // apxUSD
      linkedAssetTypes: [],
      linkedAssets: [
        "0x92a6A01B07984de46c24E8EBa248449beB8B1dCB", // PT-apxUSD-18JUN2026
        "0xAF687B5EcB525Ccea96115088999B4eD80C388b6", // PT-apxUSD-05NOV2026
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
    dytmOffice: ethereumChainData.dytm.dytmOffice,
    dytmPeriphery: ethereumChainData.dytm.dytmPeriphery,
    accountSplitterAndMerger: ethereumChainData.dytm.accountSplitterAndMerger,
    whitelistedPools: [
      ethereumChainData.dytmWhitelistedVaults.DYTMMainnetTesting1,
      ethereumChainData.torosPools.SP500BULL2X,
      ethereumChainData.torosPools.SP500BULL3X,
      ethereumChainData.torosPools.NVDABULL2X,
      ethereumChainData.torosPools.MUBULL2X,
      ethereumChainData.torosPools.IRENBULL2X,
      ethereumChainData.torosPools.STRCBULL2X,
      ethereumChainData.torosPools.AMATBULL2X,
      ethereumChainData.torosPools.SPCXBULL2X,
    ],
    whitelistedMarkets: [
      1, // for testing
    ],
    maxDytmMarkets: 1,
    mismatchDeltaNumerator: 5, // 0.05% allowed mismatch
  },
  across: {
    spokePool: "0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5", // Across SpokePool on Ethereum
    approvedDestinations: [
      {
        sourcePool: ethereumChainData.ondoHyperliquidMarketMaking.ondoVault,
        sourceToken: ethereumChainData.assets.usdc,
        destinationChainId: 999, // HyperEVM
        destinationPool: hyperevmChainData.ondoHyperliquidMarketMaking.hyperApiWalletVault,
        destinationToken: hyperevmChainData.assets.usdc,
      },
      {
        sourcePool: ethereumChainData.ondoHyperliquidMarketMaking.ondoVault2,
        sourceToken: ethereumChainData.assets.usdc,
        destinationChainId: 999, // HyperEVM
        destinationPool: hyperevmChainData.ondoHyperliquidMarketMaking.hyperApiWalletVault2,
        destinationToken: hyperevmChainData.assets.usdc,
      },
      {
        sourcePool: ethereumChainData.ondoHyperliquidMarketMaking.ondoVault3,
        sourceToken: ethereumChainData.assets.usdc,
        destinationChainId: 999, // HyperEVM
        destinationPool: hyperevmChainData.ondoHyperliquidMarketMaking.hyperApiWalletVault3,
        destinationToken: hyperevmChainData.assets.usdc,
      },
    ],
  },
};

export const ethereumProdFileNames: IFileNames = {
  versionsFileName: "./publish/ethereum/prod/versions.json",
  assetsFileName: "./config/ethereum/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/ethereum/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/ethereum/dHEDGE Governance Contract Guards.csv",
  deprecatedContractGuardsFileName: "./config/ethereum/dHEDGE Deprecated Contract Guards.csv",
} as const;
