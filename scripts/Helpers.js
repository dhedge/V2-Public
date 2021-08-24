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

const hasDuplicates = async (array, key) => {
  const valueArr = array.map(function (item) {
    return item[key];
  });

  const isDuplicate = valueArr.some(function (item, idx) {
    if (!item) return false;
    return valueArr.indexOf(item) != idx;
  });

  return isDuplicate;
};

module.exports = { getTag, hasDuplicates };
