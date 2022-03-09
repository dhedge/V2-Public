import { assets, synthetix } from "../../config/chainData/ovm-data";
import { IAddresses, IFileNames } from "../types";

export const ovmProdAddresses: IAddresses = {
  // old - https://ogg.scopelift.co/wallet/0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08
  // https://gnosis-safe.io/app/oeth:0x90b1a66957914EbbE7a8df254c0c1E455972379C/balances - 3/3
  protocolDaoAddress: "0x90b1a66957914EbbE7a8df254c0c1E455972379C",
  // old - https://ogg.scopelift.co/wallet/0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc
  // https://gnosis-safe.io/app/oeth:0xD857e322351Dc56592e3D9181FBF65034EF4aef2 2/5
  protocolTreasuryAddress: "0xD857e322351Dc56592e3D9181FBF65034EF4aef2",
  // Should be fetched from the oz file
  proxyAdminAddress: "0x9FEE88a18479bf7f0D41Da03819538AA7A617730",
  // Gnosis safe multicall/send address
  // https://github.com/gnosis/safe-deployments
  gnosisMultiSendAddress: "0x998739BFdAAdde7C933B942a68053933098f9EDa",
  gnosisApi: "https://safe-transaction.optimism.gnosis.io",

  // Same for everyone
  implementationStorageAddress: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
  synthetixProxyAddress: assets.snxProxy,
  synthetixAddressResolverAddress: synthetix.addressResolver,

  // For sUSDUniV3TWAPAggregator
  sUSDAddress: "0x8c6f28f2f1a3c87f0f938b96d27520d9751ec8d9",
  sUSDDaiUniV3PoolAddress: "0xadb35413ec50e0afe41039eac8b930d313e94fa4",
  daiChainlinkOracleAddress: "0x8dBa75e83DA73cc766A7e5a0ee71F656BAb470d6",
};

export const ovmProdFileNames: IFileNames = {
  versionsFileName: "./publish/ovm/prod/versions.json",
  assetsFileName: "./config/ovm-prod/dHEDGE Assets list.csv",
  governanceNamesFileName: "./config/ovm-prod/dHEDGE Governance Names.csv",
  contractGuardsFileName: "./config/ovm-prod/dHEDGE Governance Contract Guards.csv",
  assetGuardsFileName: "./config/ovm-prod/dHEDGE Governance Asset Guards.csv",
};

export const ovmKovanFileNames: IFileNames = {
  versionsFileName: "./publish/ovm/kovan/versions.json",
  assetsFileName: "./config/ovm-kovan/dHEDGE Assets list.csv",
  governanceNamesFileName: "./config/ovm-kovan/dHEDGE Governance Names.csv",
  contractGuardsFileName: "./config/ovm-kovan/dHEDGE Governance Contract Guards.csv",
  assetGuardsFileName: "./config/ovm-kovan/dHEDGE Governance Asset Guards.csv",
};

export const ovmKovanAddresses: IAddresses = {
  // https://ogg.scopelift.co/wallet/0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08
  protocolDaoAddress: "0xef31D75A2f85CfDD9032158A2CEB773C84d79192",
  // https://ogg.scopelift.co/wallet/0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc
  protocolTreasuryAddress: "0xef31D75A2f85CfDD9032158A2CEB773C84d79192",
  proxyAdminAddress: "0xA185BfbB4c554728505656C2d3788f3fA3Db5B92",
  implementationStorageAddress: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
  gnosisMultiSendAddress: "0x998739BFdAAdde7C933B942a68053933098f9EDa",
  gnosisApi: "https://safe-transaction.optimism.gnosis.io",

  synthetixProxyAddress: "0x0064A673267696049938AA47595dD0B3C2e705A1",
  synthetixAddressResolverAddress: "0xb08b62e1cdfd37eCCd69A9ACe67322CCF801b3A6",
};
