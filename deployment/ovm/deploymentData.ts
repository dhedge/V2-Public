import { BigNumber } from "ethers";
import { ovmChainData } from "../../config/chainData/ovmData";
import { IAddresses, IFileNames } from "../types";

const { torosPools } = ovmChainData;

export const ovmProdAddresses: IAddresses = {
  // old - https://ogg.scopelift.co/wallet/0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08
  // https://gnosis-safe.io/app/oeth:0x90b1a66957914EbbE7a8df254c0c1E455972379C/balances - 3/3
  protocolDaoAddress: ovmChainData.protocolDao,
  // old - https://ogg.scopelift.co/wallet/0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc
  // https://gnosis-safe.io/app/oeth:0xD857e322351Dc56592e3D9181FBF65034EF4aef2 2/5
  protocolTreasuryAddress: "0xD857e322351Dc56592e3D9181FBF65034EF4aef2",
  // Should be fetched from the oz file
  proxyAdminAddress: ovmChainData.proxyAdmin,
  // Gnosis safe multicall/send address
  // https://github.com/gnosis/safe-deployments
  gnosisMultiSendAddress: "0x998739BFdAAdde7C933B942a68053933098f9EDa",
  gnosisApi: "https://safe-transaction-optimism.safe.global",

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

  aaveV3: {
    aaveLendingPoolAddress: ovmChainData.aaveV3.lendingPool,
    aaveProtocolDataProviderAddress: ovmChainData.aaveV3.protocolDataProvider,
    aaveIncentivesControllerAddress: ovmChainData.aaveV3.incentivesController,
  },

  stakingV2: {
    dhtCap: BigNumber.from(7_000_000).mul(BigNumber.from(10).pow(18)),
    emissionsRate: 1000,
    whitelistedPools: [
      // Optimism	Stablecoin Yield	https://app.dhedge.org/pool/0x1ec50880101022c11530a069690f5446d1464592	$500,000
      {
        pool: ovmChainData.torosPools.USDY,
        cap: BigNumber.from(500_000).mul(BigNumber.from(10).pow(18)),
      },
      // Optimism	Ethereum Yield	https://app.dhedge.org/pool/0xb2cfb909e8657c0ec44d3dd898c1053b87804755	$200,000
      {
        pool: ovmChainData.torosPools.ETHY,
        cap: BigNumber.from(200_000).mul(BigNumber.from(10).pow(18)),
      },
      // Optimism	USD Market Neutral Yield	https://app.dhedge.org/pool/0x49bf093277bf4dde49c48c6aa55a3bda3eedef68	$100,000
      {
        pool: ovmChainData.torosPools.USDMNY,
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

  v2RouterAddresses: ovmChainData.v2Routers,

  arrakisV1: {
    arrakisV1RouterStakingAddress: ovmChainData.arrakis.v1RouterStaking,
  },

  stargate: {
    router: ovmChainData.stargate.router,
    staking: ovmChainData.stargate.staking,
  },

  rewardDistribution: {
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
      "0xb9243c495117343981ec9f8aa2abffee54396fc0", // USDpy
      // "0x9fc311fc8faa6d6b0d3199f25d9976e1e16de998", // Was added for LINK-PERP Contract guard
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
    ],
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
