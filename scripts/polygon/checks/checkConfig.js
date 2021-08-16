task("checkConfig", "Check deployed contracts")
  .addOptionalParam("environment", "staging or prod", "prod", types.string)
  .addOptionalParam("v", "deployment version eg. 'v2.4.0'", "", types.string)
  .addOptionalParam("ownership", "check ownership", false, types.boolean)
  .addOptionalParam("factory", "check factory", false, types.boolean)
  .addOptionalParam("assets", "check assets", false, types.boolean)
  .addOptionalParam("governance", "check governance", false, types.boolean)
  .addOptionalParam("bytecode", "check bytecode", false, types.boolean)
  .setAction(async (taskArgs) => {
    const initialize = require("./initialize");
    const checkOwnership = require("./checkConfigOwnership");
    const checkFactory = require("./checkConfigFactory");
    const checkGovernance = require("./checkConfigGovernance");
    const checkAssets = require("./checkConfigAssets");
    const checkBytecode = require("./checkConfigBytecode");

    const environment = taskArgs.environment;
    const version = taskArgs.v;
    const initializeData = await initialize.init(environment, version);

    // Checks ownable contracts are owned by Protocol DAO
    if (taskArgs.ownership) await checkOwnership.main(initializeData);

    // Checks deployed asset configuration vs CSV & versions file
    if (taskArgs.factory) await checkFactory.main(initializeData);

    // Goverernance contract configuration vs CSV
    if (taskArgs.governance) await checkGovernance.main(initializeData);

    // Checks deployed asset configuration vs CSV & versions file
    if (taskArgs.assets) await checkAssets.main(initializeData);

    // Checks for differences in deployed bytecode vs current repo bytecode
    // Note: Bytecode checks are excluded from 'check:polygon:all' script and can be executed separately.
    if (taskArgs.bytecode) await checkBytecode.main(initializeData);
  });
