const snxProxy = "0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4";

const assets = Object.freeze({
  susd: "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9",
  seth: "0xE405de8F52ba7559f9df3C368500B6E6ae6Cee49",
  sbtc: "0x298B9B95708152ff6968aafd889c6586e9169f1D",
  slink: "0xc5Db22719A06418028A40A9B5E9A7c02959D0d08",
  snxProxy,
  usdc: "0x7f5c764cbc14f9669b88837ca1490cca17c31607",
  usdt: "0x94b008aa00579c1307b0ef2c499ad98a8ce58e58",
  weth: "0x4200000000000000000000000000000000000006",
  dai: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
  wbtc: "0x68f180fcCe6836688e9084f035309E29Bf0A2095",
  dht: "0xAF9fE3B5cCDAe78188B1F8b9a49Da7ae9510F151",
  op: "0x4200000000000000000000000000000000000042",
  maiStableCoin: "0xdfa46478f9e5ea86d57387849598dbfb2e964b02",
  stg: "0x2f6f07cdcf3588944bf4c42ac74ff24bf56e7590",
  velo: "0x3c8B650257cFb5f272f799F5e2b4e65093a11a05",
  alusd: "0xcb8fa9a76b8e203d8c3797bf438d8fb81ea3326a",
  lusd: "0xc40f949f8a4e094d1b49a23ea9241d289b7b2819",
  snxUSD: "0xb2F30A7C980f052f02563fb518dcc39e6bf38175",
  wstETH: "0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb",
  link: "0x350a791bfc2c21f9ed5d10980dad2e2638ffa7f6",
  usdcNative: "0x0b2c639c533813f4aa9d7837caf62653d097ff85",
});

export const ovmChainData = Object.freeze({
  proxyAdmin: "0x9FEE88a18479bf7f0D41Da03819538AA7A617730",
  protocolDao: "0x90b1a66957914EbbE7a8df254c0c1E455972379C",
  oneinch: {
    v4Router: "0x1111111254760F7ab3F16433eea9304126DCd199",
    v5Router: "0x1111111254eeb25477b68fb85ed929f73a960582",
    v6Router: "0x111111125421ca6dc452d289314280a0f8842a65",
  },

  synthetix: {
    snxProxy,
    addressResolver: "0x1Cb059b7e74fD21665968C908806143E744D5F30",
    susdKey: "0x7355534400000000000000000000000000000000000000000000000000000000",
    sethKey: "0x7345544800000000000000000000000000000000000000000000000000000000",
    slinkKey: "0x734c494e4b000000000000000000000000000000000000000000000000000000",
    sinrKey: "0x73494e5200000000000000000000000000000000000000000000000000000000",
    // This is where the balances are stored for SUSD
    // We need to use this for getTokenAccount
    sUSDProxy_target_tokenState: "0x92bac115d89ca17fd02ed9357ceca32842acb4c2",
    sLINKProxy_target_tokenState: "0x08a008eea07d3cc7ca1913eec3468c10f8f79e6a",
    SNXProxy_target_tokenState: "0xb9c6ca25452e7f6d0d3340ce1e9b573421afc2ee",
    synthRedeemer: "0xA997BD647AEe62Ef03b41e6fBFAdaB43d8E57535",
    v3Core: "0xffffffaEff0B96Ea8e4f94b2253f31abdD875847",
    accountNFT: "0x0E429603D3Cb1DFae4E6F52Add5fE82d96d77Dac",
    v3SpotMarket: "0x38908Ee087D7db73A1Bd1ecab9AAb8E8c9C74595",
  },

  v2Routers: [],

  zipswap: {
    factory: "0x8BCeDD62DD46F1A76F8A1633d4f5B76e0CDa521E",
    router: "0xE6Df0BB08e5A97b40B21950a0A51b94c4DbA0Ff6",
  },

  futures: {
    futuresMarketSettings: "0xaE55F163337A2A46733AA66dA9F35299f9A46e9e",
    ethMarket: "0xf86048dff23cf130107dfb4e6386f574231a5c65",
  },

  perpsV2: {
    ethMarket: "0x2b3bb4c683bfc5239b029131eef3b1d214478d93",
    // Synthetix integration should always use the address resolver to fetch latest addresses
    addressResolver: "0x1Cb059b7e74fD21665968C908806143E744D5F30",
  },

  stargate: {
    router: "0xB0D502E938ed5f4df2E681fE6E419ff29631d62b",
    staking: "0x4DeA9e918c6289a52cd469cAC652727B7b412Cd2",
    stakingRewardToken: "0x4200000000000000000000000000000000000042", // OP token
    pools: {
      susdc: {
        address: "0xdecc0c09c3b5f6e92ef4184125d5648a66e35298",
        poolId: 1,
        stakingPoolId: 0,
      },
      sdai: {
        address: "0x165137624F1f692e69659f944BF69DE02874ee27",
        poolId: 3,
        stakingPoolId: 2,
      },
      ssusd: {
        address: "0x2f8bc9081c7fcfec25b9f41a50d97eaa592058ae",
        poolId: 14,
        stakingPoolId: 4,
      },
    },
  },
  assets,
  assetsBalanceOfSlot: {
    usdc: 0,
    usdt: 0,
    weth: 3,
    dai: 2,
    wbtc: 0,
    susd: 3,
    op: 0,
    snx: 3,
    usdcNative: 9,
  },

  usdPriceFeeds: {
    eth: "0x13e3Ee699D1909E989722E753853AE30b17e08c5",
    link: "0xCc232dcFAAE6354cE191Bd574108c1aD03f86450",
    btc: "0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593",
    dai: "0x8dBa75e83DA73cc766A7e5a0ee71F656BAb470d6",
    usdc: "0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3",
    usdt: "0xECef79E109e997bCA29c1c0897ec9d7b03647F5E",
    snx: "0x2FCF37343e916eAEd1f1DdaaF84458a359b53877",
    susd: "0x7f99817d87baD03ea21E05112Ca799d715730efe",
    op: "0x0D276FC14719f9292D5C1eA2198673d1f4269246",
    maiStableCoin: "0xECAF977A599cD94c71e7292BA0c9cEA9eA227d2a",
  },

  uniswapV3: {
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    router: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
    nonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    pools: {
      susd_dai: "0xadb35413ec50e0afe41039eac8b930d313e94fa4",
    },
  },

  // https://docs.aave.com/developers/deployed-contracts/v3-mainnet/optimism
  aaveV3: {
    protocolDataProvider: "0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654",
    lendingPool: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
    incentivesController: "0x929EC64c34a17401F460460D4B9390518E5B473e",
    aTokens: {
      weth: "0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8",
      usdc: "0x625E7708f30cA75bfd92586e17077590C60eb4cD",
      dai: "0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE",
      usdt: "0x6ab707Aca953eDAeFBc4fD23bA73294241490620",
      link: "0x191c10Aa4AF7C30e871E70C95dB0E4eb77237530",
    },
    variableDebtTokens: {
      weth: "0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351",
      usdc: "0xFCCf3cAbbe80101232d343252614b6A3eE81C989",
      dai: "0x8619d80FB0141ba7F184CbF22fd724116D9f7ffC",
      usdt: "0xfb00AC187a8Eb5AFAE4eACE434F493Eb62672df7",
      link: "0x953A573793604aF8d41F306FEb8274190dB4aE0e",
    },
    stableDebtTokens: {
      weth: "0xD8Ad37849950903571df17049516a5CD4cbE55F6",
      usdc: "0x307ffe186F84a3bc2613D1eA417A5737D69A7007",
      dai: "0xd94112B5B62d53C9402e7A60289c6810dEF1dC9B",
      usdt: "0x70eFfc565DB6EEf7B927610155602d31b670e802",
      link: "0x89D976629b7055ff1ca02b927BA3e020F22A44e4",
    },
  },

  // Contract addresses from https://docs.sonne.finance/protocol/contract-addresses
  sonne: {
    comptroller: "0x60CF091cD3f50420d50fD7f707414d0DF4751C58",
    cTokens: {
      usdc: "0xEC8FEa79026FfEd168cCf5C627c7f486D77b765F",
      dai: "0x5569b83de187375d43FBd747598bfe64fC8f6436",
      weth: "0xf7B5965f5C117Eb1B5450187c9DcFccc3C317e8E",
    },
  },

  lyra: {
    optionMarketWrapper: "0xCCE7819d65f348c64B7Beb205BA367b3fE33763B",
    synthetixAdapter: "0xbfa31380ED380cEb325153eA08f296A45A489108",
    optionMarketViewer: "0xEAf788AD8abd9C98bA05F6802a62B8DbC673D76B",
    lyraRegistry: "0xF5A0442D4753cA1Ea36427ec071aa5E786dA5916",
    quoter: "0xa60D490C1984D91AB2E43e5b891b2AB8Ab790752",
  },

  torosPools: {
    USDY: "0x1ec50880101022c11530a069690f5446d1464592",
    USDMNY: "0x49bf093277bf4dde49c48c6aa55a3bda3eedef68",
    ETHY: "0xb2cfb909e8657c0ec44d3dd898c1053b87804755",
    USDpy: "0xb9243c495117343981ec9f8aa2abffee54396fc0",
    ETHBULL2X: "0x9573c7b691cdcebbfa9d655181f291799dfb7cf5",
    ETHBEAR1X: "0xcacb5a722a36cff6baeb359e21c098a4acbffdfa",
    BTCBULL2X: "0x32ad28356ef70adc3ec051d8aacdeeaa10135296",
    BTCBEAR1X: "0x83d1fa384ec44c2769a3562ede372484f26e141b",
    LINKBULL2X: "0x9fa29b1f55f57e7af577ea2bc8a8e4488aa150f1",
    LINKBEAR1X: "0xe17a1b2038fa5d725a3cb077ad6c242062b4872b",
    ETHBULL3X: "0x32b1d1bfd4b3b0cb9ff2dcd9dac757aa64d4cb69",
    BTCBULL3X: "0xb03818de4992388260b62259361778cf98485dfe",
  },

  velodrome: {
    velo: assets.velo,
    voter: "0x09236cff45047dbee6b921e00704bed6d6b8cf7e",
    factory: "0x25CbdDb98b35ab1FF77413456B31EC81A6B6B746",
    router: "0x9c12939390052919aF3155f41Bf4160Fd3666A6f",
    VARIABLE_WETH_USDC: {
      isStable: false,
      poolAddress: "0x79c912FEF520be002c2B6e57EC4324e260f38E50",
      gaugeAddress: "0xE2CEc8aB811B648bA7B1691Ce08d5E800Dd0a60a",
    },
    VARIABLE_VELO_USDC: {
      isStable: false,
      poolAddress: "0xe8537b6FF1039CB9eD0B71713f697DDbaDBb717d",
      gaugeAddress: "0x6b8EDC43de878Fd5Cd5113C42747d32500Db3873",
    },
    STABLE_USDC_DAI: {
      isStable: true,
      poolAddress: "0x4F7ebc19844259386DBdDB7b2eB759eeFc6F8353",
      gaugeAddress: "0xc4fF55A961bC04b880e60219CCBBDD139c6451A4",
    },
  },

  velodromeV2: {
    velo: "0x9560e827af36c94d2ac33a39bce1fe78631088db",
    voter: "0x41c914ee0c7e1a5edcd0295623e6dc557b5abf3c",
    factory: "0xf1046053aa5682b4f9a81b5481394da16be5ff5a",
    router: "0xa062ae8a9c5e11aaa026fc2670b0d65ccc8b2858",
    VARIABLE_WETH_USDC: {
      isStable: false,
      poolAddress: "0x0493Bf8b6DBB159Ce2Db2E0E8403E753Abd1235b",
      gaugeAddress: "0xE7630c9560C59CCBf5EEd8f33dd0ccA2E67a3981",
    },
    VARIABLE_VELO_USDC: {
      isStable: false,
      poolAddress: "0x8134A2fDC127549480865fB8E5A9E8A8a95a54c5",
      gaugeAddress: "0x84195De69B8B131ddAa4Be4F75633fCD7F430b7c",
    },
    STABLE_USDC_DAI: {
      isStable: true,
      poolAddress: "0x19715771E30c93915A5bbDa134d782b81A820076",
      gaugeAddress: "0x6998089f6bdd9c74c7d8d01b99d7e379ccccb02d",
    },
  },

  velodromeCL: {
    nonfungiblePositionManager: "0xbb5dfe1380333cee4c2eebd7202c80de2256adf4",
    factory: "0x548118C7E0B865C2CfA94D15EC86B666468ac758",
  },

  arrakis: {
    v1RouterStaking: "0x9ce88a56d120300061593ef7ad074a1b710094d5",
    usdcWethGauge: "0xb8888ea29e2f70ad62a3b69b1a1342720612a00d",
  },

  // Swap router route hints for lower slippage swaps
  routeHints: [
    { asset: assets.maiStableCoin, intermediary: assets.usdc },
    { asset: assets.velo, intermediary: assets.usdc },
    { asset: assets.susd, intermediary: assets.usdc },
    { asset: assets.dht, intermediary: assets.op },
    { asset: assets.alusd, intermediary: assets.usdc },
    { asset: assets.lusd, intermediary: assets.usdc },
    { asset: assets.wstETH, intermediary: assets.weth },
    { asset: assets.link, intermediary: assets.weth },
    { asset: assets.usdcNative, intermediary: assets.usdc },
  ],

  zeroEx: {
    exchangeProxy: "0xDEF1ABE32c034e558Cdd535791643C58a13aCC10",
  },
});
