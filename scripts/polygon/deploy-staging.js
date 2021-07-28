const { deploy } = require("./deploy.js");

async function main() {
  await deploy("staging");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
