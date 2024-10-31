import { BigNumber } from "ethers";
import { baseChainData } from "../../config/chainData/baseData";
import { IAddresses } from "../types";

export const baseProdData: IAddresses = {
  protocolDaoAddress: baseChainData.dHEDGE.daoMultisig,
  protocolTreasuryAddress: baseChainData.dHEDGE.treasury,
  proxyAdminAddress: baseChainData.proxyAdmin,

  // Gnosis safe multicall/send address
  // https://github.com/gnosis/safe-deployments
  gnosisMultiSendAddress: "0x998739BFdAAdde7C933B942a68053933098f9EDa",
  gnosisApi: "https://safe-transaction-base.safe.global",

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
        poolLogic: "0xcf51f81652779c07d08f1c7d0acaf66e5c3b7377", // Flat Money Perp Market Bot Test https://dhedge.org/vault/0xcf51f81652779c07d08f1c7d0acaf66e5c3b7377
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
          dayOfWeek: 5,
          hour: 0,
        },
      },
    },
    withdrawalLimit: {
      usdValue: BigNumber.from(50_000).mul(BigNumber.from(10).pow(18)), // $50k
      percent: BigNumber.from(25).mul(BigNumber.from(10).pow(16)), // 25%
    },
  },

  aaveV3: {
    aaveLendingPoolAddress: baseChainData.aaveV3.lendingPool,
    aaveProtocolDataProviderAddress: baseChainData.aaveV3.protocolDataProvider,
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
        poolLogic: "0xcf51f81652779c07d08f1c7d0acaf66e5c3b7377", // Flat Money Perp Market Bot Test https://dhedge.org/vault/0xcf51f81652779c07d08f1c7d0acaf66e5c3b7377
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
        26, // "Velodrome CL NFT Position Asset" = 26
      ],
      underlyingAssetType: 0, //   "Chainlink direct USD price feed with 8 decimals" = 0
    },
  ],

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      baseChainData.torosPools.sUSDCy,
      baseChainData.torosPools.STETHBULL2X,
      baseChainData.torosPools.STETHBULL3X,
      baseChainData.torosPools.STETHBULL4X,
      "0xCC4D4e673046e843C0E41ED150aD7a4be95b62ea", // SwapperTest https://dhedge.org/vault/0xcc4d4e673046e843c0e41ed150ad7a4be95b62ea
    ],
  },
};

export const baseProdFileNames = {
  versionsFileName: "./publish/base/prod/versions.json",
  assetsFileName: "./config/base/dHEDGE Assets list.json",
  assetGuardsFileName: "./config/base/dHEDGE Governance Asset Guards.csv",
  contractGuardsFileName: "./config/base/dHEDGE Governance Contract Guards.csv",
  governanceNamesFileName: "./config/base/dHEDGE Governance Names.csv",
  deprecatedContractGuardsFileName: "./config/base/dHEDGE Deprecated Contract Guards.csv",
} as const;
