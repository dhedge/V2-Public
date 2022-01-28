import { assets, synthetix } from "../../test/integration/ovm/ovm-data";
import { IAddresses, IFileNames } from "../v2/types";
import { addresses } from "./deploy-ovm";

export const ovmAddresses: IAddresses = {
  // Dhedge Internal
  protocolDaoAddress: addresses.protocolDao,
  // Should be fetched from the oz file
  proxyAdminAddress: "0x9FEE88a18479bf7f0D41Da03819538AA7A617730",
  // Same for everyone
  implementationStorageAddress: "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
  synthetixProxyAddress: assets.snxProxy,
  synthetixAddressResolverAddress: synthetix.addressResolver,
};

export const ovmProdFileNames: IFileNames = {
  versionsFileName: "/publish/ovm/prod/versions.json",
  assetsFileName: "./config/ovm-prod/dHEDGE Assets list.csv",
  governanceNamesFileName: "./config/ovm-prod/dHEDGE Governance Names.csv",
  contractGuardsFileName: "./config/ovm-prod/dHEDGE Governance Contract Guards.csv",
  assetGuardsFileName: "./config/ovm-prod/dHEDGE Governance Asset Guards.csv",
};
