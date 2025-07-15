import { BigNumber } from "ethers";
import { baseChainData } from "../../config/chainData/baseData";
import { IAddresses, IFileNames } from "../types";
import { AssetType } from "../upgrade/jobs/assetsJob";
import { arbitrumChainData } from "../../config/chainData/arbitrumData";

export const FLAT_MONEY_PERP_MARKET_BOT_TEST = "0xCF51f81652779C07D08F1C7d0AcAf66E5C3b7377"; // https://dhedge.org/vault/0xcf51f81652779c07d08f1c7d0acaf66e5c3b7377

export const baseProdData: IAddresses = {
  protocolDaoAddress: baseChainData.dHEDGE.daoMultisig,
  protocolTreasuryAddress: baseChainData.dHEDGE.treasury,
  proxyAdminAddress: baseChainData.proxyAdmin,

  easySwapperConfig: {
    customLockupAllowedPools: [
      baseChainData.torosPools.sUSDCy,
      baseChainData.torosPools.STETHBULL2X,
      baseChainData.torosPools.STETHBULL3X,
      baseChainData.torosPools.STETHBULL4X,
    ], // Add here Toros pools on Base
    feeByPassManagers: ["0x5619AD05b0253a7e647Bd2E4C01c7f40CEaB0879"], // Add here Toros manager address on Base
    feeNumerator: 10,
    feeDenominator: 10000,
  },

  v2RouterAddresses: baseChainData.v2Routers,

  superSwapper: {
    routeHints: baseChainData.routeHints,
  },

  assets: {
    nativeAssetWrapper: baseChainData.assets.weth,
    weth: baseChainData.assets.weth,
    dai: baseChainData.assets.dai,
  },

  uniV2: {
    factory: baseChainData.uniswapV2.factory,
  },

  uniV3: {
    uniswapV3FactoryAddress: baseChainData.uniswapV3.factory,
    uniswapV3RouterAddress: baseChainData.uniswapV3.router,
  },

  oneInchV5RouterAddress: baseChainData.oneInch.v5Router,
  oneInchV6RouterAddress: baseChainData.oneInch.v6Router,

  velodrome: {
    factoryV2: baseChainData.aerodrome.factory,
    routerV2: baseChainData.aerodrome.router,
    voterV2: baseChainData.aerodrome.voter,
  },

  velodromeCL: {
    nonfungiblePositionManager: baseChainData.aerodromeCL.nonfungiblePositionManager,
    factory: baseChainData.aerodromeCL.factory,
    voter: baseChainData.aerodrome.voter,
    enabledGauges: [
      "0xBd85D45f1636fCEB2359d9Dcf839f12b3cF5AF3F", // CL1-USDC/USDT
      "0x2A1f7bf46bd975b5004b61c6040597E1B6117040", // CL1-WETH/wstETH
      "0x1f6c9d116CE22b51b0BC666f86B038a6c19900B8", // CL50-EURC/USDC
      "0x41b2126661C673C2beDd208cC72E85DC51a5320a", // CL100-WETH/cbBTC
      "0x6399ed6725cC163D019aA64FF55b22149D7179A8", // CL100-USDC/cbBTC
      "0xB57eC27f68Bd356e300D57079B6cdbe57d50830d", // CL1-tBTC/cbBTC
      "0xe2a2B1D8AA4bD8A05e517Ccf61E96A727831B63e", // CL1-USDS/USDC
    ],
  },

  zeroExExchangeProxy: baseChainData.zeroEx.exchangeProxy,

  synthetixV3: {
    core: baseChainData.synthetixV3.core,
    dHedgeVaultsWhitelist: [
      {
        poolLogic: baseChainData.torosPools.sUSDCy,
        collateralAsset: baseChainData.assets.susdc,
        debtAsset: baseChainData.assets.snxUSD,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: "0xE404FA05a4298dC657EA826ddAEec8BD630e414A", // Synthetix USDC Yield Test https://dhedge.org/vault/0xe404fa05a4298dc657ea826ddaeec8bd630e414a
        collateralAsset: baseChainData.assets.susdc,
        debtAsset: baseChainData.assets.snxUSD,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: baseChainData.torosPools.FAy, // Funding Arbitrage Yield https://dhedge.org/vault/0xd258da1a96c53676301b60000918a1406e367d3e
        collateralAsset: baseChainData.assets.susdc,
        debtAsset: baseChainData.assets.snxUSD,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: "0x5334d0184a11f210de806fcd5b556bf19981a7be", // Flat Money Market Maker https://dhedge.org/vault/0x5334d0184a11f210de806fcd5b556bf19981a7be
        collateralAsset: baseChainData.assets.susdc,
        debtAsset: baseChainData.assets.snxUSD,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: FLAT_MONEY_PERP_MARKET_BOT_TEST,
        collateralAsset: baseChainData.assets.susdc,
        debtAsset: baseChainData.assets.snxUSD,
        snxLiquidityPoolId: 1,
      },
      {
        poolLogic: "0xa1a0fcc73689549b244e9938d71b6638e18032d7", // Synthetix V3 Perps Bot Test https://dhedge.org/vault/0xa1a0fcc73689549b244e9938d71b6638e18032d7
        collateralAsset: baseChainData.assets.susdc,
        debtAsset: baseChainData.assets.snxUSD,
        snxLiquidityPoolId: 1,
      },
    ],
    spotMarket: baseChainData.synthetixV3.spotMarket,
    perpsMarket: baseChainData.synthetixV3.perpsMarket,
    perpsWithdrawAsset: baseChainData.assets.usdc,
    allowedMarkets: [
      {
        marketId: 1,
        collateralSynth: baseChainData.assets.susdc,
        collateralAsset: baseChainData.assets.usdc,
        atomicSwapSettings: {
          isAtomicSwapAllowed: true,
          isOneToOneSwap: true,
        },
      },
      {
        marketId: 4,
        collateralSynth: "0xEDE1d04C864EeEC40393ED4cb454B85A5ABD071C", // Synthetic Coinbase Wrapped BTC https://basescan.org/address/0xEDE1d04C864EeEC40393ED4cb454B85A5ABD071C
        collateralAsset: baseChainData.assets.cbbtc,
        atomicSwapSettings: {
          isAtomicSwapAllowed: false,
          isOneToOneSwap: false,
        },
      },
      {
        marketId: 6,
        collateralSynth: "0xFA24Be208408F20395914Ba82Def333d987E0080", // Synthetic Wrapped ETH https://basescan.org/address/0xFA24Be208408F20395914Ba82Def333d987E0080
        collateralAsset: baseChainData.assets.weth,
        atomicSwapSettings: {
          isAtomicSwapAllowed: false,
          isOneToOneSwap: false,
        },
      },
      {
        marketId: 7,
        collateralSynth: "0x3526D453D1Edb105E4e2b8448760fC501050d976", // Synthetic Lido Wrapped Staked ETH https://basescan.org/address/0x3526D453D1Edb105E4e2b8448760fC501050d976
        collateralAsset: baseChainData.assets.wsteth,
        atomicSwapSettings: {
          isAtomicSwapAllowed: false,
          isOneToOneSwap: false,
        },
      },
    ],
    windows: {
      delegationWindow: {
        start: {
          dayOfWeek: 2,
          hour: 0,
        },
        end: {
          dayOfWeek: 4,
          hour: 12,
        },
      },
      undelegationWindow: {
        start: {
          dayOfWeek: 4,
          hour: 12,
        },
        end: {
          dayOfWeek: 7,
          hour: 23,
        },
      },
    },
    withdrawalLimit: {
      usdValue: BigNumber.from(50_000).mul(BigNumber.from(10).pow(18)), // $50k
      percent: BigNumber.from(100).mul(BigNumber.from(10).pow(16)), // 100%
    },
  },

  aaveV3: {
    aaveLendingPoolAddress: baseChainData.aaveV3.lendingPool,
    aaveIncentivesControllerAddress: baseChainData.aaveV3.incentivesController,
  },

  flatMoney: {
    delayedOrder: baseChainData.flatMoney.delayedOrder,
    perpMarketWhitelistedVaults: [
      {
        poolLogic: baseChainData.torosPools.FAy, // Funding Arbitrage Yield https://dhedge.org/vault/0xd258da1a96c53676301b60000918a1406e367d3e
        withdrawalAsset: baseChainData.assets.usdc,
      },
      {
        poolLogic: "0x5334d0184a11f210de806fcd5b556bf19981a7be", // Flat Money Market Maker https://dhedge.org/vault/0x5334d0184a11f210de806fcd5b556bf19981a7be
        withdrawalAsset: baseChainData.assets.reth,
      },
      {
        poolLogic: FLAT_MONEY_PERP_MARKET_BOT_TEST,
        withdrawalAsset: baseChainData.assets.usdc,
      },
      {
        poolLogic: "0xa1a0fcc73689549b244e9938d71b6638e18032d7", // Synthetix V3 Perps Bot Test https://dhedge.org/vault/0xa1a0fcc73689549b244e9938d71b6638e18032d7
        withdrawalAsset: baseChainData.assets.reth,
      },
      {
        poolLogic: baseChainData.torosPools.STETHBULL2X,
        withdrawalAsset: baseChainData.assets.reth,
      },
      {
        poolLogic: baseChainData.torosPools.STETHBULL3X,
        withdrawalAsset: baseChainData.assets.reth,
      },
      {
        poolLogic: baseChainData.torosPools.STETHBULL4X,
        withdrawalAsset: baseChainData.assets.reth,
      },
      {
        poolLogic: "0x631d238c4Fd232c14BF318174711538f737C0c7c", // Ethereum Surge https://dhedge.org/vault/0x631d238c4Fd232c14BF318174711538f737C0c7c
        withdrawalAsset: baseChainData.assets.reth,
      },
    ],
    swapper: baseChainData.flatMoney.swapper,
  },

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  rewardAssetSetting: [
    {
      rewardToken: baseChainData.aerodrome.aero,
      linkedAssetTypes: [
        AssetType["Velodrome V2 LP/Gauge Asset"], // 25
        AssetType["Velodrome CL NFT Position Asset"], // 26
      ],
    },
  ],

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      baseChainData.torosPools.sUSDCy,
      baseChainData.torosPools.STETHBULL2X,
      baseChainData.torosPools.STETHBULL3X,
      baseChainData.torosPools.STETHBULL4X,
      "0xCC4D4e673046e843C0E41ED150aD7a4be95b62ea", // SwapperTest https://dhedge.org/vault/0xcc4d4e673046e843c0e41ed150ad7a4be95b62ea
      baseChainData.torosPools.USDy,
      baseChainData.torosPools.USDMNY,
      baseChainData.torosPools.BTCBEAR1X,
      baseChainData.torosPools.BTCBULL2X,
      baseChainData.torosPools.BTCBULL3X,
    ],
  },

  angleProtocol: {
    distributor: "0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae",
    rewardTokenSupported: "0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB",
  },

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: baseChainData.assets.usdc,
    authorizedKeeperAddresses: [
      "0xfF5C66B0799bb1cD834e2178866225F020A87A7f",
      "0xD411D209d3C602bdB7F99A16775A2e30aEb51009",
      "0xc804F6F95973f3380D8f52fd7aFF475337e2eea2",
      "0x83336A07e2257c537EfcA180E9c89819fa40ECCd",
      "0xfB2f4AE9584c82d3dB9Cd00B5CB664c8cf44470B",
    ],
  },

  pancakeswap: {
    nonfungiblePositionManager: "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
    masterChefV3: "0xC6A2Db661D5a5690172d8eB0a7DEA2d3008665A3",
  },

  sky: {
    psm3: "0x1601843c5E9bC251A3272907010AFa41Fa18347E",
  },

  across: {
    spokePool: "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64",
    approvedDestinations: [
      {
        sourcePool: FLAT_MONEY_PERP_MARKET_BOT_TEST,
        sourceToken: baseChainData.assets.usdc,
        destinationChainId: 42161,
        destinationPool: arbitrumChainData.gmxTestVaults.gmxTest2,
        destinationToken: arbitrumChainData.assets.usdcNative,
      },
      {
        sourcePool: FLAT_MONEY_PERP_MARKET_BOT_TEST,
        sourceToken: baseChainData.assets.usdc,
        destinationChainId: 42161,
        destinationPool: arbitrumChainData.gmxTestVaults.gmxTest6,
        destinationToken: arbitrumChainData.assets.usdcNative,
      },
    ],
  },

  odosV2RouterAddress: baseChainData.odosEx.v2Router,

  compoundV3: {
    rewards: baseChainData.compoundV3.rewards,
  },
};

export const baseProdFileNames: IFileNames = {
  versionsFileName: "./publish/base/prod/versions.json",
  assetsFileName: "./config/base/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/base/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/base/dHEDGE Governance Contract Guards.csv",
  governanceNamesFileName: "./config/base/dHEDGE Governance Names.csv",
  deprecatedContractGuardsFileName: "./config/base/dHEDGE Deprecated Contract Guards.csv",
} as const;
