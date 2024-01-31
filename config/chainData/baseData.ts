export const baseChainData = Object.freeze({
  // Should be fetched from the oz file
  proxyAdmin: "0xD3113A115676EaF2c33bc40C336aa0595CbC8BDa",

  // Created before new chain deployment
  dHEDGE: {
    daoMultisig: "0x4A83129Ce9C8865EF3f91Fc87130dA25b64F9100",
    treasury: "0xEE27793EBAf6a446c74C2cDd23Bba615e9472264",
  },

  assets: {
    dai: "0x50c5725949a6f0c72e6c4a641f24049a917db0cb",
    weth: "0x4200000000000000000000000000000000000006",
    usdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    susdc: "0xC74eA762cF06c9151cE074E6a569a5945b6302E7",
    snxUSD: "0x09d51516F38980035153a554c26Df3C6f51a23C3",
  },

  // https://data.chain.link/
  usdPriceFeeds: {
    dai: "0x591e79239a7d679378ec8c847e5038150364c78f",
    eth: "0x71041dddad3595f9ced3dccfbe3d1f4b0a16bb70",
    usdc: "0x7e860098f58bbfc8648a4311b374b1d669a2bc6b",
    usdt: "0xf19d560eb8d2adf07bd6d13ed03e1d11215721f9",
  },

  assetsBalanceOfSlot: {},

  // https://docs.uniswap.org/contracts/v3/reference/deployments
  uniswapV3: {
    factory: "0x33128a8fC17869897dcE68Ed026d694621f6FDfD",
    swapRouter: "0x2626664c2603336E57B271c5C0b26F421741e481",
  },

  oneInch: {
    v5Router: "0x1111111254EEB25477B68fb85Ed929f73A960582",
  },

  velodromeV2: {
    factory: "0x420DD381b31aEf6683db6B902084cB0FFECe40Da",
    router: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
  },

  zeroEx: {
    exchangeProxy: "0xdef1c0ded9bec7f1a1670819833240f027b25eff",
  },

  synthetixV3: {
    core: "0x32C222A9A159782aFD7529c87FA34b96CA72C696",
    accountNFT: "0x63f4Dd0434BEB5baeCD27F3778a909278d8cf5b8",
    spotMarket: "0x18141523403e2595D31b22604AcB8Fc06a4CaA61",
  },
});
