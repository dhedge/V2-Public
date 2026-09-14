import { IAddresses, IFileNames } from "../types";
import { AssetType } from "../upgrade/jobs/assetsJob";

// Created before new chain deployment
const protocolDao = "0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100";
const protocolTreasury = "0xEE27793EBAf6a446c74C2cDd23Bba615e9472264";
// Should be fetched from the oz file
const proxyAdmin = "0xD3113A115676EaF2c33bc40C336aa0595CbC8BDa";

export const assets = {
  weth: "0x4200000000000000000000000000000000000006",
  usdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  reth: "0xb6fe221fe9eef5aba221c348ba20a1bf5e73624c",
};

const torosPools = {
  USDMNY: "0xede61eefa4850b459e3b09fe6d8d371480d6ff00",
  sUSDCy: "0xc1e02884af4a283ca25ab63c45360d220d69da52",
  STETHBULL2X: "0xa672e882acbb96486393d43e0efdab5ebebddc1d",
  STETHBULL3X: "0x15e2f06138aed58ca2a6afb5a1333bbc5f728f80",
  STETHBULL4X: "0xba5f6a0d2ac21a3fec7a6c40facd23407aa84663",
  FAy: "0xd258da1a96c53676301b60000918a1406e367d3e",
  USDy: "0x1c980456751AE40315Ff73CaaC0843Be643321Be",
  BTCBEAR1X: "0xd2f23773bf5e2d59f6bb925c2232f6e83f3f79e0",
  BTCBULL2X: "0x9e0501537723c71250307F5B1A8eE60e167D21C9",
  BTCBULL3X: "0xCAF08BF08D0c87e2c74dd9EBEC9C776037bD7e8E",
};

export const FLAT_MONEY_PERP_MARKET_BOT_TEST = "0xCF51f81652779C07D08F1C7d0AcAf66E5C3b7377"; // https://dhedge.org/vault/0xcf51f81652779c07d08f1c7d0acaf66e5c3b7377

const aerodromeVoter = "0x16613524e02ad97eDfeF371bC883F2F5d6C480A5";

export const baseProdData: IAddresses = {
  protocolDaoAddress: protocolDao,
  protocolTreasuryAddress: protocolTreasury,
  proxyAdminAddress: proxyAdmin,

  v2RouterAddresses: ["0x6bded42c6da8fbf0d2ba55b2fa120c5e0c8d7891"], // SushiSwap V2 Router

  superSwapper: {
    routeHints: [],
  },

  assets: {
    nativeAssetWrapper: assets.weth,
  },

  uniV2: {
    factory: "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6",
  },

  uniV3: {
    uniswapV3FactoryAddress: "0x33128a8fC17869897dcE68Ed026d694621f6FDfD",
    uniswapV3RouterAddress: "0x2626664c2603336E57B271c5C0b26F421741e481",
  },

  oneInchV6RouterAddress: "0x111111125421ca6dc452d289314280a0f8842a65",

  velodrome: {
    factoryV2: "0x420DD381b31aEf6683db6B902084cB0FFECe40Da",
    routerV2: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
    voterV2: aerodromeVoter,
  },

  velodromeCL: {
    nonfungiblePositionManager: "0x827922686190790b37229fd06084350E74485b72",
    voter: aerodromeVoter,
    enabledGauges: [
      "0xBd85D45f1636fCEB2359d9Dcf839f12b3cF5AF3F", // CL1-USDC/USDT
      "0x2A1f7bf46bd975b5004b61c6040597E1B6117040", // CL1-WETH/wstETH
      "0x1f6c9d116CE22b51b0BC666f86B038a6c19900B8", // CL50-EURC/USDC
      "0x41b2126661C673C2beDd208cC72E85DC51a5320a", // CL100-WETH/cbBTC
      "0x6399ed6725cC163D019aA64FF55b22149D7179A8", // CL100-USDC/cbBTC
      "0xB57eC27f68Bd356e300D57079B6cdbe57d50830d", // CL1-tBTC/cbBTC
      "0xe2a2B1D8AA4bD8A05e517Ccf61E96A727831B63e", // CL1-USDS/USDC
      "0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8", // CL100-WETH/USDC
    ],
  },

  aaveV3: {
    aaveLendingPoolAddress: "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5",
    aaveIncentivesControllerAddress: "0xf9cc4F0D883F1a1eb2c253bdb46c254Ca51E1F44",
  },

  flatMoney: {
    delayedOrder: "0x6D857e9D24a7566bB72a3FB0847A3E0e4E1c2879",
    perpMarketWhitelistedVaults: [
      {
        poolLogic: torosPools.FAy, // Funding Arbitrage Yield https://dhedge.org/vault/0xd258da1a96c53676301b60000918a1406e367d3e
        withdrawalAsset: assets.usdc,
      },
      {
        poolLogic: "0x5334d0184a11f210de806fcd5b556bf19981a7be", // Flat Money Market Maker https://dhedge.org/vault/0x5334d0184a11f210de806fcd5b556bf19981a7be
        withdrawalAsset: assets.reth,
      },
      {
        poolLogic: FLAT_MONEY_PERP_MARKET_BOT_TEST,
        withdrawalAsset: assets.usdc,
      },
      {
        poolLogic: "0xa1a0fcc73689549b244e9938d71b6638e18032d7", // Synthetix V3 Perps Bot Test https://dhedge.org/vault/0xa1a0fcc73689549b244e9938d71b6638e18032d7
        withdrawalAsset: assets.reth,
      },
      {
        poolLogic: torosPools.STETHBULL2X,
        withdrawalAsset: assets.reth,
      },
      {
        poolLogic: torosPools.STETHBULL3X,
        withdrawalAsset: assets.reth,
      },
      {
        poolLogic: torosPools.STETHBULL4X,
        withdrawalAsset: assets.reth,
      },
      {
        poolLogic: "0x631d238c4Fd232c14BF318174711538f737C0c7c", // Ethereum Surge https://dhedge.org/vault/0x631d238c4Fd232c14BF318174711538f737C0c7c
        withdrawalAsset: assets.reth,
      },
    ],
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
  },

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  rewardAssetSetting: [
    {
      rewardToken: "0x940181a94a35a4569e4529a3cdfb74e38fd98631",
      linkedAssetTypes: [
        AssetType["Velodrome V2 LP/Gauge Asset"], // 25
        AssetType["Velodrome CL NFT Position Asset"], // 26
      ],
      linkedAssets: [],
    },
  ],

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      torosPools.sUSDCy,
      torosPools.STETHBULL2X,
      torosPools.STETHBULL3X,
      torosPools.STETHBULL4X,
      "0xCC4D4e673046e843C0E41ED150aD7a4be95b62ea", // SwapperTest https://dhedge.org/vault/0xcc4d4e673046e843c0e41ed150ad7a4be95b62ea
      torosPools.USDy,
      torosPools.USDMNY,
      torosPools.BTCBEAR1X,
      torosPools.BTCBULL2X,
      torosPools.BTCBULL3X,
    ],
  },

  angleProtocol: {
    distributor: "0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae",
    rewardTokenSupported: [
      { token: "0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB", tokenType: 2 }, // aBasUSDC
      { token: "0x99CBC45ea5bb7eF3a5BC08FB1B7E56bB2442Ef0D", tokenType: 2 }, // aBaswstETH
      { token: "0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7", tokenType: 2 }, // aBasWETH
      { token: "0xBdb9300b7CDE636d9cD4AFF00f6F009fFBBc8EE6", tokenType: 2 }, // aBascbBTC
      { token: "0x7C307e128efA31F540F2E2d976C995E0B65F51F6", tokenType: 2 }, // aBasweETH
      { token: "0x067ae75628177FD257c2B1e500993e1a0baBcBd1", tokenType: 2 }, // aBasGHO
      { token: "0x90DA57E0A6C0d166Bf15764E03b83745Dc90025B", tokenType: 2 }, // aBasEURC
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

  pancakeswap: {
    nonfungiblePositionManager: "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
    masterChefV3: "0xC6A2Db661D5a5690172d8eB0a7DEA2d3008665A3",
  },

  across: {
    spokePool: "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64",
  },

  compoundV3: {
    rewards: "0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1",
  },

  fluid: {
    merkleDistributor: "0x94312a608246Cecfce6811Db84B3Ef4B2619054E",
  },

  kyberSwap: {
    routerV2: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
  },
};

export const baseProdFileNames: IFileNames = {
  versionsFileName: "./publish/base/prod/versions.json",
  assetsFileName: "./config/base/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/base/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/base/dHEDGE Governance Contract Guards.csv",
  deprecatedContractGuardsFileName: "./config/base/dHEDGE Deprecated Contract Guards.csv",
} as const;
