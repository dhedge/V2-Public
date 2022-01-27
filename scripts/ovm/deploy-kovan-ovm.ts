import { OVMDeployAddress, OVMDeployFileNames } from "./deploy-types";
import { deployOvm } from "./deploy";

const fileNames: OVMDeployFileNames = {
  ovmVersionFile: "./publish/ovm/kovan/versions.json",
  chainlinkAssetsFile: "./config/kovan-ovm/assets/Chainlink Assets.csv",
  usdPriceAggregatorAssetsFile: "./config/kovan-ovm/assets/USDPriceAggregator Assets.csv",
};

const addresses: OVMDeployAddress = {
  LEET: "0x0000000000000000000000000000000000001337",
  // https://ogg.scopelift.co/wallet/0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08
  protocolDao: "0xef31D75A2f85CfDD9032158A2CEB773C84d79192",
  // https://ogg.scopelift.co/wallet/0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc
  protocolTreasury: "0xef31D75A2f85CfDD9032158A2CEB773C84d79192",

  synthetixProxyAddress: "0x0064A673267696049938AA47595dD0B3C2e705A1",
  synthetixAddressResolverAddress: "0xb08b62e1cdfd37eCCd69A9ACe67322CCF801b3A6",
  implementationStorage: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
};

deployOvm(fileNames, addresses);
