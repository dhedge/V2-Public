import { ChainDataOVM } from "./ChainDataType";

const torosPools = {
  USDY: "0x1ec50880101022c11530a069690f5446d1464592", // Stablecoin yield
};

const snxProxy = "0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4";

export const ovmChainData: ChainDataOVM = {
  proxyAdmin: "0x9FEE88a18479bf7f0D41Da03819538AA7A617730",
  ZERO_ADDRESS: "0x0000000000000000000000000000000000000000",
  protocolDao: "0x90b1a66957914EbbE7a8df254c0c1E455972379C",
  curvePools: [],
  oneinch: {
    v4Router: "0x1111111254760F7ab3F16433eea9304126DCd199",
    v5Router: "0x1111111254eeb25477b68fb85ed929f73a960582",
  },
  eth_price_feeds: {},

  synthetix: {
    snxProxy: snxProxy,
    addressResolver: "0x1Cb059b7e74fD21665968C908806143E744D5F30",
    susdKey: "0x7355534400000000000000000000000000000000000000000000000000000000",
    sethKey: "0x7345544800000000000000000000000000000000000000000000000000000000",
    slinkKey: "0x734c494e4b000000000000000000000000000000000000000000000000000000",
    sUSDProxy_target_tokenState: "0x92bac115d89ca17fd02ed9357ceca32842acb4c2",
  },

  v2Routers: ["0xE6Df0BB08e5A97b40B21950a0A51b94c4DbA0Ff6"],

  // zipswap
  zipswap: {
    factory: "0x8BCeDD62DD46F1A76F8A1633d4f5B76e0CDa521E",
    router: "0xE6Df0BB08e5A97b40B21950a0A51b94c4DbA0Ff6",
  },

  futures: {
    futuresMarketSettings: "0xaE55F163337A2A46733AA66dA9F35299f9A46e9e",
    ethMarket: "0xf86048dff23cf130107dfb4e6386f574231a5c65",
  },

  assets: {
    susd: "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9",
    seth: "0xE405de8F52ba7559f9df3C368500B6E6ae6Cee49",
    sbtc: "0x298B9B95708152ff6968aafd889c6586e9169f1D",
    slink: "0xc5Db22719A06418028A40A9B5E9A7c02959D0d08",
    snxProxy: snxProxy,
    usdc: "0x7f5c764cbc14f9669b88837ca1490cca17c31607",
    usdt: "0x94b008aa00579c1307b0ef2c499ad98a8ce58e58",
    weth: "0x4200000000000000000000000000000000000006",
    dai: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
    wbtc: "0x68f180fcCe6836688e9084f035309E29Bf0A2095",
    dht: "0xAF9fE3B5cCDAe78188B1F8b9a49Da7ae9510F151",
    op: "0x4200000000000000000000000000000000000042",
  },

  assetsBalanceOfSlot: {
    usdc: 0,
    usdt: 0,
    weth: 3,
    dai: 2,
    wbtc: 0,
    susd: 3,
  },

  price_feeds: {
    eth: "0x13e3Ee699D1909E989722E753853AE30b17e08c5",
    link: "0xCc232dcFAAE6354cE191Bd574108c1aD03f86450",
    btc: "0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593",
    dai: "0x8dBa75e83DA73cc766A7e5a0ee71F656BAb470d6",
    usdc: "0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3",
    usdt: "0xECef79E109e997bCA29c1c0897ec9d7b03647F5E",
    snx: "0x2FCF37343e916eAEd1f1DdaaF84458a359b53877",
    susd: "0x7f99817d87baD03ea21E05112Ca799d715730efe",
    op: "0x0D276FC14719f9292D5C1eA2198673d1f4269246",
  },

  // uniswap V3
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

  lyra: {
    optionMarketWrapper: "0xCCE7819d65f348c64B7Beb205BA367b3fE33763B",
    synthetixAdapter: "0xbfa31380ED380cEb325153eA08f296A45A489108",
    optionMarketViewer: "0xEAf788AD8abd9C98bA05F6802a62B8DbC673D76B",
    lyraRegistry: "0xF5A0442D4753cA1Ea36427ec071aa5E786dA5916",
    quoter: "0xa60D490C1984D91AB2E43e5b891b2AB8Ab790752",
  },

  torosPools: torosPools,

  velodrome: {
    velo: "0x3c8B650257cFb5f272f799F5e2b4e65093a11a05",
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

  // Arrakis
  arrakis: {
    v1RouterStaking: "0x86d62a8ad19998e315e6242b63eb73f391d4674b",
    usdcWethGauge: "0xb8888ea29e2f70ad62a3b69b1a1342720612a00d",
  },
};
