export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
export const protocolDao = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";

// sushiswap
export const sushi = {
  factory: "0xc35DADB65012eC5796536bD9864eD8773aBc74C4",
  router: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
  minichef: "0x0769fd68dFb93167989C6f7254cd0D766Fb2841F",
  pools: {
    usdc_weth: {
      address: "0x34965ba0ac2451A34a0471F04CCa3F990b8dea27",
      poolId: 1,
    },
    weth_dht: {
      address: "0xa375d23a751124359568f3a22576528bD1C8C3e3",
    },
  },
};

// aave v2
export const aaveV2 = {
  protocolDataProvider: "0x7551b5D2763519d4e37e8B81929D336De671d46d",
  lendingPool: "0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf",
  incentivesController: "0x357D51124f59836DeD84c8a1730D72B749d8BC23",
  aTokens: {
    weth: "0x28424507fefb6f7f8E9D3860F56504E4e5f5f390",
    usdc: "0x1a13F4Ca1d028320A707D99520AbFefca3998b7F",
    usdt: "0x60D55F02A771d515e077c9C2403a1ef324885CeC",
    dai: "0x27f8d03b3a2196956ed754badc28d73be8830a6e",
  },
  variableDebtTokens: {
    dai: "0x75c4d1Fb84429023170086f06E682DcbBF537b7d",
    usdt: "0x8038857FD47108A07d1f6Bf652ef1cBeC279A2f3",
    weth: "0xeDe17e9d79fc6f9fF9250D9EEfbdB88Cc18038b5",
  },
  stableDebtTokens: {
    dai: "0x2238101B7014C279aaF6b408A284E49cDBd5DB55",
    usdt: "0xe590cfca10e81FeD9B0e4496381f02256f5d2f61",
    weth: "0xc478cBbeB590C76b01ce658f8C4dda04f30e2C6f",
  },
};

// aave v3
export const aaveV3 = {
  protocolDataProvider: "0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654",
  lendingPool: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  incentivesController: "0x929EC64c34a17401F460460D4B9390518E5B473e",
  aTokens: {
    weth: "0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8",
    usdc: "0x625E7708f30cA75bfd92586e17077590C60eb4cD",
    usdt: "0x6ab707Aca953eDAeFBc4fD23bA73294241490620",
    dai: "0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE",
    link: "0x191c10Aa4AF7C30e871E70C95dB0E4eb77237530",
  },
  variableDebtTokens: {
    usdc: "0xFCCf3cAbbe80101232d343252614b6A3eE81C989",
    dai: "0x8619d80FB0141ba7F184CbF22fd724116D9f7ffC",
    usdt: "0xfb00AC187a8Eb5AFAE4eACE434F493Eb62672df7",
    weth: "0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351",
    link: "0x953A573793604aF8d41F306FEb8274190dB4aE0e",
  },
  stableDebtTokens: {
    usdc: "0x307ffe186F84a3bc2613D1eA417A5737D69A7007",
    dai: "0xd94112B5B62d53C9402e7A60289c6810dEF1dC9B",
    usdt: "0x70eFfc565DB6EEf7B927610155602d31b670e802",
    weth: "0xD8Ad37849950903571df17049516a5CD4cbE55F6",
    link: "0x89D976629b7055ff1ca02b927BA3e020F22A44e4",
  },
};

// balancer
export const balancer = {
  v2Vault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
  merkleOrchard: "0x0F3e0c4218b7b0108a3643cFe9D3ec0d4F57c54e",
  pools: {
    // WETH, BALANCER
    bal80weth20: "0x7EB878107Af0440F9E776f999CE053D277c8Aca8",
  },
  stablePools: {
    // USDC, DAI, miMatic, USDT
    BPSP: "0x06df3b2bbb68adc8b0e302443692037ed9f91b42",
    // USDC, TUSD, DAI, USDT
    BPSP_TUSD: "0x0d34e5dd4d8f043557145598e4e2dc286b35fd4f",
  },
};

// quickswap
export const quickswap = {
  router: "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff",
  stakingRewardsFactory: "0x5eec262B05A57da9beb5FE96a34aa4eD0C5e029f",
  pools: {
    usdc_weth: {
      address: "0x853Ee4b2A13f8a742d64C8F088bE7bA2131f670d",
      stakingRewards: "0x4A73218eF2e820987c59F838906A82455F42D98b",
    },
  },
};

// uniswap V3
export const uniswapV3 = {
  factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
  router: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
  nonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
};

// Curve
export const curvePools = ["0x1d8b86e3D88cDb2d34688e87E72F388Cb541B7C8"];

// oneInch
export const oneinch = {
  v3Router: "0x1111111254fb6c44bac0bed2854e76f90643097d",
};

export const torosPools = {
  ETHBEAR2X: "0x027da30fadab6202801f97be344e2348a2a92842",
  ETHBULL3X: "0x460b60565cb73845d56564384ab84bf84c13e47d",
  BTCBEAR2X: "0x3dbce2c8303609c17aa23b69ebe83c2f5c510ada",
  BTCBULL3X: "0xdb88ab5b485b38edbeef866314f9e49d095bce39",
  BTCBEAR1X: "0x86c3dd18baf4370495d9228b58fd959771285c55",
  ETHBEAR1X: "0x79d2aefe6a21b26b024d9341a51f6b7897852499",
};

export const assets = {
  dusd: "0xbae28251b2a4e621aa7e20538c06dee010bc06de",
  wmatic: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
  wbtc: "0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6",
  weth: "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619",
  usdc: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",
  usdt: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
  dai: "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063",
  sushi: "0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a",
  balancer: "0x9a71012B13CA4d3D0Cdc72A177DF3ef03b0E76A3",
  quick: "0x831753DD7087CaC61aB5644b308642cc1c33Dc13",
  ghst: "0x385eeac5cb85a38a9a07a70c73e0a3271cfb54a7",
  dht: "0x8C92e38eCA8210f4fcBf17F0951b198Dd7668292",
  tusd: "0x2e1AD108fF1D8C782fcBbB89AAd783aC49586756",
  miMatic: "0xa3Fa99A148fA48D14Ed51d610c367C61876997F1",
  // Unsupported assets:
  xsgd: "0x769434dca303597c8fc4997bf3dab233e961eda2",
  frax: "0x45c32fA6DF82ead1e2EF74d17b76547EDdFaFF89",
  link: "0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39",
  ...torosPools,
};

export const assetsBalanceOfSlot = {
  weth: 0,
  usdc: 0,
  usdt: 0,
  dai: 0,
  dht: 0,
  wbtc: 0,
  wmatic: 0,
};

export const eth_price_feeds = {
  ghst: "0xe638249AF9642CdA55A92245525268482eE4C67b",
};

export const price_feeds = {
  matic: "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0",
  eth: "0xF9680D99D6C9589e2a93a78A04A279e509205945",
  usdc: "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7",
  usdt: "0x0A6513e40db6EB1b165753AD52E80663aeA50545",
  dai: "0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D",
  sushi: "0x49B0c695039243BBfEb8EcD054EB70061fd54aa0",
  balancer: "0xD106B538F2A868c28Ca1Ec7E298C3325E0251d66",
  tusd: "0x7C5D415B64312D38c56B54358449d0a4058339d2",
  link: "0xd9FFdb71EbE7496cC440152d43986Aae0AB76665",
};
