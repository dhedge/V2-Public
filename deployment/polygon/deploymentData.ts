import { BigNumber } from "ethers";
import { IAddresses, IFileNames } from "../types";

const protocolDao = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
const protocolTreasury = "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3";
const proxyAdmin = "0x0C0a10C9785a73018077dBC74B2A006695849252";

const torosPools = {
  ETHBULL3X: "0x460b60565cb73845d56564384ab84bf84c13e47d",
  BTCBULL3X: "0xdb88ab5b485b38edbeef866314f9e49d095bce39",
  MATICBEAR1X: "0x8987ca55e635d0d3ba9469ee31e9b8a7d447e9cc",
  MATICBULL2X: "0x7dab035a8a65f7d33f1628a450c6780323d3c5e1",
  BTCBEAR1X: "0x86c3dd18baf4370495d9228b58fd959771285c55",
  ETHBEAR1X: "0x79d2aefe6a21b26b024d9341a51f6b7897852499",
};

const assets = {
  wmatic: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
  weth: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",
  usdc: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
  balancer: "0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3",
  dht: "0x8C92e38eCA8210f4fcBf17F0951b198Dd7668292",
  // No chainlink feed, unsupported
  maticX: "0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6",
  agEur: "0xe0b52e49357fd4daf2c15e02058dce6bc0057db4",
  usdcNative: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
};

const aaveV3 = {
  lendingPool: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  incentivesController: "0x929EC64c34a17401F460460D4B9390518E5B473e",
  variableDebtTokens: {
    usdc: "0xFCCf3cAbbe80101232d343252614b6A3eE81C989",
    weth: "0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351",
    wbtc: "0x92b42c66840c7ad907b4bf74879ff3ef7c529473",
  },
};

const uniswapV3 = {
  factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
  router: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
  nonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
};

const routeHints = [
  { asset: assets.agEur, intermediary: assets.usdc },
  { asset: assets.balancer, intermediary: assets.weth },
  { asset: assets.maticX, intermediary: assets.wmatic },
  { asset: assets.usdcNative, intermediary: assets.usdc },
];

export const polygonProdData: IAddresses = {
  // Dhedge Internal
  protocolDaoAddress: protocolDao,
  protocolTreasuryAddress: protocolTreasury,
  // Should be fetched from the oz file
  proxyAdminAddress: proxyAdmin,

  aaveV3: {
    aaveLendingPoolAddress: aaveV3.lendingPool,
    aaveIncentivesControllerAddress: aaveV3.incentivesController,
  },

  aaveMigrationHelper: {
    migrationHelperAddress: "0x3db487975aB1728DB5787b798866c2021B24ec52",
    aaveV3DebtTokensWhitelist: [
      aaveV3.variableDebtTokens.usdc,
      aaveV3.variableDebtTokens.weth,
      aaveV3.variableDebtTokens.wbtc,
    ],
  },

  quickswap: {
    uniV2Factory: "0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32",
  },

  v2RouterAddresses: [
    "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", // SushiSwap V2 Router
    "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff", // QuickSwap V2 Router
  ],

  oneInchV6RouterAddress: "0x111111125421ca6dc452d289314280a0f8842a65",

  uniV2: {
    factory: "0x9e5A52f57b3038F1B8EeE45F28b3C1967e22799C",
  },

  uniV3: {
    uniswapV3RouterAddress: uniswapV3.router,
    uniSwapV3NonfungiblePositionManagerAddress: uniswapV3.nonfungiblePositionManager,
    uniswapV3FactoryAddress: uniswapV3.factory,
  },

  assets: {
    nativeAssetWrapper: assets.wmatic,
    usdc: assets.usdc,
    dht: assets.dht,
  },

  superSwapper: {
    routeHints: routeHints,
  },

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  flatMoney: {
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      torosPools.BTCBEAR1X,
      torosPools.BTCBULL3X,
      torosPools.ETHBEAR1X,
      torosPools.ETHBULL3X,
      torosPools.MATICBEAR1X,
      torosPools.MATICBULL2X,
    ],
  },

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: assets.usdcNative,
    authorizedKeeperAddresses: [
      "0x99c9F65a486C0567495ec58722916c73292D585f",
      "0xC0F49445a9B8A60778EF8bCa99059Ceabb066e19",
      "0x962976AA38665fc59B2F981C2457a6f95fFB2aD5",
      "0x5048d4630c51d02A281Cb77E63a1A3af4Fd8dc33",
    ],
  },

  kyberSwap: {
    routerV2: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
  },

  typedStructuredDataValidator: {
    cowSwapOrder: {
      gpv2Settlement: "0x9008D19f58AAbD9eD0D60971565AA8510560ab41",
      maxUnfavorableDeviationBps: 100, // 1%
    },
  },

  stakingV2: {
    emissionsRate: 1000,
    dhtCap: BigNumber.from(2_000_000).mul(BigNumber.from(10).pow(18)),
    whitelistedPools: [
      // Polygon	Test Pool	https://app.dhedge.org/vault/0x5e0775919ee36e3e956622c01b8e8b64bd8eb7c5	$1,000
      { pool: "0x5e0775919ee36e3e956622c01b8e8b64bd8eb7c5", cap: BigNumber.from(1000).mul(BigNumber.from(10).pow(18)) },
    ],
  },
};

export const polygonProdFileNames: IFileNames = {
  versionsFileName: "./publish/polygon/prod/versions.json",
  assetsFileName: "./config/polygon/dHEDGE Assets list.json",
  contractGuardsFileName: "./config/polygon/dHEDGE Governance Contract Guards.csv",
  assetGuardsFileName: "./config/polygon/dHEDGE Governance Asset Guards.csv",
  deprecatedContractGuardsFileName: "./config/polygon/dHEDGE Deprecated Contract Guards.csv",
};
