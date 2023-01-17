// https://arbiscan.io/
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

// sushiswap
// https://github.com/sushiswap/sushiswap-sdk/blob/canary/src/constants/addresses.ts
const sushi = {
  factory: "0xc35DADB65012eC5796536bD9864eD8773aBc74C4", // done
  router: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", // done
  minichef: "0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3", // done
  pools: {
    usdc_weth: {
      address: "0x905dfCD5649217c42684f23958568e533C711Aa3", //done
      poolId: 0, // @phillipe how do you get this? I had to brute force it?>??
    },
  },
};

// Searching
const assets = {
  weth: "0x82af49447d8a07e3bd95bd0d56f35241523fbab1", // done
  usdc: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8", // done
  usdt: "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9", // done
  dai: "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1", // done
  sushi: "0xd4d42f0b6def4ce0383636770ef773390d85c61a", // done
};

// https://docs.chain.link/docs/arbitrum-price-feeds/
const price_feeds = {
  eth: "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612", // done
  usdc: "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3", // done
  usdt: "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7", // done
  dai: "0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB", // done
  sushi: "0xb2A8BA74cbca38508BA1632761b56C897060147C", // done
};

module.exports = {
  ZERO_ADDRESS,
  sushi,
  assets,
  price_feeds,
};
