const assets = Object.freeze({
  weth: "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",
  usdc: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
  usdt: "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9",
  dai: "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1",
  dht: "0x8038f3c971414fd1fc220ba727f2d4a0fc98cb65",
  wsteth: "0x5979D7b546E38E414F7E9822514be443A4800529",
  bal: "0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8",
  frax: "0x17fc002b466eec40dae837fc4be5c67993ddbd6f",
  alusd: "0xcb8fa9a76b8e203d8c3797bf438d8fb81ea3326a",
  ram: "0xaaa6c1e32c55a7bfa8066a6fae9b42650f262418",
  sweth: "0xbc011A12Da28e8F0f528d9eE5E7039E22F91cf18",
  usdcNative: "0xaf88d065e77c8cc2239327c5edb3a432268e5831",
  wbtc: "0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f",
});

export const arbitrumChainData = Object.freeze({
  // Should be fetched from the oz file
  proxyAdmin: "0x2B15c0D49163DFdAE6024b4a3643378081aA5Fd5",

  dHEDGE: {
    daoMultisig: "0x13471A221D6A346556723842A1526C603Dc4d36B",
    treasury: "0x26f7cbd49A4DC3321780AE8e7e0cb460f55a7511",
  },

  assets,
  // https://data.chain.link/arbitrum/mainnet
  usdPriceFeeds: {
    eth: "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
    usdc: "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
    usdt: "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7",
    dai: "0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB",
    bal: "0xBE5eA816870D11239c543F84b71439511D70B94f",
    frax: "0x0809e3d38d1b4214958faf06d8b1b1a2b73f2ab8",
  },
  ethPriceFeeds: {
    wsteth: "0xb523AE262D20A936BC152e6023996e46FDC2A95D",
  },

  assetsBalanceOfSlot: {
    weth: 51,
    wsteth: 1,
    usdc: 51,
    frax: 0,
    alusd: 51,
    sweth: 7,
    usdcNative: 9,
    wbtc: 51,
    usdt: 51,
    dai: 2,
  },

  v2Routers: ["0x1b02da8cb0d097eb8d57a175b88c7d8b47997506"], // SushiSwap V2 Router

  routeHints: [],

  // https://docs.uniswap.org/contracts/v3/reference/deployments
  uniswapV3: {
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    router: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
    nonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
  },

  // https://docs.aave.com/developers/deployed-contracts/v3-mainnet/arbitrum
  aaveV3: {
    lendingPool: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
    incentivesController: "0x929EC64c34a17401F460460D4B9390518E5B473e",
    protocolDataProvider: "0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654",
    aTokens: {
      usdc: "0x625E7708f30cA75bfd92586e17077590C60eb4cD",
      usdt: "0x6ab707Aca953eDAeFBc4fD23bA73294241490620",
      dai: "0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE",
      weth: "0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8",
    },
    variableDebtTokens: {
      dai: "0x8619d80FB0141ba7F184CbF22fd724116D9f7ffC",
      weth: "0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351",
    },
  },

  oneInch: {
    v5Router: "0x1111111254EEB25477B68fb85Ed929f73A960582",
    v6Router: "0x111111125421ca6dc452d289314280a0f8842a65",
  },

  balancer: {
    v2Vault: "0xba12222222228d8ba445958a75a0704d566bf2c8",
    stable: {
      wstETH_WETH: {
        pool: "0x36bf227d6bac96e2ab1ebb5492ecec69c691943f",
        gauge: "0x251e51b25afa40f2b6b9f05aaf1bc7eaa0551771",
      },
    },
    weighted: {
      wstETH_USDC: {
        pool: "0x178e029173417b1f9c8bc16dcec6f697bc323746",
        gauge: "0x9232ee56ab3167e2d77e491fba82babf963ccace",
      },
    },
  },

  ramses: {
    router: "0xaaa87963efeb6f7e0a2711f397663105acb1805e",
    voter: "0xaaa2564deb34763e3d05162ed3f5c2658691f499",
    xoRAM: "0xaaa1ee8dc1864ae49185c368e8c64dd780a50fb7",
    FRAX_alUSD: {
      isStable: true,
      pairAddress: "0xfd599DB360Cd9713657C95dF66650A427d213010",
      gaugeAddress: "0x43fbf34df6da5fC66E15E023D3b690Fd0dE33cD7",
    },
    wstETH_swETH: {
      isStable: true,
      pairAddress: "0x0cb75413a9be84d0ab502c121bd603b1bf8f788f",
      gaugeAddress: "0xce831f8152db79a4ee36cb89b64333188f6801c5",
    },
    USDC_swETH: {
      isStable: false,
      pairAddress: "0xf1a5444a7ed5f24962a118512b076a015b0e6c0b",
      gaugeAddress: "0x9765cDAeC6395B04737EdC22C5b3E7d85677328A",
    },
  },

  torosPools: {
    ETHBULL3X: "0xf715724abba480d4d45f4cb52bef5ce5e3513ccc",
    BTCBULL3X: "0xad38255febd566809ae387d5be66ecd287947cb9",
  },

  zeroEx: {
    exchangeProxy: "0xdef1c0ded9bec7f1a1670819833240f027b25eff",
  },
});
