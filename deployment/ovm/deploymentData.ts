import { BigNumber } from "ethers";
import { IAddresses, IFileNames } from "../types";
import { AssetType } from "../upgrade/jobs/assetsJob";

const protocolDao = "0x90b1a66957914EbbE7a8df254c0c1E455972379C";
const proxyAdmin = "0x9FEE88a18479bf7f0D41Da03819538AA7A617730";

export const assets = {
  susd: "0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9",
  usdc: "0x7f5c764cbc14f9669b88837ca1490cca17c31607",
  weth: "0x4200000000000000000000000000000000000006",
  wbtc: "0x68f180fcCe6836688e9084f035309E29Bf0A2095",
  dht: "0xAF9fE3B5cCDAe78188B1F8b9a49Da7ae9510F151",
  op: "0x4200000000000000000000000000000000000042",
  velo: "0x3c8B650257cFb5f272f799F5e2b4e65093a11a05",
  lusd: "0xc40f949f8a4e094d1b49a23ea9241d289b7b2819",
  wstETH: "0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb",
  link: "0x350a791bfc2c21f9ed5d10980dad2e2638ffa7f6",
  usdcNative: "0x0b2c639c533813f4aa9d7837caf62653d097ff85",
};

const torosPools = {
  USDY: "0x1ec50880101022c11530a069690f5446d1464592",
  USDMNY: "0x49bf093277bf4dde49c48c6aa55a3bda3eedef68",
  ETHY: "0xb2cfb909e8657c0ec44d3dd898c1053b87804755",
  USDpy: "0xb9243c495117343981ec9f8aa2abffee54396fc0",
  ETHBULL2X: "0x9573c7b691cdcebbfa9d655181f291799dfb7cf5",
  ETHBEAR1X: "0xcacb5a722a36cff6baeb359e21c098a4acbffdfa",
  BTCBULL2X: "0x32ad28356ef70adc3ec051d8aacdeeaa10135296",
  BTCBEAR1X: "0x83d1fa384ec44c2769a3562ede372484f26e141b",
  ETHBULL3X: "0x32b1d1bfd4b3b0cb9ff2dcd9dac757aa64d4cb69",
  BTCBULL3X: "0xb03818de4992388260b62259361778cf98485dfe",
  SOLBULL2X: "0x7d3c9c6566375d7ad6e89169ca5c01b5edc15364",
  SOLBULL3X: "0xcc7d6ed524760539311ed0cdb41d0852b4eb77eb",
  BTCBULL4X: "0x11b55966527ff030ca9c7b1c548b4be5e7eaee6d",
  SUIBULL2X: "0x1bAe4efC60269fe66ECEC7252825d6a0250A02EE",
  DOGEBULL2X: "0x49BDB78f48db6e0CeD4D4475b6D2047539dF1412",
};

export const flatMoneyV2Vaults = {
  flatMoneyV2MarketMaker: "0x1c57f6769fb3e51e65ad24c8c12dbd956ea716b6", // Flat Money V2 Market Maker https://dhedge.org/vault/0x1c57f6769fb3e51e65ad24c8c12dbd956ea716b6
};

const velodromeV2Voter = "0x41c914ee0c7e1a5edcd0295623e6dc557b5abf3c";

// Swap router route hints for lower slippage swaps
const routeHints = [
  { asset: assets.velo, intermediary: assets.usdc },
  { asset: assets.susd, intermediary: assets.usdcNative },
  { asset: assets.dht, intermediary: assets.op },
  { asset: assets.lusd, intermediary: assets.usdc },
  { asset: assets.wstETH, intermediary: assets.weth },
  { asset: assets.link, intermediary: assets.weth },
];

export const optimismProdData: IAddresses = {
  // old - https://ogg.scopelift.co/wallet/0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08
  protocolDaoAddress: protocolDao,
  // old - https://ogg.scopelift.co/wallet/0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc
  protocolTreasuryAddress: "0xD857e322351Dc56592e3D9181FBF65034EF4aef2",
  // Should be fetched from the oz file
  proxyAdminAddress: proxyAdmin,

  uniV2: {
    factory: "0x0c3c1c532F1e39EdF36BE9Fe0bE1410313E074Bf",
  },

  uniV3: {
    uniswapV3RouterAddress: "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
    uniSwapV3NonfungiblePositionManagerAddress: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
    uniswapV3FactoryAddress: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
  },

  assets: {
    nativeAssetWrapper: assets.weth,
    usdc: assets.usdc,
    dht: assets.dht,
  },

  oneInchV6RouterAddress: "0x111111125421ca6dc452d289314280a0f8842a65",

  aaveV3: {
    aaveLendingPoolAddress: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
    aaveIncentivesControllerAddress: "0x929EC64c34a17401F460460D4B9390518E5B473e",
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
        pool: torosPools.USDpy,
        cap: BigNumber.from(100_000).mul(BigNumber.from(10).pow(18)),
      },
      // Ethereum Savings Account https://dhedge.org/vault/0xa2ffe6ed599e8f7aac8047f5ee0de3d83de1b320 $25,000
      {
        pool: "0xa2ffe6ed599e8f7aac8047f5ee0de3d83de1b320",
        cap: BigNumber.from(25_000).mul(BigNumber.from(10).pow(18)),
      },
    ],
  },

  velodrome: {
    router: "0x9c12939390052919aF3155f41Bf4160Fd3666A6f",
    voter: "0x09236cff45047dbee6b921e00704bed6d6b8cf7e",
    routerV2: "0xa062ae8a9c5e11aaa026fc2670b0d65ccc8b2858",
    voterV2: velodromeV2Voter,
    factoryV2: "0xf1046053aa5682b4f9a81b5481394da16be5ff5a",
  },

  velodromeCL: {
    nonfungiblePositionManager: "0x416b433906b1B72FA758e166e239c43d68dC6F29",
    nonfungiblePositionManagerOld: "0xbB5DFE1380333CEE4c2EeBd7202c80dE2256AdF4",
    voter: velodromeV2Voter, // same as the v2 voter
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

  v2RouterAddresses: [],

  rewardDistribution: [
    {
      token: assets.op,
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
      token: assets.op,
      amountPerSecond: BigNumber.from(10000) // 10K
        .mul(BigNumber.from(10).pow(18))
        .div(30 * 24 * 60 * 60), // 30 days in seconds
      whitelistedPools: [torosPools.ETHY],
    },
    {
      token: assets.op,
      amountPerSecond: BigNumber.from(5000) // 5K
        .mul(BigNumber.from(10).pow(18))
        .div(30 * 24 * 60 * 60), // 30 days in seconds
      whitelistedPools: [torosPools.USDY],
    },
  ],
  superSwapper: {
    routeHints: routeHints,
  },

  slippageAccumulator: {
    decayTime: 86400, // 24 hours
    maxCumulativeSlippage: 10e4, // 10%
  },

  rewardAssetSetting: [
    {
      rewardToken: "0x9560e827af36c94d2ac33a39bce1fe78631088db", // VELO (Velodrome V2)
      linkedAssetTypes: [
        AssetType["Velodrome CL NFT Position Asset"], // 26
        AssetType["Velodrome V2 LP/Gauge Asset"], // 25
      ],
      linkedAssets: [],
    },
  ],

  flatMoney: {
    swapper: "0x4F754e0F0924afD74980886b0B479Fa1D7C58D0D",
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
    rewards: "0x443EA0340cb75a160F31A440722dec7b5bc3C2E9",
  },

  flatMoneyV2: {
    orderAnnouncementModule: "0xd917A0C9B21Bb71DF1209d2c211Ad83004F01554",
    orderExecutionModule: "0x7805CB7fb2C2e70FDdF92949065D9Ee1Fc2F72a8",
    whitelistedVaults: [
      {
        poolLogic: "0x83106dDCaC5D119A3d0f551E06239E579299b7C4", // DNY2
        withdrawalAsset: assets.wbtc,
      },
      {
        poolLogic: torosPools.BTCBULL4X,
        withdrawalAsset: assets.wbtc,
      },
      {
        poolLogic: torosPools.BTCBULL3X,
        withdrawalAsset: assets.wbtc,
      },
      {
        poolLogic: torosPools.BTCBULL2X,
        withdrawalAsset: assets.wbtc,
      },
      {
        poolLogic: torosPools.USDpy,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: "0x0f6eae52ae1f94bc759ed72b201a2fdb14891485", // MTy
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: flatMoneyV2Vaults.flatMoneyV2MarketMaker,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: torosPools.USDMNY,
        withdrawalAsset: assets.usdcNative,
      },
      {
        poolLogic: "0x35BD1cA1E11E792B6F1f57D3408B5C5cCDdB6B53", // BSX
        withdrawalAsset: assets.wbtc,
      },
      {
        poolLogic: "0x29f3DfeD90380DB4BAFAFf84862d7fC13eb51252", // mStable mUSD Assets
        withdrawalAsset: assets.usdcNative,
      },
    ],
  },

  across: {
    spokePool: "0x6f26Bf09B1C792e3228e5467807a900A503c0281",
  },

  poolLimitOrderManager: {
    defaultSlippageTolerance: 200, // 2%
    settlementToken: assets.usdcNative,
    authorizedKeeperAddresses: [
      "0x99c9F65a486C0567495ec58722916c73292D585f",
      "0xC0F49445a9B8A60778EF8bCa99059Ceabb066e19",
      "0x962976AA38665fc59B2F981C2457a6f95fFB2aD5",
      "0x5048d4630c51d02A281Cb77E63a1A3af4Fd8dc33",
    ],
  },

  kyberSwap: {
    routerV2: "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
  },

  easyLimitBuyManager: {
    permit2: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
    authorizedKeeperAddresses: [
      "0xFBFE87a8665cE77e4F1f47d0256b7e68Be966498",
      "0xBA2A62aFAfC662afbE5C726910C101225aDeF591",
      "0x4C6ced5164042150A63Cd7610af3Efc7fF2fe4B6",
      "0x3D8D80d65EF8df009AF576dF44d4d06bf39A94DF",
    ],
  },
};

export const ovmProdFileNames: IFileNames = {
  versionsFileName: "./publish/ovm/prod/versions.json",
  assetsFileName: "./config/ovm/dHEDGE Assets list.json",
  contractGuardsFileName: "./config/ovm/dHEDGE Governance Contract Guards.csv",
  assetGuardsFileName: "./config/ovm/dHEDGE Governance Asset Guards.csv",
  deprecatedContractGuardsFileName: "./config/ovm/dHEDGE Deprecated Contract Guards.csv",
};
