import { ethereumChainData } from "../../config/chainData/ethereumData";
import { hyperevmChainData } from "../../config/chainData/hyperevmData";
import { IAddresses, IFileNames } from "../types";

const protocolDaoAddress = "0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100";

const TOROS_VAULTS = {
  SP500BULL2X: "0xb360401bAeBE769aAEDF0212cb1ad6Fd8430A282",
  NVDABULL2X: "0xc722466CFc5bc7E7cc6e01A984621900376c5FfF",
  NVDABULL3X: "0x46F34e200Aa5a1a220B74E5d28665CC3CFCC739a",
  SP500BULL3X: "0xf1bBA105ee5Eb20129A943ab23ba1FaEaeF6b947",
  GOLDBULL3X: "0x6379297d251535BD4497C90d001787b53603CCA1",
  GOLDBULL2X: "0xEe55e2Df9a98ABC3F9a2f40FA96279742b1858bE",
  SLVBULL2X: "0x0AC8D6A003De1869d450216116736ae4B8b4F471",
  SLVBULL3X: "0xa8B3f14d88593e1B5460654cF8eCdaf6d47165A9",
  NDXBULL2X: "0xBc8124fa384247dF4E6f3EA2548bb78aB4bA9Fe4",
  NDXBULL3X: "0xBDb2a2641d8E291437e244c08e4433A13796E8dE",
};

const assets = {
  usdc: "0xb88339CB7199b77E23DB6E890353E22632Ba630f",
};

export const hyperevmProdData: IAddresses = {
  protocolDaoAddress,
  protocolTreasuryAddress: "0xEE27793EBAf6a446c74C2cDd23Bba615e9472264",
  proxyAdminAddress: "0xD2d91d3cA66E15598181562654D4727355a31E4b",

  hyperliquid: {
    admin: protocolDaoAddress,
    maxSlippage: "30000000000000000", // 3% max slippage for all trades (0.03e18)
    whitelistedVaults: [],
    apiWalletEnabledPools: [
      hyperevmChainData.ondoHyperliquidMarketMaking.hyperApiWalletVault,
      hyperevmChainData.ondoHyperliquidMarketMaking.hyperApiWalletVault2,
      hyperevmChainData.ondoHyperliquidMarketMaking.hyperApiWalletVault3,
    ],
  },

  assets: {
    nativeAssetWrapper: "0x5555555555555555555555555555555555555555",
  },

  flatMoney: {
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      TOROS_VAULTS.SP500BULL2X,
      TOROS_VAULTS.NVDABULL2X,
      TOROS_VAULTS.NVDABULL3X,
      TOROS_VAULTS.SP500BULL3X,
      TOROS_VAULTS.GOLDBULL3X,
      TOROS_VAULTS.GOLDBULL2X,
      TOROS_VAULTS.SLVBULL2X,
      TOROS_VAULTS.SLVBULL3X,
      TOROS_VAULTS.NDXBULL2X,
      TOROS_VAULTS.NDXBULL3X,
    ],
  },

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  kyberSwap: {
    routerV2: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
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
  across: {
    spokePool: "0x35E63eA3eb0fb7A3bc543C71FB66412e1F6B0E04", // Across SpokePool on HyperEVM
    approvedDestinations: [
      {
        sourcePool: hyperevmChainData.ondoHyperliquidMarketMaking.hyperApiWalletVault,
        sourceToken: hyperevmChainData.assets.usdc,
        destinationChainId: 1, // Ethereum
        destinationPool: ethereumChainData.ondoHyperliquidMarketMaking.ondoVault,
        destinationToken: ethereumChainData.assets.usdc,
      },
      {
        sourcePool: hyperevmChainData.ondoHyperliquidMarketMaking.hyperApiWalletVault2,
        sourceToken: hyperevmChainData.assets.usdc,
        destinationChainId: 1, // Ethereum
        destinationPool: ethereumChainData.ondoHyperliquidMarketMaking.ondoVault2,
        destinationToken: ethereumChainData.assets.usdc,
      },
      {
        sourcePool: hyperevmChainData.ondoHyperliquidMarketMaking.hyperApiWalletVault3,
        sourceToken: hyperevmChainData.assets.usdc,
        destinationChainId: 1, // Ethereum
        destinationPool: ethereumChainData.ondoHyperliquidMarketMaking.ondoVault3,
        destinationToken: ethereumChainData.assets.usdc,
      },
    ],
  },
} as const;

export const hyperevmProdFileNames: IFileNames = {
  versionsFileName: "./publish/hyperevm/prod/versions.json",
  assetsFileName: "./config/hyperevm/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/hyperevm/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/hyperevm/dHEDGE Governance Contract Guards.csv",
  approvedPerpsFileName: "./config/hyperevm/dHEDGE Approved Perps.json",
} as const;
