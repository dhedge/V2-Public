import { IAddresses, IFileNames } from "./types";
import fs from "fs";
import { polygonAddresses, polygonProdFileNames, polygonStagingFileNames } from "../polygon/deployment-data";
import { ovmAddresses, ovmProdFileNames } from "../ovm/deploy-data";

export interface DeploymentData {
  addresses: IAddresses;
  filenames: IFileNames;
}

const switchPolygonOzFile = (isProduction: boolean) => {
  const ozPath = "./.openzeppelin/";
  const ozEnvFile = ozPath + (isProduction ? "polygon-production.json" : "polygon-staging.json");
  const ozExpectedFile = ozPath + "unknown-137.json";
  fs.renameSync(ozEnvFile, ozExpectedFile);

  process.on("SIGINT", () => {
    console.log("Process Interrupted, Reverting rename");
    fs.renameSync(ozExpectedFile, ozEnvFile);
    console.log("Exiting...");
    // eventually exit
    process.exit(); // Add code if necessary
  });

  process.on("exit", () => {
    console.log("Process Interrupted, Reverting rename");
    fs.renameSync(ozExpectedFile, ozEnvFile);
    console.log("Exiting...");
    // eventually exit
    process.exit(); // Add code if necessary
  });
};

export const getDeploymentData = (chainId: number, deployment: "staging" | "production"): DeploymentData => {
  const sCase = chainId.toString() + "-" + deployment;
  switch (sCase) {
    case "137-staging":
      switchPolygonOzFile(false);
      return {
        addresses: polygonAddresses,
        filenames: polygonStagingFileNames,
      };
    case "137-production":
      switchPolygonOzFile(true);
      return {
        addresses: polygonAddresses,
        filenames: polygonProdFileNames,
      };
    case "10-staging":
      throw new Error("No staging environment for chainId:" + chainId);
    case "10-production":
      return {
        addresses: ovmAddresses,
        filenames: ovmProdFileNames,
      };
  }
  throw new Error("getDeploymentData: No Case for " + sCase);
};
