import { BigNumber } from "ethers";
import { IAddresses, IFileNames } from "../types";

const protocolDao = "0x13471A221D6A346556723842A1526C603Dc4d36B";
const protocolTreasury = "0x26f7cbd49A4DC3321780AE8e7e0cb460f55a7511";
// Should be fetched from the oz file
const proxyAdmin = "0x2B15c0D49163DFdAE6024b4a3643378081aA5Fd5";

export const assets = {
  weth: "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",
  usdc: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
  dht: "0x8038f3c971414fd1fc220ba727f2d4a0fc98cb65",
  wsteth: "0x5979D7b546E38E414F7E9822514be443A4800529",
  usdcNative: "0xaf88d065e77c8cc2239327c5edb3a432268e5831",
  wbtc: "0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f",
  arb: "0x912ce59144191c1204e64559fe8253a0e49e6548",
};

const torosPools = {
  ETHBULL3X: "0xf715724abba480d4d45f4cb52bef5ce5e3513ccc",
  BTCBULL3X: "0xad38255febd566809ae387d5be66ecd287947cb9",
  sETHy: "0xe9b5260d99d283ff887859c569baf8ad1bd12aac",
  ETHBULL2X: "0x696f6d66c2da2aa4a400a4317eec8da88f7a378c",
  BTCBULL2X: "0xe3254397f5d9c0b69917ebb49b49e103367b406f",
  ETHBEAR1X: "0x40d30b13666c55b1f41ee11645b5ea3ea2ca31f8",
  BTCBEAR1X: "0x27d8fdb0251b48d8edd1ad7bedf553cf99abe7b0",
  ETHy: "0x43DA9b0aB53242c55A9Ff9c722FfC2a373D639c7",
  BTCy: "0x319fD1d1D74607B7a224EB4e31A4aa75837D7d01",
  USDmny: "0x9A916e55F5b67226734CD7B465d51BCE1d11a89a",
  SOLBULL3X: "0xcFEc7a15726D4b5d183783C9033b921bA3a5090a",
  SOLBULL2X: "0xE9A71F5230a41Aa09f4099a41d24450E85462Fe1",
  SOLBEAR1X: "0xda6d2144FaEc116b53715F76Ca4A79925A3bB1fB",
  ETHBULL4X: "0xBf4aB4224B2AC26667Cd4b8A0E5134D55cB0B293",
  BTCBULL4X: "0xd49d22f2a2f05B2088fD42503409E430a8a7D827",
  SUIBULL2X: "0x1a9B3A496Fe222Ba84c53E215A904c555C3157c9",
  SOL1X: "0xa6686c9c6bc90f84e3fb77c3d5417fd66bc05697",
  SUI1X: "0xc8f346c8045fa911eac2ffef628e0c5fcdb445bd",
  DOGEBULL2X: "0x7d37089ed7434c50f659D40b1E1fE09Be026fc77",
  DOGE1X: "0x06ABBA36D0991A83e75f54dBB2a8Dc91F30f8C78",
  XRP1X: "0x1369E0F1520671cd0748984c40955F6A6aF40487",
  HYPE1X: "0xbfc82f7823C0261903057B04B1C7C0E4e49eb550",
  XRPBULL2X: "0xD0F9912f604C0A5Fd9bd03889243F5c426b38c81",
  BNB1X: "0xb6E92517C99087cB58D8E8A8e649C598137F3fc3",
  CRV1X: "0x0f5a811Cb153BDCFD74AD69E82567396385feC3a",
  LINK1X: "0xeCB200a89DfcC09663493A0f67089C7FeBf08D14",
  LINKBULL2X: "0x4Ec9C0f08BDCe085e9D4053B393a290D7AFC8083",
  HYPEBULL2X: "0xE2Afa0cA430432ffd22564BdeA87fa4cFB879c4e",
  CRVBULL2X: "0xF8eDE83467778ed0c1ab54CB21F17Dd9d33e6c86",
  PUMP1X: "0x6030aB5a681398Ab5616Da99A9C8453fd84bc802",
  PUMPBULL2X: "0x6D72a0883AA4ac3d32067B6eC21e3f84a67485e2",
  BNBBULL2X: "0x829E90E558A2eEBa733fEffaD3419543C4bCBa08",
  ETHBEAR2X: "0x41e29b6d6295f287070b3759CcaA6964b7f4cb31",
  BTCBEAR2X: "0x3e63f81b3AA4e821392fCcdAbdD7D0c960C0235E",
  SOLBEAR2X: "0x1227a7C904F0A3923f1319cCcE15ab23a66FD4D2",
  XRPBEAR1X: "0x764FAd1F0A4B1D5c20f0432BA5c8c594C57051B7",
  BNBBEAR1X: "0x7AeD02321Cd9aeFCaEb6942bc10B35d8dAf85722",
  DOGEBEAR1X: "0x4D92f42b2936d2C685027cAd2F682f2cE8E812AC",
  LINKBEAR1X: "0x1D01303F4cBD1B4402d300ce1591CbADad74e075",
  HYPEBEAR1X: "0x44F9CBc1356F5592f91A69eFE923B91514986381",
  SUIBEAR1X: "0x1E0e416ADD4F3A66fd4258fA21942d9116e1077A",
  PUMPBEAR1X: "0x360E83BD7f746a7bcAe4685c2BF589882392F54c",
  CRVBEAR1X: "0xeE46dEE5594ADfe7aeB9B9c7aC33Baf214b8F075",
  SUIBULL3X: "0xB6783Ac4a451e379Af99067A02c41f1819123EC0",
  XRPBULL3X: "0xa2bD75D941634F2D2800cA9a20b20A17a2Fea17e",
  BTC1X: "0x326e1c8b9cB088cbbEB5440Bd0EbAAC0d0607538",
  ETH1X: "0x11F0fd32F8b6dB76067d710582b4B4739ad49A75",
  AAVEBEAR1X: "0x4ACa336C6A4eFfBd571Ab4c2621ee0ec4A594c46",
  AAVEBULL2X: "0xdDaaCbDBf778924e11Eb6D50EB6CE5EB3Cb95DF5",
  BTCHOSRTVOL: "0x8C068d7033d66c4AacaB25CE8219E5688C60155f",
  BTCCOVCALL: "0x2FbAdd08aDE2E8A24CF1Fe3a58fE918336b39a72",
  HYPEBULL3X: "0x0219549D65ac79326bD7874f6c610CB5e1B76d33",
  BTCP1X: "0x8990f5e57a8E0b5CABB68D1CD5bd790A92e32f5C",
  BTCP2X: "0x99C917097D455d54F68A6b8e73095E30badddAcE",
  BTCP3X: "0x31481Fa8e8802EAcF1cfa3aaBDD11be24FcC3476",
};

export const gmxTestVaults = {
  gmxTest2: "0x7862F74Aa0a1Db091bE314709248Ec24F5F7a967", // https://dhedge.org/vault/0x7862F74Aa0a1Db091bE314709248Ec24F5F7a967
  gmxTest6: "0xa457b8A4c1a8478F0d38AF3aDC1DD803131Bef03", // https://dhedge.org/vault/0xa457b8a4c1a8478f0d38af3adc1dd803131bef03
};

// https://data.chain.link/arbitrum/mainnet
const usdPriceFeeds = {
  btc: "0x6ce185860a4963106506C203335A2910413708e9",
  dogecoin: "0x9A7FB1b3950837a8D9b40517626E11D4127C098C",
  sui: "0x4a85B128EBDaFC24d5CB611e161376ffDECeB289",
  xrp: "0xB4AD57B52aB9141de9926a3e0C8dc6264c2ef205",
  hype: "0xf9ce4fE2F0EcE0362cb416844AE179a49591D567",
  crv: "0xaebDA2c976cfd1eE1977Eac079B4382acb849325",
  pump: "0x0C997958ccE7A0403AEA7E34d14bbaDA897B5bb3",
};

const pyth = {
  priceFeedContract: "0xff1a0f4744e8582DF1aE09D5611b887B6a12925C",
  priceIds: {
    pump: "0x7a01fca212788bba7c5bf8c9efd576a8a722f070d2c17596ff7bb609b8d5c3b9",
  },
};

export const gmx = {
  dataStore: "0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8",
  reader: "0xfA26cBb46e2614609406de08CA1Dc7f70a684184",
  referralStorage: "0xe6fab3f0c7199b0d34d7fbe83394fc0e0d06e99d",
  exchangeRouter: "0x7dE39FF2e232A2203196788d37e234cF8F1b83f1",
  approvalRouter: "0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6",
};

export const arbitrumProdData: IAddresses = {
  protocolDaoAddress: protocolDao,
  protocolTreasuryAddress: protocolTreasury,
  proxyAdminAddress: proxyAdmin,

  v2RouterAddresses: ["0x1b02da8cb0d097eb8d57a175b88c7d8b47997506"], // SushiSwap V2 Router

  superSwapper: {
    routeHints: [],
  },

  assets: {
    nativeAssetWrapper: assets.weth,
    usdc: assets.usdc,
    dht: assets.dht,
  },

  uniV2: {
    factory: "0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9",
  },

  uniV3: {
    uniswapV3FactoryAddress: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    uniswapV3RouterAddress: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
    uniSwapV3NonfungiblePositionManagerAddress: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
  },

  aaveV3: {
    aaveIncentivesControllerAddress: "0x929EC64c34a17401F460460D4B9390518E5B473e",
    aaveLendingPoolAddress: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  },

  oneInchV6RouterAddress: "0x111111125421ca6dc452d289314280a0f8842a65",

  ramses: {
    router: "0xaaa87963efeb6f7e0a2711f397663105acb1805e",
  },

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  rewardDistribution: [
    {
      amountPerSecond: BigNumber.from(3124)
        .mul(BigNumber.from(10).pow(18))
        .div(30 * 24 * 60 * 60), // 30 days in seconds,
      token: assets.arb,
      whitelistedPools: [torosPools.ETHy],
    },
    {
      amountPerSecond: BigNumber.from(100_000)
        .mul(BigNumber.from(10).pow(18))
        .div(8 * 24 * 60 * 60), // 8 days in seconds,
      token: assets.arb,
      whitelistedPools: [torosPools.ETHy],
    },
    {
      amountPerSecond: BigNumber.from(22_500)
        .mul(BigNumber.from(10).pow(6))
        .div(30 * 24 * 60 * 60), // 30 days in seconds,
      token: assets.usdcNative,
      whitelistedPools: [torosPools.sETHy],
    },
    {
      amountPerSecond: BigNumber.from(25_000)
        .mul(BigNumber.from(10).pow(18))
        .div(90 * 24 * 60 * 60), // 90 days in seconds,
      token: assets.arb,
      whitelistedPools: [torosPools.BTCy],
    },
  ],

  compoundV3: {
    rewards: "0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae",
  },

  flatMoney: {
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      torosPools.BTCBEAR1X,
      torosPools.BTCBULL2X,
      torosPools.BTCBULL3X,
      torosPools.ETHBEAR1X,
      torosPools.ETHBULL2X,
      torosPools.ETHBULL3X,
      torosPools.SOLBULL2X,
      torosPools.SOLBULL3X,
      torosPools.SOLBEAR1X,
      torosPools.BTCBULL4X,
      torosPools.ETHBULL4X,
      torosPools.SUIBULL2X,
      torosPools.DOGEBULL2X,
      torosPools.SOL1X,
      torosPools.SUI1X,
      torosPools.DOGE1X,
      torosPools.XRP1X,
      torosPools.HYPE1X,
      torosPools.XRPBULL2X,
      torosPools.BNB1X,
      torosPools.CRV1X,
      torosPools.BTCy,
      torosPools.LINK1X,
      torosPools.LINKBULL2X,
      torosPools.HYPEBULL2X,
      torosPools.CRVBULL2X,
      torosPools.PUMP1X,
      torosPools.PUMPBULL2X,
      torosPools.BNBBULL2X,
      torosPools.ETHBEAR2X,
      torosPools.BTCBEAR2X,
      torosPools.SOLBEAR2X,
      torosPools.XRPBEAR1X,
      torosPools.BNBBEAR1X,
      torosPools.DOGEBEAR1X,
      torosPools.LINKBEAR1X,
      torosPools.HYPEBEAR1X,
      torosPools.SUIBEAR1X,
      torosPools.PUMPBEAR1X,
      torosPools.CRVBEAR1X,
      torosPools.SUIBULL3X,
      torosPools.XRPBULL3X,
      torosPools.BTC1X,
      torosPools.ETH1X,
      torosPools.AAVEBEAR1X,
      torosPools.AAVEBULL2X,
      torosPools.BTCHOSRTVOL,
      torosPools.BTCCOVCALL,
      torosPools.HYPEBULL3X,
      torosPools.BTCP1X,
      torosPools.BTCP2X,
      torosPools.BTCP3X,
    ],
  },

  gmx: {
    ...gmx,
    feeReceiver: protocolTreasury, // ui fee, https://gmx-docs.io/docs/api/contracts-v2/#ui-fee
    dHedgeVaultsWhitelist: [
      {
        poolLogic: torosPools.BTCy, // https://dhedge.org/vault/0x319fd1d1d74607b7a224eb4e31a4aa75837d7d01
        withdrawalAsset: assets.wbtc,
      },
      {
        poolLogic: "0xe24f85a5a5c8a9417537d82dfaa3e14efa8fb322", // GMX Test, https://dhedge.org/vault/0xe24f85a5a5c8a9417537d82dfaa3e14efa8fb322
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: gmxTestVaults.gmxTest2,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: "0xBF30FfE47111ae5D0a5A9F9a187EAD0170BA4D8f", // GMX Test 3, https://dhedge.org/vault/0xBF30FfE47111ae5D0a5A9F9a187EAD0170BA4D8f
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: "0x2b1d9fbbeadad547a8053119e0b8cb290c487e9d", // GMX Test 4, https://dhedge.org/vault/0x2b1d9fbbeadad547a8053119e0b8cb290c487e9d
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: "0x8A948d8D843593bF8c50eeDa5f1140846b40a95E", // GMX Test 5, https://dhedge.org/vault/0x8A948d8D843593bF8c50eeDa5f1140846b40a95E
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: gmxTestVaults.gmxTest6,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.ETHy,
        withdrawalAsset: assets.weth,
      },
      {
        poolLogic: torosPools.USDmny,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.SOLBULL3X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.SOLBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.SOLBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.ETHBULL4X,
        withdrawalAsset: assets.weth,
      },
      {
        poolLogic: torosPools.BTCBULL4X,
        withdrawalAsset: assets.wbtc,
      },
      {
        poolLogic: torosPools.SUIBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.SOL1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.SUI1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.DOGEBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.DOGE1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.XRP1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.HYPE1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.XRPBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.BNB1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.CRV1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.LINK1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.LINKBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.HYPEBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.CRVBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.PUMP1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.PUMPBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.BNBBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.SOLBEAR2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.XRPBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.BNBBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.DOGEBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.LINKBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.HYPEBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.SUIBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.PUMPBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.CRVBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.SUIBULL3X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.XRPBULL3X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.AAVEBEAR1X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.AAVEBULL2X,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.HYPEBULL3X,
        withdrawalAsset: assets.usdcNative,
      },
    ],
    virtualTokenResolver: [
      {
        virtualToken: "0x47904963fc8b2340414262125aF798B9655E58Cd", // virtual BTC
        virtualTokenMultiplier: BigNumber.from(10).pow(44), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 8 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: usdPriceFeeds.btc,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43", // BTC pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0x197aa2DE1313c7AD50184234490E12409B2a1f95", // virtual SUI
        virtualTokenMultiplier: BigNumber.from(10).pow(43), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 9 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: usdPriceFeeds.sui,
          maxAge: 90_000,
        },
        pythOracleContract: pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744", // SUI pyth price id
          maxAge: 1500, // 1500 seconds => 25 mins
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0xC4da4c24fd591125c3F47b340b6f4f76111883d8", // virtual Doge
        virtualTokenMultiplier: BigNumber.from(10).pow(44), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 8 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: usdPriceFeeds.dogecoin,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0xdcef50dd0a4cd2dcc17e45df1676dcb336a11a61c69df7a0299b0150c672d25c", // Doge pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0xc14e065b0067dE91534e032868f5Ac6ecf2c6868", // virtual XRP
        virtualTokenMultiplier: BigNumber.from(10).pow(46), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 6 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: usdPriceFeeds.xrp,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0xec5d399846a9209f3fe5881d70aae9268c94339ff9817e8d18ff19fa05eea1c8", // XRP pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0xfDFA0A749dA3bCcee20aE0B4AD50E39B26F58f7C", // virtual HYPE
        virtualTokenMultiplier: BigNumber.from(10).pow(44), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 8 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: usdPriceFeeds.hype,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0x4279e31cc369bbcc2faf022b382b080e32a8e689ff20fbc530d2a603eb6cd98b", // HYPE pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0xe5f01aeAcc8288E9838A60016AB00d7b6675900b", // virtual CRV
        virtualTokenMultiplier: BigNumber.from(10).pow(34), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 18 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: usdPriceFeeds.crv,
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: pyth.priceFeedContract,
        pythOracleData: {
          priceId: "0xa19d04ac696c7a6616d291c7e5d1377cc8be437c327b75adb5dc1bad745fcae8", // CRV pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
      {
        virtualToken: "0x9c060B2fA953b5f69879a8B7B81f62BFfEF360be", // virtual PUMP
        virtualTokenMultiplier: BigNumber.from(10).pow(34), // formula for decimals for price feed multiplier: 60 - 8 (external price feed decimals) - 18 (token decimals)
        oracleLookupType: 1, // 1 = ChainlinkPythLib
        onchainOracle: {
          oracleContract: usdPriceFeeds.pump, // note: this onchain oracle decimals is 18, but getTokenMinMaxPrice returns price with 8 decimals
          maxAge: 90_000, // 90_000 seconds => 25 hours,
        },
        pythOracleContract: pyth.priceFeedContract,
        pythOracleData: {
          priceId: pyth.priceIds.pump, // PUMP pyth price id
          maxAge: 86_400, // 86400 seconds => 24 hours,
          minConfidenceRatio: 50, // 100/50 => +-2% price deviation acceptable,
        },
      },
    ],
  },

  across: {
    spokePool: "0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A",
  },

  pancakeswap: {
    nonfungiblePositionManager: "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
    masterChefV3: "0x5e09ACf80C0296740eC5d6F643005a4ef8DaA694",
  },

  flatMoneyOptions: {
    orderAnnouncementModule: "0x2326BB21B769D81E134C9b305ca156f989249fE7",
    orderExecutionModule: "0x7e50AD6E467D9FAFC3B4BFd003247cEaA2F17e5b",
    flatcoinVault: "0x29fAD9d44C550e5D8081AB35763797B39d75b858",
    whitelistedVaultsForLP: [
      {
        poolLogic: "0x3696652233468ab827e5af5155a9f2a0c07682c4", // Test Vault
        withdrawalAsset: assets.wbtc,
      },
      {
        poolLogic: torosPools.BTCHOSRTVOL,
        withdrawalAsset: assets.wbtc,
      },
      {
        poolLogic: torosPools.BTCCOVCALL,
        withdrawalAsset: assets.wbtc,
      },
    ],
    collateral: assets.wbtc,
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

  fluid: {
    merkleDistributor: "0x94312a608246Cecfce6811Db84B3Ef4B2619054E",
  },

  angleProtocol: {
    distributor: "0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae",
    rewardTokenSupported: [
      {
        token: "0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8", // aArbWETH
        tokenType: 2,
      },
      {
        token: "0x513c7E3a9c69cA3e22550eF58AC1C0088e918FFf", // aArbwstETH
        tokenType: 2,
      },
      {
        token: "0x6533afac2E7BCCB20dca161449A13A32D391fb00", // aArbARB
        tokenType: 2,
      },
      {
        token: assets.arb,
        tokenType: 1,
      },
      {
        token: "0x2c63f9da936624Ac7313b972251D340260A4bF08", // Wrapped aArbARB
        tokenType: 3,
      },
    ],
  },

  kyberSwap: {
    routerV2: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
  },

  rewardAssetSetting: [
    {
      rewardToken: assets.wsteth, // wstETH
      linkedAssetTypes: [],
      linkedAssets: [
        "0x71fBF40651E9D4278a74586AfC99F307f369Ce9A", // PT-wstETH-25JUN2026
      ],
    },
  ],

  pendle: {
    pendleRouterV4: "0x888888888889758F76e7103c6CbF23ABbF58F946",
    knownMarkets: [
      "0xf78452e0f5C0B95fc5dC8353B8CD1e06E53fa25B", // wstETH-25JUN2026
    ],
  },

  easyLimitBuyManager: {
    permit2: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
    authorizedKeeperAddresses: [
      "0xFBFE87a8665cE77e4F1f47d0256b7e68Be966498",
      "0xBA2A62aFAfC662afbE5C726910C101225aDeF591",
      "0x4C6ced5164042150A63Cd7610af3Efc7fF2fe4B6",
      "0x3D8D80d65EF8df009AF576dF44d4d06bf39A94DF",
    ],
  },
};

export const arbitrumProdFileNames: IFileNames = {
  versionsFileName: "./publish/arbitrum/prod/versions.json",
  assetsFileName: "./config/arbitrum/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/arbitrum/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/arbitrum/dHEDGE Governance Contract Guards.csv",
  deprecatedContractGuardsFileName: "./config/arbitrum/dHEDGE Deprecated Contract Guards.csv",
} as const;
