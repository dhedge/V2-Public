export type Address = string;

export interface OVMDeployFileNames {
  ovmVersionFile: string;
  chainlinkAssetsFile: string;
  usdPriceAggregatorAssetsFile: string;
}

export interface OVMDeployAddress {
  LEET: Address;
  protocolDao: Address;
  protocolTreasury: Address;
  synthetixProxyAddress: Address;
  synthetixAddressResolverAddress: Address;
  implementationStorage: Address;
}
