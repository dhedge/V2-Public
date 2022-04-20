import { IAddresses, IFileNames } from "../types";

import {
  polygonProdAddresses,
  polygonProdFileNames,
  polygonStagingAddresses,
  polygonStagingFileNames,
  switchPolygonOzFile,
} from "../polygon/deployment-data";
import { ovmKovanAddresses, ovmKovanFileNames, ovmProdAddresses, ovmProdFileNames } from "../ovm/deploy-data";

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
        addresses: polygonStagingAddresses,
        filenames: polygonStagingFileNames,
      };
    case "137-production":
      switchPolygonOzFile(true);
      return {
        addresses: polygonProdAddresses,
        filenames: polygonProdFileNames,
      };
    // ovm kovan
    case "69-staging":
      return {
        addresses: ovmKovanAddresses,
        filenames: ovmKovanFileNames,
      };
    // ovm prod
    case "10-production":
      return {
        addresses: ovmProdAddresses,
        filenames: ovmProdFileNames,
      };
  }
  throw new Error("getDeploymentData: No Case for " + sCase);
};
