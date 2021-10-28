const hre = require("hardhat");

const pool = "0xe3528a438b94e64669def9b875c381c46ef713bf";

const main = async () => {
  const upgrades = hre.upgrades;

  const DHedgePoolPriceOracle = await ethers.getContractFactory("DHedgePoolPriceOracle");
  const dHedgePoolPriceOracle = await upgrades.deployProxy(DHedgePoolPriceOracle, [pool]);
  await dHedgePoolPriceOracle.deployed();
  console.log("Oracle deployed at ", dHedgePoolPriceOracle.address);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
