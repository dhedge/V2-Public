import { Address } from "../../deployment-scripts/types";

export interface ChainDataCommon {
  proxyAdmin: Address;
  ZERO_ADDRESS: Address;
  protocolDao: Address;

  v2Routers: Address[];

  arrakis: {
    v1RouterStaking: Address;
    usdcWethGauge: Address;
  };

  aaveV3: {
    protocolDataProvider: Address;
    lendingPool: Address;
    incentivesController: Address;
    aTokens: {
      weth: Address;
      usdc: Address;
      usdt: Address;
      dai: Address;
      link: Address;
    };
    variableDebtTokens: {
      usdc: Address;
      dai: Address;
      usdt: Address;
      weth: Address;
      link: Address;
    };
    stableDebtTokens: {
      usdc: Address;
      dai: Address;
      usdt: Address;
      weth: Address;
      link: Address;
    };
  };

  uniswapV3: {
    factory: Address;
    router: Address;
    nonfungiblePositionManager: Address;
    pools: Record<string, Address>;
  };

  curvePools: Address[];

  oneinch: {
    v4Router: Address;
    v5Router: Address;
  };

  assets: {
    susd?: string;
    snxProxy?: string;
    usdc: string;
    weth: string;
    dai: string;
    dht: string;
  };

  assetsBalanceOfSlot: { usdc: number; weth: number; dai: number } & Record<string, number>;

  eth_price_feeds: Record<string, Address>;
  price_feeds: Record<string, Address>;

  velodrome?: {
    velo: string;
    voter: string;
    factory: string;
    router: string;
  };
}

export interface ChainDataOVM extends ChainDataCommon {
  assets: {
    susd: string;
    seth: string;
    sbtc: string;
    slink: string;
    snxProxy: string;
    usdc: string;
    usdt: string;
    weth: string;
    dai: string;
    wbtc: string;
    dht: string;
    op: Address;
  };
  uniswapV3: {
    factory: Address;
    router: Address;
    nonfungiblePositionManager: Address;
    pools: {
      susd_dai: Address;
    };
  };

  synthetix: {
    addressResolver: Address;
    snxProxy: Address;
    susdKey: Address;
    sethKey: Address;
    slinkKey: Address;
    // This is where the balances are stored for SUSD
    // We need to use this for getTokenAccount
    sUSDProxy_target_tokenState: Address;
  };

  futures: {
    futuresMarketSettings: Address;
    ethMarket: Address;
  };

  zipswap: {
    factory: Address;
    router: Address;
  };

  lyra: {
    dhedgeLyraWrapper?: string;
    optionMarketWrapper: string;
    synthetixAdapter: string;
    optionMarketViewer: string;
    lyraRegistry: string;
    quoter: string;
  };

  torosPools: {
    USDY: Address;
  };

  velodrome: {
    velo: string;
    voter: string;
    factory: string;
    router: string;
    VARIABLE_WETH_USDC: {
      isStable: boolean;
      poolAddress: string;
      gaugeAddress: string;
    };
    VARIABLE_VELO_USDC: {
      isStable: boolean;
      poolAddress: string;
      gaugeAddress: string;
    };
    STABLE_USDC_DAI: {
      isStable: boolean;
      poolAddress: string;
      gaugeAddress: string;
    };
  };
}

export interface ChainDataPolygon extends ChainDataCommon {
  balancer: {
    v2Vault: Address;
    merkleOrchard: Address;
    pools: {
      bal80weth20: Address;
    };
    stableComposablePools: {
      wMaticStMatic: Address;
      wMaticMaticX: Address;
    };
    stablePools: {
      BPSP: Address;
      BPSP_TUSD: Address;
    };
    gaugePools: {
      stMATIC: {
        pool: Address;
        gauge: Address;
      };
      maticX: {
        pool: Address;
        gauge: Address;
      };
    };
  };

  sushi: {
    factory: Address;
    router: Address;
    minichef: Address;
    pools: {
      usdc_weth: {
        address: Address;
        poolId: 1;
      };
      weth_dht: {
        address: Address;
      };
    };
  };

  aaveV2: {
    protocolDataProvider: Address;
    lendingPool: Address;
    incentivesController: Address;
    aTokens: {
      weth: Address;
      usdc: Address;
      usdt: Address;
      dai: Address;
    };
    variableDebtTokens: {
      dai: Address;
      usdt: Address;
      weth: Address;
    };
    stableDebtTokens: {
      dai: Address;
      usdt: Address;
      weth: Address;
    };
  };

  quickswap: {
    router: Address;
    stakingRewardsFactory: Address;
    pools: {
      usdc_weth: {
        address: Address;
        stakingRewards: Address;
      };
    };
    dQUICK: Address;
  };

  eth_price_feeds: {
    ghst: Address;
  };

  torosPools: {
    ETHBEAR2X: Address;
    ETHBULL3X: Address;
    BTCBEAR2X: Address;
    BTCBULL3X: Address;
    BTCBEAR1X: Address;
    ETHBEAR1X: Address;
    USDY: Address;
  };

  assets: {
    dusd: Address;
    wmatic: Address;
    wbtc: Address;
    weth: Address;
    usdc: Address;
    usdt: Address;
    dai: Address;
    sushi: Address;
    balancer: Address;
    quick: Address;
    ghst: Address;
    dht: Address;
    tusd: Address;
    miMatic: Address;
    stMatic: Address;
    // No chainlink feed, unsupported
    maticX: Address;
    xsgd: Address;
    frax: Address;
    link: Address;
  };

  price_feeds: {
    miMatic: Address;
    matic: Address;
    stMatic: Address;
    eth: Address;
    usdc: Address;
    usdt: Address;
    dai: Address;
    sushi: Address;
    balancer: Address;
    tusd: Address;
    link: Address;
    quick: Address;
  };

  assetsBalanceOfSlot: {
    weth: number;
    usdc: number;
    usdt: number;
    dai: number;
    dht: number;
    wbtc: number;
    wmatic: number;
    miMatic: number;
    stMatic: number;
  };

  maticX: {
    maticXPool: Address;
  };
}
