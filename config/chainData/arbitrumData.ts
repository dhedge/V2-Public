export const arbitrumChainData = Object.freeze({
  // Should be fetched from the oz file
  proxyAdmin: "0x2B15c0D49163DFdAE6024b4a3643378081aA5Fd5",

  dHEDGE: {
    daoMultisig: "0x13471A221D6A346556723842A1526C603Dc4d36B",
    treasury: "0x26f7cbd49A4DC3321780AE8e7e0cb460f55a7511",
  },

  assets: {
    weth: "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",
    usdc: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
    usdt: "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9",
    dai: "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1",
    dht: "0x8038f3c971414fd1fc220ba727f2d4a0fc98cb65",
    wsteth: "0x5979D7b546E38E414F7E9822514be443A4800529",
    bal: "0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8",
  },
  // https://docs.chain.link/data-feeds/price-feeds/addresses/?network=arbitrum
  usdPriceFeeds: {
    eth: "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
    usdc: "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
    usdt: "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7",
    dai: "0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB",
    bal: "0xBE5eA816870D11239c543F84b71439511D70B94f",
  },
  ethPriceFeeds: {
    wsteth: "0xb523AE262D20A936BC152e6023996e46FDC2A95D",
  },

  assetsBalanceOfSlot: {
    weth: 51,
    wstETH: 1,
    usdc: 51,
  },

  // https://docs.uniswap.org/contracts/v3/reference/deployments
  uniswapV3: {
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    swapRouter: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
    nonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
  },

  // https://docs.aave.com/developers/deployed-contracts/v3-mainnet/arbitrum
  aaveV3: {
    lendingPool: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
    incentives: "0x929EC64c34a17401F460460D4B9390518E5B473e",
    poolDataProvider: "0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654",
  },

  oneInch: {
    v4Router: "0x1111111254fb6c44bAC0beD2854e76F90643097d",
    v5Router: "0x1111111254EEB25477B68fb85Ed929f73A960582",
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
});
