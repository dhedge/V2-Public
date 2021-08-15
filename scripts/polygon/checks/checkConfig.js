task("checkConfig", "Check deployed contracts")
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

    const initializeData = await initialize.init("v2.4.0"); // TODO: remove "v2.4.0" once latest release version is deployed

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
