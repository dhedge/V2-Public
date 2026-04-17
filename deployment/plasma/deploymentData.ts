import { IAddresses, IFileNames } from "../types";

export const plasmaProdData: IAddresses = {
  protocolDaoAddress: "0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100",
  protocolTreasuryAddress: "0xEE27793EBAf6a446c74C2cDd23Bba615e9472264",
  proxyAdminAddress: "0x80B668bD5dB79F633CAFeC9032825d51dc9943f8",

  slippageAccumulator: {
    decayTime: 86400, // 1 day
    maxCumulativeSlippage: 10e4, // 10%
  },

  aaveV3: {
    aaveLendingPoolAddress: "0x925a2A7214Ed92428B5b1B090F80b25700095e12",
  },

  flatMoney: {
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
  },

  pendle: {
    pendleRouterV4: "0x888888888889758F76e7103c6CbF23ABbF58F946",
    knownMarkets: [
      "0xFD3eB62302fa3cBc3c7e59e887b92dBBc814285D", // USDe-15JAN2026
      "0xe06C3B972BA630cCF3392cEcdbe070690b4e6b55", // sUSDe-15JAN2026
      "0x5fa69163085efd4767f24639eb1fb87ed34bbb12", // sUSDe-09APR2026
      "0x4BaB3368DEdb3398664E845612d189666C6c3f5f", // USDe-09APR2026
    ],
    yieldContractFactory: "0xED0dC8C074255c277BC704D6b096167D7a6E4311",
    staticRouter: "0x6813d43782395A1F2AAb42f39aeEDE03ac655e09",
  },

  rewardAssetSetting: [
    {
      rewardToken: "0x5d3a1ff2b6bab83b63cd9ad0787074081a52ef34", // USDe
      linkedAssetTypes: [],
      linkedAssets: [
        "0x93b544c330f60a2aa05ced87aeeffb8d38fd8c9a", // PT-USDe-15JAN2026
        "0x54Dc267be2839303ff1e323584A16e86CeC4Aa44", // PT-USDe-09APR2026
      ],
    },
    {
      rewardToken: "0x211cc4dd073734da055fbf44a2b4667d5e5fe5d2", // sUSDe
      linkedAssetTypes: [],
      linkedAssets: [
        "0x02fcc4989b4c9d435b7ced3fe1ba4cf77bbb5dd8", // PT-sUSDe-15JAN2026
        "0xab509448ad489e2e1341e25cc500f2596464cc82", // PT-sUSDe-09APR2026
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
        token: "0x9421F7A094c299AF6d4451E68bA7bEC09a8a062D", // Wrapped aUSDT
        tokenType: 4,
      },
      {
        token: "0x6100E367285b01F48D07953803A2d8dCA5D19873", // WXPL
        tokenType: 5,
      },
    ],
  },
};

export const plasmaProdFileNames: IFileNames = {
  versionsFileName: "./publish/plasma/prod/versions.json",
  assetsFileName: "./config/plasma/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/plasma/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/plasma/dHEDGE Governance Contract Guards.csv",
} as const;
