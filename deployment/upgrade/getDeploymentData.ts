import { IAddresses, IFileNames } from "../types";

import {
  polygonProdData,
  polygonProdFileNames,
  polygonStagingData,
  polygonStagingFileNames,
  switchPolygonOzFile,
} from "../polygon/deploymentData";
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

export const getDeploymentData = (chainId: number, deployment: "staging" | "production"): IDeploymentData => {
  const sCase = chainId.toString() + "-" + deployment;
  switch (sCase) {
    case "137-staging":
      switchPolygonOzFile(false);
      return {
        addresses: polygonStagingData,
        filenames: polygonStagingFileNames,
      };
    case "137-production":
      switchPolygonOzFile(true);
      return {
        addresses: polygonProdData,
        filenames: polygonProdFileNames,
      };
    case "10-production":
      return {
        addresses: optimismProdData,
        filenames: ovmProdFileNames,
      };
    case "42161-production":
      return {
        addresses: arbitrumProdData,
        filenames: arbitrumProdFileNames,
      };
    case "8453-production":
      return {
        addresses: baseProdData,
        filenames: baseProdFileNames,
      };
    case "1-production":
      return {
        addresses: ethereumProdData,
        filenames: ethereumProdFileNames,
      };
    case "9745-production":
      return {
        addresses: plasmaProdData,
        filenames: plasmaProdFileNames,
      };
    case "999-production":
      return {
        addresses: hyperevmProdData,
        filenames: hyperevmProdFileNames,
      };
    // Useful for testing with hardhat local fork node.
    // Note that if any upgrade script runs successfully, the version
    // file corresponding to the addresses and filenames used will be updated.
    // Revert the changes in the versions file in that case.
    case "31337-production":
      return {
        addresses: optimismProdData,
        filenames: ovmProdFileNames,
      };
  }
  throw new Error("getDeploymentData: No Case for " + sCase);
};
