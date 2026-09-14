import { ChainId } from "../chainIds";
import { IAddresses, IFileNames } from "../types";

import { polygonProdData, polygonProdFileNames } from "../polygon/deploymentData";
import { optimismProdData, ovmProdFileNames } from "../ovm/deploymentData";
import { arbitrumProdData, arbitrumProdFileNames } from "../arbitrum/deploymentData";
import { baseProdData, baseProdFileNames } from "../base/deploymentData";
import { ethereumProdData, ethereumProdFileNames } from "../ethereum/deploymentData";
import { plasmaProdData, plasmaProdFileNames } from "../plasma/deploymentData";
import { hyperevmProdData, hyperevmProdFileNames } from "../hyperevm/deploymentData";

export interface IDeploymentData {
  addresses: IAddresses;
  filenames: IFileNames;
}

export const getDeploymentData = (chainId: number): IDeploymentData => {
  switch (chainId) {
    case ChainId.polygon:
      return {
        addresses: polygonProdData,
        filenames: polygonProdFileNames,
      };
    case ChainId.optimism:
      return {
        addresses: optimismProdData,
        filenames: ovmProdFileNames,
      };
    case ChainId.arbitrum:
      return {
        addresses: arbitrumProdData,
        filenames: arbitrumProdFileNames,
      };
    case ChainId.base:
      return {
        addresses: baseProdData,
        filenames: baseProdFileNames,
      };
    case ChainId.ethereum:
      return {
        addresses: ethereumProdData,
        filenames: ethereumProdFileNames,
      };
    case ChainId.plasma:
      return {
        addresses: plasmaProdData,
        filenames: plasmaProdFileNames,
      };
    case ChainId.hyperevm:
      return {
        addresses: hyperevmProdData,
        filenames: hyperevmProdFileNames,
      };
  }
  throw new Error("getDeploymentData: No Case for chainId " + chainId);
};
