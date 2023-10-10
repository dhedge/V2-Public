import csv from "csvtojson";

import { writeCsv } from "../../deploymentHelpers";
import { IDeployedAssetGuard, IDeployedContractGuard } from "../../types";

export const addOrReplaceGuardInFile = async <T extends IDeployedContractGuard | IDeployedAssetGuard>(
  assetGuardFileName: string,
  guard: T,
  matchKey: keyof T,
) => {
  const csvContractGuards: T[] = await csv().fromFile(assetGuardFileName);
  const withoutExisting = csvContractGuards.filter(
    (existingGuard) => existingGuard[matchKey].toString().toLowerCase() != guard[matchKey].toString().toLowerCase(),
  );

  writeCsv([...withoutExisting, guard], assetGuardFileName);
};

export const removeContractGuardFromFile = async (contractGuardFileName: string, deprecatedGuardedAddress: string) => {
  const contractGuards: IDeployedContractGuard[] = await csv().fromFile(contractGuardFileName);
  writeCsv(
    contractGuards.filter(
      ({ contractAddress }) => contractAddress.toLowerCase() !== deprecatedGuardedAddress.toLowerCase(),
    ),
    contractGuardFileName,
  );
};
