const { getTag } = require("./Helpers");

async function main () {
  let tag = await getTag();
  console.log(tag)
};

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
