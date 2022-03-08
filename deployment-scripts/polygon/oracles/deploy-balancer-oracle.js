const hre = require("hardhat");
const fs = require("fs");
const { tryVerify } = require("../../Helpers");

const oracleVersionFile = "./publish/matic/oracle-versions.json";
const pools = ["0xbae28251b2a4e621aa7e20538c06dee010bc06de"]; // dUSD
const decimals = 18;

const main = async () => {
  await hre.run("compile:one", { contractName: "BalancerDHedgePoolPriceOracle" });

  const versionPath = `../publish/${network.name}/oracle-versions.json`;
  const versions = require(versionPath);
  let contracts = versions.contracts;

  const DHedgePoolPriceOracle = await ethers.getContractFactory("BalancerDHedgePoolPriceOracle");

  for (const pool of pools) {
    const dHedgePoolPriceOracle = await DHedgePoolPriceOracle.deploy(pool, decimals);
    const tx = dHedgePoolPriceOracle.deployTransaction;
    //wait 5 confirmations before verifying on polyscan
    await tx.wait(5);
    console.log(`Balancer oracle for ${pool} deployed at ${dHedgePoolPriceOracle.address}`);
    await tryVerify(
      hre,
      dHedgePoolPriceOracle.address,
      "contracts/oracles/BalancerDHedgePoolPriceOracle.sol:BalancerDHedgePoolPriceOracle",
      [pool, decimals],
    );
    contracts.Oracles.push({
      assetAddress: pool,
      oracleAddress: dHedgePoolPriceOracle.address,
      oracleName: "BalancerDHedgePoolPriceOracle",
    });
  }

  const tag = Object.keys(versions)[Object.keys(versions).length - 1];
  const network = await ethers.provider.getNetwork();
  versions[tag] = {
    network: network,
    date: new Date().toUTCString(),
    contracts,
  };

  // convert JSON object to string
  const data = JSON.stringify(versions, null, 2);

  fs.writeFileSync(oracleVersionFile, data);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
