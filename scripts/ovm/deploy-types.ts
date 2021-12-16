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
  sUSD: Address;
  synthetixProxyAddress: Address;
  synthetixAddressResolverAddress: Address;
  implementationStorage: Address;
}
