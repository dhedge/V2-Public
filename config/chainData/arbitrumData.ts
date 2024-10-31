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
  usdx: "0xb2F30A7C980f052f02563fb518dcc39e6bf38175", // Synthetix USD
  arb: "0x912ce59144191c1204e64559fe8253a0e49e6548",
  susdc: "0xE81Be4495f138FAE5846d21AC2cA822BEf452365", // Synthetix USDC
  tbtc: "0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40",
  stbtc: "0xFA86aB03412Ab63Fea238d43D1E839c4F7A80232", // Synthetix tBTC
  seth: "0x3Ec3FedA50b718b5A9ff387F93EeA7841D795B1E", // Synthetix ETH
  susde: "0xE3eE09c200584228F7C45d50E12BcC3fb65c19Ca", // Synthetix USDe
  usde: "0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34",
  swsol: "0x7301a8DBd293b85A06726aE12E433a829ba3B871", // Synthetix wSOL
  wsol: "0xb74Da9FE2F96B9E0a5f4A3cf0b92dd2bEC617124", // Wormhole SOL
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
    arb: "0xb2a824043730fe05f3da2efafa1cbbe83fa548d6",
    wbtc: "0x6ce185860a4963106506C203335A2910413708e9",
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
    arb: 51,
    tbtc: 51,
    usde: 5,
  },

  v2Routers: ["0x1b02da8cb0d097eb8d57a175b88c7d8b47997506"], // SushiSwap V2 Router

  routeHints: [],

  uniswapV2: {
    factory: "0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9",
  },

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

  ramsesCL: {
    nonfungiblePositionManager: "0xAA277CB7914b7e5514946Da92cb9De332Ce610EF",
    ramsesV2Factory: "0xAA2cd7477c451E703f3B9Ba5663334914763edF8",
  },

  torosPools: {
    ETHBULL3X: "0xf715724abba480d4d45f4cb52bef5ce5e3513ccc",
    BTCBULL3X: "0xad38255febd566809ae387d5be66ecd287947cb9",
    sUSDy: "0xc3198eb5102fb3335c0e911ef1da4bc07e403dd1",
    sARBy: "0xddd6b1f34e12c0230ab23cbd4514560b24438514",
    sETHy: "0xe9b5260d99d283ff887859c569baf8ad1bd12aac",
    ETHBULL2X: "0x696f6d66c2da2aa4a400a4317eec8da88f7a378c",
    BTCBULL2X: "0xe3254397f5d9c0b69917ebb49b49e103367b406f",
    ETHBEAR1X: "0x40d30b13666c55b1f41ee11645b5ea3ea2ca31f8",
    BTCBEAR1X: "0x27d8fdb0251b48d8edd1ad7bedf553cf99abe7b0",
    ETHy: "0x43DA9b0aB53242c55A9Ff9c722FfC2a373D639c7",
  },

  zeroEx: {
    exchangeProxy: "0xdef1c0ded9bec7f1a1670819833240f027b25eff",
  },

  synthetixV3: {
    core: "0xffffffaEff0B96Ea8e4f94b2253f31abdD875847",
    accountNFT: "0x0E429603D3Cb1DFae4E6F52Add5fE82d96d77Dac",
    spotMarket: "0xa65538A6B9A8442854dEcB6E3F85782C60757D60",
    perpsMarket: "0xd762960c31210Cf1bDf75b06A5192d395EEDC659",
  },

  compoundV3: {
    cUSDCv3: "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf",
    cWETHv3: "0x6f7D514bbD4aFf3BcD1140B7344b32f063dEe486",
    rewards: "0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae",
  },

  flatMoney: {
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
  },
});
