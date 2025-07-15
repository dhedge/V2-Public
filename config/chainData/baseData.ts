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
    usdbc: "0xd9aaec86b65d86f6a7b5b1b0c42ffa531710b6ca",
    reth: "0xb6fe221fe9eef5aba221c348ba20a1bf5e73624c",
    snx: "0x22e6966b799c4d5b13be962e1d117b56327fda66",
    unit: "0xb95fB324b8A2fAF8ec4f76e3dF46C718402736e2",
    cbbtc: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
    wsteth: "0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452",
  },

  // https://data.chain.link/
  usdPriceFeeds: {
    dai: "0x591e79239a7d679378ec8c847e5038150364c78f",
    eth: "0x71041dddad3595f9ced3dccfbe3d1f4b0a16bb70",
    usdc: "0x7e860098f58bbfc8648a4311b374b1d669a2bc6b",
    usdt: "0xf19d560eb8d2adf07bd6d13ed03e1d11215721f9",
    usdbc: "0x7e860098f58bbfc8648a4311b374b1d669a2bc6b",
    snx: "0xe3971Ed6F1A5903321479Ef3148B5950c0612075",
    reth: "0x4aF79bbBd345ae56D9e9Af4482e77CB4EB98e85e",
  },

  assetsBalanceOfSlot: {
    usdc: 9,
    dai: 0,
    weth: 3,
    usdbc: 51,
    reth: 0,
  },

  uniswapV2: {
    factory: "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6",
  },

  // https://docs.uniswap.org/contracts/v3/reference/deployments
  uniswapV3: {
    factory: "0x33128a8fC17869897dcE68Ed026d694621f6FDfD",
    router: "0x2626664c2603336E57B271c5C0b26F421741e481",
  },

  oneInch: {
    v5Router: "0x1111111254EEB25477B68fb85Ed929f73A960582",
    v6Router: "0x111111125421ca6dc452d289314280a0f8842a65",
  },

  zeroEx: {
    exchangeProxy: "0xdef1c0ded9bec7f1a1670819833240f027b25eff",
  },

  odosEx: {
    v2Router: "0x19cEeAd7105607Cd444F5ad10dd51356436095a1",
  },

  synthetixV3: {
    core: "0x32C222A9A159782aFD7529c87FA34b96CA72C696",
    accountNFT: "0x63f4Dd0434BEB5baeCD27F3778a909278d8cf5b8",
    spotMarket: "0x18141523403e2595D31b22604AcB8Fc06a4CaA61",
    perpsMarket: "0x0A2AF931eFFd34b81ebcc57E3d3c9B1E1dE1C9Ce",
    perpsAccountNFT: "0xcb68b813210afa0373f076239ad4803f8809e8cf",
  },

  aerodrome: {
    aero: "0x940181a94a35a4569e4529a3cdfb74e38fd98631",
    voter: "0x16613524e02ad97eDfeF371bC883F2F5d6C480A5",
    factory: "0x420DD381b31aEf6683db6B902084cB0FFECe40Da",
    router: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
    VARIABLE_WETH_USDC: {
      isStable: false,
      poolAddress: "0xcDAC0d6c6C59727a65F871236188350531885C43",
      gaugeAddress: "0x519BBD1Dd8C6A94C46080E24f316c14Ee758C025",
    },
    VARIABLE_AERO_USDC: {
      isStable: false,
      poolAddress: "0x6cDcb1C4A4D1C3C6d054b27AC5B77e89eAFb971d",
      gaugeAddress: "0x4F09bAb2f0E15e2A078A227FE1537665F55b8360",
    },
    STABLE_USDC_DAI: {
      isStable: true,
      poolAddress: "0x67b00B46FA4f4F24c03855c5C8013C0B938B3eEc",
      gaugeAddress: "0x640e9ef68e1353112fF18826c4eDa844E1dC5eD0",
    },
  },

  aerodromeCL: {
    nonfungiblePositionManager: "0x827922686190790b37229fd06084350E74485b72",
    factory: "0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A",
  },

  aaveV3: {
    lendingPool: "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5",
    protocolDataProvider: "0x2d8A3C5677189723C4cB8873CfC9C8976FDF38Ac",
    incentivesController: "0xf9cc4F0D883F1a1eb2c253bdb46c254Ca51E1F44",
  },

  v2Routers: ["0x6bded42c6da8fbf0d2ba55b2fa120c5e0c8d7891"], // SushiSwap V2 Router

  routeHints: [],

  flatMoney: {
    delayedOrder: "0x6D857e9D24a7566bB72a3FB0847A3E0e4E1c2879",
    viewer: "0x509b85EEF0df77992b29aeDdD22C7119Db87ce16",
    pointsModule: "0x59525b9b23ADc475EF91d98dAe06B568BA574Ce5",
    leverageModule: "0xdB0Cd65dcc7fE07003cE1201f91E1F966fA95768",
    oracleModule: "0xaba633927bd8622fbbdd35d291a914c2fdaae1ff",
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
  },

  torosPools: {
    USDMNY: "0xede61eefa4850b459e3b09fe6d8d371480d6ff00",
    sUSDCy: "0xc1e02884af4a283ca25ab63c45360d220d69da52",
    STETHBULL2X: "0xa672e882acbb96486393d43e0efdab5ebebddc1d",
    STETHBULL3X: "0x15e2f06138aed58ca2a6afb5a1333bbc5f728f80",
    STETHBULL4X: "0xba5f6a0d2ac21a3fec7a6c40facd23407aa84663",
    ETHy: "0x53a4716a8f7dbc9543ebf9cd711952033cc64d43",
    FAy: "0xd258da1a96c53676301b60000918a1406e367d3e",
    USDy: "0x1c980456751AE40315Ff73CaaC0843Be643321Be",
    BTCBEAR1X: "0xd2f23773bf5e2d59f6bb925c2232f6e83f3f79e0",
    BTCBULL2X: "0x9e0501537723c71250307F5B1A8eE60e167D21C9",
    BTCBULL3X: "0xCAF08BF08D0c87e2c74dd9EBEC9C776037bD7e8E",
  },

  compoundV3: {
    cUSDCv3: "0xb125E6687d4313864e53df431d5425969c15Eb2F",
    cWETHv3: "0x46e6b214b524310239732D51387075E0e70970bf",
    rewards: "0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1",
  },
});
