import { ovmChainData } from "../../config/chainData/ovm-data";
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
  gnosisApi: "https://safe-transaction.optimism.gnosis.io",

  // Same for everyone
  implementationStorageAddress: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
  synthetixProxyAddress: ovmChainData.assets.snxProxy,
  synthetixAddressResolverAddress: ovmChainData.synthetix.addressResolver,

  torosEasySwapperAllowedPools: Object.values(torosPools),

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

  oneInchV4RouterAddress: "0x1111111254760F7ab3F16433eea9304126DCd199",
  oneInchV5RouterAddress: "0x1111111254eeb25477b68fb85ed929f73a960582",

  aaveV3: {
    aaveLendingPoolAddress: ovmChainData.aaveV3.lendingPool,
    aaveProtocolDataProviderAddress: ovmChainData.aaveV3.protocolDataProvider,
    aaveIncentivesControllerAddress: ovmChainData.aaveV3.incentivesController,
  },
  stakingV2Pools: [],

  lyra: {
    optionMarketWrapper: "0xCCE7819d65f348c64B7Beb205BA367b3fE33763B",
    optionMarketViewer: "0xEAf788AD8abd9C98bA05F6802a62B8DbC673D76B",
    lyraRegistry: "0xF5A0442D4753cA1Ea36427ec071aa5E786dA5916",
  },

  velodrome: {
    router: ovmChainData.velodrome.router,
    voter: ovmChainData.velodrome.voter,
  },

  v2RouterAddresses: [ovmChainData.velodrome.router],

  arrakisV1: {
    arrakisV1RouterStakingAddress: ovmChainData.arrakis.v1RouterStaking,
  },

  rewardDistribution: {
    token: ovmChainData.assets.usdc, // USDC for some testing
    amountPerSecond: 10, // it's 0.00001 USDC per second -> 0.864 USDC per day
  },
};

export const ovmProdFileNames: IFileNames = {
  versionsFileName: "./publish/ovm/prod/versions.json",
  assetsFileName: "./config/ovm-prod/dHEDGE Assets list.json",
  governanceNamesFileName: "./config/ovm-prod/dHEDGE Governance Names.csv",
  contractGuardsFileName: "./config/ovm-prod/dHEDGE Governance Contract Guards.csv",
  assetGuardsFileName: "./config/ovm-prod/dHEDGE Governance Asset Guards.csv",
};

export const ovmKovanFileNames: IFileNames = {
  versionsFileName: "./publish/ovm/kovan/versions.json",
  assetsFileName: "./config/ovm-kovan/dHEDGE Assets list.json",
  governanceNamesFileName: "./config/ovm-kovan/dHEDGE Governance Names.csv",
  contractGuardsFileName: "./config/ovm-kovan/dHEDGE Governance Contract Guards.csv",
  assetGuardsFileName: "./config/ovm-kovan/dHEDGE Governance Asset Guards.csv",
};

export const ovmGoerliFileNames: IFileNames = {
  versionsFileName: "./publish/ovm/goerli/versions.json",
  assetsFileName: "./config/ovm-goerli/dHEDGE Assets list.json",
  governanceNamesFileName: "./config/ovm-goerli/dHEDGE Governance Names.csv",
  contractGuardsFileName: "./config/ovm-goerli/dHEDGE Governance Contract Guards.csv",
  assetGuardsFileName: "./config/ovm-goerli/dHEDGE Governance Asset Guards.csv",
};

export const ovmKovanAddresses: IAddresses = {
  // https://ogg.scopelift.co/wallet/0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08
  protocolDaoAddress: "0xf5E53501a0c0a48079FdBcca95dA75305c67d5F5",
  // https://ogg.scopelift.co/wallet/0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc
  protocolTreasuryAddress: "0xf5E53501a0c0a48079FdBcca95dA75305c67d5F5",
  proxyAdminAddress: "0xA185BfbB4c554728505656C2d3788f3fA3Db5B92",
  implementationStorageAddress: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",

  synthetixProxyAddress: "0xA850829F8eE75CC6849e35256A43C20D6A7F5F0B", // mock address provided by lyra
  synthetixAddressResolverAddress: "0x960492a0a82736F7B1c819cEB06a62be8838E005", // mock address provided by lyra

  // No leverage pools on OVM
  torosEasySwapperAllowedPools: [],

  // These need to be set
  uniV3: {
    uniswapV3FactoryAddress: "0x",
    uniswapV3RouterAddress: "0x",
    uniSwapV3NonfungiblePositionManagerAddress: "0x",
  },

  lyra: {
    optionMarketWrapper: "0xd24955B7AB75FaD5542769105d862FC76A76AF7f",
    optionMarketViewer: "0xe5f9B585F3c2fc3E497283CeC078C5FDC10d4B13",
    lyraRegistry: "0x91a1AB0DDa247CE6D8666c5A49c183f8978a9797",
  },

  // These need to be set
  assets: {
    nativeAssetWrapper: "0x",
    usdc: "0x",
    weth: "0x",
    dai: "0x",
    dht: "0x",
  },
  stakingV2Pools: [],
};

export const ovmGoerliAddresses: IAddresses = {
  protocolDaoAddress: "0xf5E53501a0c0a48079FdBcca95dA75305c67d5F5",
  protocolTreasuryAddress: "0xf5E53501a0c0a48079FdBcca95dA75305c67d5F5",
  proxyAdminAddress: "",
  implementationStorageAddress: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",

  synthetixProxyAddress: "0x355FCaB434BB9A3976e4cDb6E74c14C093aBAd4D", // mock address provided by lyra
  synthetixAddressResolverAddress: "0x2bcD0dd6F13F959265FA5F3C773C343B13A5AbC4", // mock address provided by lyra

  // No leverage pools on OVM
  torosEasySwapperAllowedPools: [],

  // These need to be set
  uniV3: {
    uniswapV3FactoryAddress: "0x",
    uniswapV3RouterAddress: "0x",
    uniSwapV3NonfungiblePositionManagerAddress: "0x",
  },

  lyra: {
    optionMarketWrapper: "0xDbE4b2b5989CcE85EFE28125aB33E1411b639f22",
    optionMarketViewer: "0xd21Ea15DA6732BcFaC3f9390F0A37A1f4ce37acc",
    lyraRegistry: "0xabc92540e5D728C7E3E0f53dB2516cf4b8D5B854",
  },

  // These need to be set
  assets: {
    nativeAssetWrapper: "0x",
    usdc: "0x",
    weth: "0x",
    dai: "0x",
    dht: "0x",
  },
  stakingV2Pools: [],
};
