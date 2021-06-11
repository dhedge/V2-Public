const { getTag } = require("./Helpers");

async function main () {
  let tag = await getTag();
  console.log(tag)

  let versions = require("../publish/mumbai/versions.json");
  versions[tag] = {
    test: "test"
  }
  console.log(versions)
};

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
