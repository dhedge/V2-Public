const util = require("util");
const { exec } = require("child_process");
const execProm = util.promisify(exec);

const getTag = async () => {
  try {
    await execProm("git pull --tags");
  } catch {}
  let result = await execProm("git tag | sort -V | tail -1");
  return result.stdout.trim();
};

module.exports = { getTag };
