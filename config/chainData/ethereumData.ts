export const ethereumChainData = Object.freeze({
  // Should be fetched from the oz file
  proxyAdmin: "0xad17E5020954eB3c6d77be9DCDF9DBAB44EdD16E",

  // For protocol upgrades
  protocolDao: "0x5a76f841bFe5182f04bf511fC0Ecf88C27189FCB",

  // For protocol fees
  protocolTreasury: "0xfF44B48abad9cb7A2485f829E5c9A4d1cee623c9",

  assets: {
    weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    usde: "0x4c9EDD5852cd905f086C759E8383e09bff1E68B3",
    susde: "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497",
  },

  oneInch: {
    v6Router: "0x111111125421cA6dc452d289314280a0f8842A65",
  },

  uniswapV2: {
    factory: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
  },

  uniswapV3: {
    factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
    router: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
  },

  swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",

  aaveV3: {
    lendingPool: "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
  },
});
