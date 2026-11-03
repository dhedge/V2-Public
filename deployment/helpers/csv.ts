import fs from "fs";
import csv from "csvtojson";
import { Input, stringify } from "csv-stringify/sync";
import { IDeployedAssetGuard, IDeployedContractGuard } from "../types";

export const writeCsv = (data: Input, fileName: string) => {
  const output = stringify(data, { header: true });
  fs.writeFileSync(fileName, output);
};

export const addOrReplaceGuardInFile = async <T extends IDeployedContractGuard | IDeployedAssetGuard>(
  assetGuardFileName: string,
  guard: T,
  matchKey: keyof T,
) => {
  const csvContractGuards: T[] = await csv().fromFile(assetGuardFileName);
  const withoutExisting = csvContractGuards.filter(
    (existingGuard) => String(existingGuard[matchKey]).toLowerCase() != String(guard[matchKey]).toLowerCase(),
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
