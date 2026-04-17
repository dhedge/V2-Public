import { IAddresses, IFileNames } from "../types";

const protocolDaoAddress = "0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100";

export const hyperevmProdData: IAddresses = {
  protocolDaoAddress,
  protocolTreasuryAddress: "0xEE27793EBAf6a446c74C2cDd23Bba615e9472264",
  proxyAdminAddress: "0xD2d91d3cA66E15598181562654D4727355a31E4b",

  hyperliquid: {
    admin: protocolDaoAddress,
    maxSlippage: "30000000000000000", // 3% max slippage for all trades (0.03e18)
    whitelistedVaults: [],
  },

  assets: {
    nativeAssetWrapper: "0x5555555555555555555555555555555555555555",
  },

  flatMoney: {
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [],
  },

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  kyberSwap: {
    routerV2: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
  },
} as const;

export const hyperevmProdFileNames: IFileNames = {
  versionsFileName: "./publish/hyperevm/prod/versions.json",
  assetsFileName: "./config/hyperevm/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/hyperevm/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/hyperevm/dHEDGE Governance Contract Guards.csv",
  approvedPerpsFileName: "./config/hyperevm/dHEDGE Approved Perps.json",
} as const;
