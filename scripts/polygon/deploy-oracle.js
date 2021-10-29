const hre = require("hardhat");

const protocolDao = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
const pool = "0xe3528a438b94e64669def9b875c381c46ef713bf";
const decimals = 6;

const main = async () => {
  const upgrades = hre.upgrades;

  const DHedgePoolPriceOracle = await ethers.getContractFactory("DHedgePoolPriceOracle");
  const dHedgePoolPriceOracleProxy = await upgrades.deployProxy(DHedgePoolPriceOracle, [pool, decimals]);
  await dHedgePoolPriceOracleProxy.deployed();
  console.log("Oracle deployed at ", dHedgePoolPriceOracleProxy.address);
  await dHedgePoolPriceOracleProxy.transferOwnership(protocolDao);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
