import { BigNumber } from "ethers";
import { ovmChainData } from "../../config/chainData/ovmData";
import { IAddresses, IFileNames } from "../types";
import { AssetType } from "../upgrade/jobs/assetsJob";
import { arbitrumChainData } from "../../config/chainData/arbitrumData";

const { torosPools } = ovmChainData;

export const optimismProdData: IAddresses = {
  // old - https://ogg.scopelift.co/wallet/0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08
  // https://gnosis-safe.io/app/oeth:0x90b1a66957914EbbE7a8df254c0c1E455972379C/balances - 3/3
  protocolDaoAddress: ovmChainData.protocolDao,
  // old - https://ogg.scopelift.co/wallet/0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc
  // https://gnosis-safe.io/app/oeth:0xD857e322351Dc56592e3D9181FBF65034EF4aef2 2/5
  protocolTreasuryAddress: "0xD857e322351Dc56592e3D9181FBF65034EF4aef2",
  // Should be fetched from the oz file
  proxyAdminAddress: ovmChainData.proxyAdmin,

  synthetixProxyAddress: ovmChainData.assets.snxProxy,

  easySwapperConfig: {
    customLockupAllowedPools: Object.values(torosPools).concat([
      // Metrix Atlas Liquid Token Fund I
      "0xb52eac0899caf6291c62e9aec06668861138b13b",
      // Metrix Ananke Liquid Token Fund I
      "0xc6f2737e456aa7829934aa7eda2f9ade19672c74",
      // Metrix Nyx Liquid Token Fund I
      "0xafafb723b640b5ce1e20036ea74b4886e31fc4de",
    ]),
    feeByPassManagers: [
      // Toros
      "0x813123a13d01d3f07d434673fdc89cbba523f14d",
      // Metrix
      "0x625c96542b19e48f2eeebad263738828651c6b19",
    ],
    feeNumerator: 10, // 0.1% buy fee to enable Stablecoin Yield buys by managers at low cost and without need for secondary market
    feeDenominator: 10000,
  },

  uniV2: {
    factory: ovmChainData.uniswapV2.factory,
  },

  uniV3: {
    uniswapV3RouterAddress: ovmChainData.uniswapV3.router,
    uniSwapV3NonfungiblePositionManagerAddress: ovmChainData.uniswapV3.nonfungiblePositionManager,
    uniswapV3FactoryAddress: ovmChainData.uniswapV3.factory,
  },

  assets: {
    nativeAssetWrapper: ovmChainData.assets.weth,
    dai: ovmChainData.assets.dai,
    usdc: ovmChainData.assets.usdc,
    weth: ovmChainData.assets.weth,
    dht: ovmChainData.assets.dht,
    susd: ovmChainData.assets.susd,
  },

  oneInchV4RouterAddress: ovmChainData.oneinch.v4Router,
  oneInchV5RouterAddress: ovmChainData.oneinch.v5Router,
  oneInchV6RouterAddress: ovmChainData.oneinch.v6Router,

  aaveV3: {
    aaveLendingPoolAddress: ovmChainData.aaveV3.lendingPool,
    aaveIncentivesControllerAddress: ovmChainData.aaveV3.incentivesController,
  },

  stakingV2: {
    dhtCap: BigNumber.from(7_000_000).mul(BigNumber.from(10).pow(18)),
    emissionsRate: 1000,
    whitelistedPools: [
      // Optimism	Stablecoin Yield	https://app.dhedge.org/pool/0x1ec50880101022c11530a069690f5446d1464592	$500,000
      {
        pool: torosPools.USDY,
        cap: BigNumber.from(500_000).mul(BigNumber.from(10).pow(18)),
      },
      // Optimism	Ethereum Yield	https://app.dhedge.org/pool/0xb2cfb909e8657c0ec44d3dd898c1053b87804755	$200,000
      {
        pool: torosPools.ETHY,
        cap: BigNumber.from(200_000).mul(BigNumber.from(10).pow(18)),
      },
      // Optimism	USD Market Neutral Yield	https://app.dhedge.org/pool/0x49bf093277bf4dde49c48c6aa55a3bda3eedef68	$100,000
      {
        pool: torosPools.USDMNY,
        cap: BigNumber.from(100_000).mul(BigNumber.from(10).pow(18)),
      },
      // Optimism	Dybart Izak	https://app.dhedge.org/pool/0x6ae8d896b32c71107d1a49af212bc70892a06720	$25,000
      {
        pool: "0x6ae8d896b32c71107d1a49af212bc70892a06720",
        cap: BigNumber.from(25_000).mul(BigNumber.from(10).pow(18)),
      },
      // Optimism	Apollo Partners	https://app.dhedge.org/pool/0x2fbd33f07d414be3e3e112916504b9bdc5617b69	$25,000
      {
        pool: "0x2fbd33f07d414be3e3e112916504b9bdc5617b69",
        cap: BigNumber.from(25_000).mul(BigNumber.from(10).pow(18)),
      },
      // Optimism	Momentum Ensemble	https://app.dhedge.org/pool/0x178175f4092d6ba11a8372ee968dc34704397a62	$25,000
      {
        pool: "0x178175f4092d6ba11a8372ee968dc34704397a62",
        cap: BigNumber.from(25_000).mul(BigNumber.from(10).pow(18)),
      },
      // Optimism	Test Pool	https://app.dhedge.org/pool/0x65f034fd3a83f3f5dabc942b2666dd875140e311	$1,000
      {
        pool: "0x65f034fd3a83f3f5dabc942b2666dd875140e311",
        cap: BigNumber.from(1000).mul(BigNumber.from(10).pow(18)),
      },
      // SNX Debt Mirror https://app.dhedge.org/pool/0x59babc14dd73761e38e5bda171b2298dc14da92d $100,000
      {
        pool: "0x59babc14dd73761e38e5bda171b2298dc14da92d",
        cap: BigNumber.from(100_000).mul(BigNumber.from(10).pow(18)),
      },
      // DHT Vault https://app.dhedge.org/pool/0x7ede23e5061588402664fb14d8266422637dba20 $800,000
      {
        pool: "0x7ede23e5061588402664fb14d8266422637dba20",
        cap: BigNumber.from(800_000).mul(BigNumber.from(10).pow(18)),
      },
      // Horizons Strategy Optimism https://app.dhedge.org/pool/0x56da1e11923b298d70dae1b4749f4cdd56a02532 $10,000
      {
        pool: "0x56da1e11923b298d70dae1b4749f4cdd56a02532",
        cap: BigNumber.from(10_000).mul(BigNumber.from(10).pow(18)),
      },
      // DHT Liquidity Yield https://app.dhedge.org/pool/0x5aff2c03dacad38a2d47af8365b2fbbd5db2ed59 $500,000
      {
        pool: "0x5aff2c03dacad38a2d47af8365b2fbbd5db2ed59",
        cap: BigNumber.from(500_000).mul(BigNumber.from(10).pow(18)),
      },
      // Perpetual Delta Neutral Yield https://app.dhedge.org/vault/0xb9243c495117343981ec9f8aa2abffee54396fc0 $100,000
      {
        pool: ovmChainData.torosPools.USDpy,
        cap: BigNumber.from(100_000).mul(BigNumber.from(10).pow(18)),
      },
      // Ethereum Savings Account https://dhedge.org/vault/0xa2ffe6ed599e8f7aac8047f5ee0de3d83de1b320 $25,000
      {
        pool: "0xa2ffe6ed599e8f7aac8047f5ee0de3d83de1b320",
        cap: BigNumber.from(25_000).mul(BigNumber.from(10).pow(18)),
      },
    ],
  },

  lyra: {
    lyraRegistry: "0xF5A0442D4753cA1Ea36427ec071aa5E786dA5916",
  },

  velodrome: {
    router: ovmChainData.velodrome.router,
    voter: ovmChainData.velodrome.voter,
    routerV2: ovmChainData.velodromeV2.router,
    voterV2: ovmChainData.velodromeV2.voter,
    factoryV2: ovmChainData.velodromeV2.factory,
  },

  velodromeCL: {
    nonfungiblePositionManager: ovmChainData.velodromeCL.nonfungiblePositionManager,
    nonfungiblePositionManagerOld: ovmChainData.velodromeCL.nonfungiblePositionManagerOld,
    factory: ovmChainData.velodromeCL.factory,
    voter: ovmChainData.velodromeV2.voter, // same as the v2 voter
    enabledGauges: [
      "0x15D715C142169bf93BC6C8C670C208dC3ACCe17e", // CL1-USDC/sUSD
      "0xa75127121d28a9BF848F3B70e7Eea26570aa7700", // CL100-USDC/WETH
      "0x09f9E0E05c0a66248F3c098C2c14AB92e22F8a1E", // CL1-USDy/USDpy
      "0x434e3122f5d8d4e6C5B6b7b1Dc71cFf25f3b5A97", // CL1-WETH/cbETH
      "0xdda458696f5EF402C9EA16F17Abb2295c7090D5b", // CL1-WBTC/tBTC
      "0xC762d18800B3f78ae56E9e61aD7BE98a413D59dE", // CL1-USDC/USDT
      "0xb2218A2cFeF38Ca30AE8C88B41f2E2BdD9347E3e", // CL1-wstETH/WETH
    ],
  },

  v2RouterAddresses: ovmChainData.v2Routers,

  arrakisV1: {
    arrakisV1RouterStakingAddress: ovmChainData.arrakis.v1RouterStaking,
  },

  stargate: {
    router: ovmChainData.stargate.router,
    staking: ovmChainData.stargate.staking,
  },

  rewardDistribution: [
    {
      token: ovmChainData.assets.op,
      amountPerSecond: BigNumber.from(210000) // 210K
        .mul(BigNumber.from(10).pow(18))
        .div(180 * 24 * 60 * 60), // 180 days in seconds
      whitelistedPools: [
        torosPools.USDY,
        torosPools.USDMNY,
        torosPools.ETHY,
        "0x178175f4092d6ba11a8372ee968dc34704397a62", // Momentum Ensemble
        "0x6ae8d896b32c71107d1a49af212bc70892a06720", // Dybart Izak
        "0x2fbd33f07d414be3e3e112916504b9bdc5617b69", // Apollo Partners
        "0x56da1e11923b298d70dae1b4749f4cdd56a02532", // Horizons Strategy Optimism
        "0x54eaa41979695a641ac0fd14f71e165bf65d4689", // Remuage Absolute Return
        "0x189a36c62c1ce9d9fd7a543df0a6dbe3a73a2c14", // Pure Boomer Alpha 0/10 fees
      ],
    },
    {
      token: ovmChainData.assets.op,
      amountPerSecond: BigNumber.from(10000) // 10K
        .mul(BigNumber.from(10).pow(18))
        .div(30 * 24 * 60 * 60), // 30 days in seconds
      whitelistedPools: [torosPools.ETHY],
    },
    {
      token: ovmChainData.assets.op,
      amountPerSecond: BigNumber.from(5000) // 5K
        .mul(BigNumber.from(10).pow(18))
        .div(30 * 24 * 60 * 60), // 30 days in seconds
      whitelistedPools: [torosPools.USDY],
    },
  ],
  superSwapper: {
    routeHints: ovmChainData.routeHints,
  },
  perpsV2: {
    addressResolver: ovmChainData.perpsV2.addressResolver,
    whitelistedPools: [
      // Pools which are enabled to trade Perps v2
      "0x83106ddcac5d119a3d0f551e06239e579299b7c4", // DNY2
      "0x90fd55a7ef1af647e93ae96a17bcb3b6a2df0e02", // DNY3
      "0x93701ec795d8f8e16772be05142b2994c045e7dc", // DNY4
      "0xa5d8b370578f9e9eeb9cf7b7fad6cd5ab7d99a64", // DNY5
      torosPools.USDpy,
      torosPools.SOLBULL2X,
      torosPools.SOLBULL3X,
      torosPools.BTCBULL2X,
      torosPools.BTCBULL3X,
      torosPools.BTCBULL4X,
      torosPools.SUIBULL2X,
      torosPools.DOGEBULL2X,
      // "0x9fc311fc8faa6d6b0d3199f25d9976e1e16de998", // Was added for LINK-PERP Contract guard
    ],
    withdrawSlippageSettings: [
      {
        pool: torosPools.SOLBULL2X,
        slippage: 0.0025e18, // 0.25%
      },
      {
        pool: torosPools.SOLBULL3X,
        slippage: 0.003e18, // 0.3%
      },
      {
        pool: torosPools.DOGEBULL2X,
        slippage: 0.002e18, // 0.2%
      },
      {
        pool: torosPools.SUIBULL2X,
        slippage: 0.005e18, // 0.5%
      },
      {
        pool: torosPools.BTCBULL4X,
        slippage: 0.0015e18, // 0.15%
      },
    ],
  },
  synthRedeemer: ovmChainData.synthetix.synthRedeemer,

  zeroExExchangeProxy: ovmChainData.zeroEx.exchangeProxy,

  synthetixV3: {
    core: ovmChainData.synthetix.v3Core,
    dHedgeVaultsWhitelist: [
      {
        // DNY3 https://app.dhedge.org/vault/0x90fd55a7ef1af647e93ae96a17bcb3b6a2df0e02
        poolLogic: "0x90fd55a7ef1af647e93ae96a17bcb3b6a2df0e02",
        collateralAsset: ovmChainData.assets.snxProxy,
        debtAsset: ovmChainData.assets.snxUSD,
        snxLiquidityPoolId: 1,
      },
    ],
    allowedMarkets: [],
    spotMarket: ovmChainData.synthetix.v3SpotMarket,
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
      percent: BigNumber.from(10).pow(17), // 10%
    },
  },

  poolTokenSwapper: {
    manager: "0x7C3C34e9840321E89a5B28232D258f9F38105094",
    assets: [
      {
        asset: ovmChainData.assets.usdc,
        assetEnabled: true,
      },
    ],
    pools: [
      {
        pool: torosPools.USDY,
        poolSwapFee: 5, // 0.05%
        poolEnabled: true,
      },
      {
        pool: torosPools.USDMNY,
        poolSwapFee: 5, // 0.05%
        poolEnabled: true,
      },
      {
        pool: torosPools.ETHY,
        poolSwapFee: 5, // 0.05%
        poolEnabled: true,
      },
      {
        pool: torosPools.USDpy,
        poolSwapFee: 5, // 0.05%
        poolEnabled: true,
      },
    ],
    swapWhitelist: [
      {
        sender: "0x9c6de13d4648a6789017641f6b1a025816e66228", // mHRVST
        status: true,
      },
      {
        sender: "0x665b06ebce43ae67283a37c8c707c44e6611f025", // DNY
        status: true,
      },
    ],
  },

  sonneFinance: {
    comptroller: ovmChainData.sonne.comptroller,
    dHedgeVaultsWhitelist: [
      // Sonne Finance Test https://dhedge.org/vault/0x79fbeba8e8d66622f9f6ba7e505efd39dc68eb27
      "0x79fbeba8e8d66622f9f6ba7e505efd39dc68eb27",
      // Sonne Finance Test 2 https://dhedge.org/vault/0x4c1a92e9e32c72936c9a40f6de28984f9aebf480
      "0x4c1a92e9e32c72936c9a40f6de28984f9aebf480",
      // Sonne Finance Test 3 https://dhedge.org/vault/0x24bf104de70e0cedc14637947e6b780ffc81f7b5
      "0x24bf104de70e0cedc14637947e6b780ffc81f7b5",
      // Sonne Finance Test 4 https://dhedge.org/vault/0xf57aefbd8f6f1e5e90109f8c6a200ad25a4575ec
      "0xf57aefbd8f6f1e5e90109f8c6a200ad25a4575ec",
    ],
  },

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  rewardAssetSetting: [
    {
      rewardToken: ovmChainData.velodromeV2.velo,
      linkedAssetTypes: [
        AssetType["Velodrome CL NFT Position Asset"], // 26
        AssetType["Velodrome V2 LP/Gauge Asset"], // 25
      ],
    },
  ],

  flatMoney: {
    swapper: ovmChainData.flatMoney.swapper,
  },

  easySwapperV2: {
    customCooldownDepositsWhitelist: [
      torosPools.ETHBEAR1X,
      torosPools.ETHBULL2X,
      torosPools.ETHBULL3X,
      torosPools.BTCBEAR1X,
      torosPools.BTCBULL2X,
      torosPools.BTCBULL3X,
      torosPools.BTCBULL4X,
      torosPools.SOLBULL2X,
      torosPools.SOLBULL3X,
      torosPools.ETHY,
      torosPools.USDMNY,
      torosPools.USDpy,
      torosPools.USDY,
      torosPools.SUIBULL2X,
      torosPools.DOGEBULL2X,
    ],
  },

  compoundV3: {
    rewards: ovmChainData.compoundV3.rewards,
  },

  odosV2RouterAddress: ovmChainData.odosEx.v2Router,

  flatMoneyV2: {
    orderAnnouncementModule: "0xd917A0C9B21Bb71DF1209d2c211Ad83004F01554",
    orderExecutionModule: "0x7805CB7fb2C2e70FDdF92949065D9Ee1Fc2F72a8",
    whitelistedVaults: [
      {
        poolLogic: "0x83106dDCaC5D119A3d0f551E06239E579299b7C4", // DNY2
        withdrawalAsset: ovmChainData.assets.wbtc,
      },
      {
        poolLogic: ovmChainData.torosPools.BTCBULL4X,
        withdrawalAsset: ovmChainData.assets.wbtc,
      },
      {
        poolLogic: ovmChainData.torosPools.BTCBULL3X,
        withdrawalAsset: ovmChainData.assets.wbtc,
      },
      {
        poolLogic: ovmChainData.torosPools.BTCBULL2X,
        withdrawalAsset: ovmChainData.assets.wbtc,
      },
      {
        poolLogic: ovmChainData.torosPools.USDpy,
        withdrawalAsset: ovmChainData.assets.usdcNative,
      },
      {
        poolLogic: "0x0f6eae52ae1f94bc759ed72b201a2fdb14891485", // MTy
        withdrawalAsset: ovmChainData.assets.usdcNative,
      },
      {
        poolLogic: ovmChainData.flatMoneyV2Vaults.flatMoneyV2MarketMaker,
        withdrawalAsset: ovmChainData.assets.usdcNative,
      },
      {
        poolLogic: ovmChainData.torosPools.USDMNY,
        withdrawalAsset: ovmChainData.assets.usdcNative,
      },
      {
        poolLogic: "0x35BD1cA1E11E792B6F1f57D3408B5C5cCDdB6B53", // BSX
        withdrawalAsset: ovmChainData.assets.wbtc,
      },
      {
        poolLogic: "0x29f3DfeD90380DB4BAFAFf84862d7fC13eb51252", // mStable mUSD Assets
        withdrawalAsset: ovmChainData.assets.usdcNative,
      },
    ],
  },

  across: {
    spokePool: "0x6f26Bf09B1C792e3228e5467807a900A503c0281",
    approvedDestinations: [
      {
        sourcePool: ovmChainData.flatMoneyV2Vaults.flatMoneyV2MarketMaker,
        sourceToken: ovmChainData.assets.usdcNative,
        destinationChainId: 42161,
        destinationPool: arbitrumChainData.gmxTestVaults.gmxTest2,
        destinationToken: arbitrumChainData.assets.usdcNative,
      },
    ],
  },

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: ovmChainData.assets.usdcNative,
    authorizedKeeperAddresses: [
      "0xfF5C66B0799bb1cD834e2178866225F020A87A7f",
      "0xD411D209d3C602bdB7F99A16775A2e30aEb51009",
      "0xc804F6F95973f3380D8f52fd7aFF475337e2eea2",
      "0x83336A07e2257c537EfcA180E9c89819fa40ECCd",
      "0xfB2f4AE9584c82d3dB9Cd00B5CB664c8cf44470B",
    ],
  },

  allowApproveGuard: {
    allowedSpender: "0xE2F9b946C4Dcc6EbD1e00A8791E1570E4e6D74D9", // PoolTokenSwapper
    tokensToSetGuardTo: [ovmChainData.torosPools.USDpy],
  },
};

export const ovmProdFileNames: IFileNames = {
  versionsFileName: "./publish/ovm/prod/versions.json",
  assetsFileName: "./config/ovm/dHEDGE Assets list.json",
  governanceNamesFileName: "./config/ovm/dHEDGE Governance Names.csv",
  contractGuardsFileName: "./config/ovm/dHEDGE Governance Contract Guards.csv",
  assetGuardsFileName: "./config/ovm/dHEDGE Governance Asset Guards.csv",
  deprecatedContractGuardsFileName: "./config/ovm/dHEDGE Deprecated Contract Guards.csv",
};
