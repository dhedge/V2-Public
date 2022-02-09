import { writeCsv } from "../../Helpers";

// TODO: replace require with import
const csv = require("csvtojson");

export const addOrReplaceGuardInFile = async <T extends { [k: string]: string | number }>(
  assetGuardFileName: string,
  guard: T,
  matchKey: keyof T,
) => {
  const csvContractGuards: T[] = await csv().fromFile(assetGuardFileName);
  const withoutExisting = csvContractGuards.map(
    (existingGuard) => existingGuard[matchKey].toString().toLowerCase() != guard[matchKey].toString().toLowerCase(),
  );
  writeCsv([...withoutExisting, guard], assetGuardFileName);
};
