import { task, types } from "hardhat/config";
import { init } from "./initialize";
import { checkOwnership } from "./checkConfigOwnership";
import { checkFactory } from "./checkConfigFactory";
import { checkGovernance } from "./checkConfigGovernance";
import { checkAssets } from "./checkConfigAssets";
import { checkBytecode } from "./checkConfigBytecode";

task("checkConfig", "Check deployed contracts")
  .addOptionalParam("environment", "staging or prod", undefined, types.string)
  .addOptionalParam("specific", "propose transactions", false, types.boolean)
  .addOptionalParam("v", "deployment version eg. 'v2.4.0'", "", types.string)
  .addOptionalParam("ownership", "check ownership", false, types.boolean)
  .addOptionalParam("factory", "check factory", false, types.boolean)
  .addOptionalParam("assets", "check assets", false, types.boolean)
  .addOptionalParam("governance", "check governance", false, types.boolean)
  .addOptionalParam("bytecode", "check bytecode", false, types.boolean)
  .setAction(async (taskArgs, hre) => {
    const environment = taskArgs.environment || hre.network.name;
    const version = taskArgs.v;
    const notSpecific = !taskArgs.specific;
    const initializeData = await init(environment, version, hre);

    // Checks ownable contracts are owned by Protocol DAO
    if (notSpecific || taskArgs.ownership) await checkOwnership(initializeData);

    // Checks deployed asset configuration vs CSV & versions file
    if (notSpecific || taskArgs.factory) await checkFactory(initializeData);

    // Goverernance contract configuration vs CSV
    if (notSpecific || taskArgs.governance) await checkGovernance(initializeData);

    // Checks deployed asset configuration vs CSV & versions file
    if (notSpecific || taskArgs.assets) await checkAssets(initializeData, hre);

    // Checks for differences in deployed bytecode vs current repo bytecode
    // Note: Bytecode checks are excluded from 'check:polygon:all' script and can be executed separately.
    if (notSpecific || taskArgs.bytecode) await checkBytecode(initializeData, hre);
  });
