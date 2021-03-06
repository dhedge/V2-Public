import { writeCsv } from "../../Helpers";
import { IDeployedAssetGuard, IDeployedContractGuard } from "../../types";

// TODO: replace require with import
import csv from "csvtojson";

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
