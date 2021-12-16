import { assets, synthetix } from "../../test/integration/ovm/ovm-data";
import { deployOvm } from "./deploy";
import { OVMDeployAddress, OVMDeployFileNames } from "./deploy-types";

const fileNames: OVMDeployFileNames = {
  ovmVersionFile: "./publish/ovm/prod/versions.json",
  chainlinkAssetsFile: "./config/prod-ovm/assets/Chainlink Assets.csv",
  usdPriceAggregatorAssetsFile: "./config/prod-ovm/assets/USDPriceAggregator Assets.csv",
};

const addresses: OVMDeployAddress = {
  LEET: "0x0000000000000000000000000000000000001337",
  // https://ogg.scopelift.co/wallet/0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08
  protocolDao: "0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08",
  // https://ogg.scopelift.co/wallet/0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc
  protocolTreasury: "0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc",

  sUSD: assets.susd,
  synthetixProxyAddress: assets.snxProxy,
  synthetixAddressResolverAddress: synthetix.addressResolver,
  implementationStorage: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
};

deployOvm(fileNames, addresses);
