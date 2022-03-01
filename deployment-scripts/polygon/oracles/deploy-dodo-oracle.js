const hre = require("hardhat");
const fs = require("fs");
const { getTag, tryVerify } = require("../../Helpers");

const oracleVersionFile = "./publish/matic/oracle-versions.json";
const pools = [
  "0x3e5f7e9e7dc3bc3086ccebd5eb59a0a4a29d881b",
  "0xc8fa09426ce1aeac1bc28751f1f6c8d74fa53f3c",
  "0xcc940b5c6136994bed41bff5d88b170929921e9e",
  "0xf4b3a195587d2735b656b7ffe9060f478faf1b32",
];
const decimals = 6;

const main = async () => {
  await hre.run("compile:one", { contractName: "DodoDHedgePoolPriceOracle" });

  const versionPath = `../publish/${network.name}/oracle-versions.json`;
  const versions = require(versionPath);
  let contracts = versions.contracts;

  const DHedgePoolPriceOracle = await ethers.getContractFactory("DodoDHedgePoolPriceOracle");

  for (const pool of pools) {
    const dHedgePoolPriceOracle = await DHedgePoolPriceOracle.deploy(pool, decimals);
    const tx = dHedgePoolPriceOracle.deployTransaction;
    //wait 5 confirmations before verifying on polyscan
    await tx.wait(5);
    console.log(`Dodo oracle for ${pool} deployed at ${dHedgePoolPriceOracle.address}`);
    await tryVerify(
      hre,
      dHedgePoolPriceOracle.address,
      "contracts/oracles/DodoDHedgePoolPriceOracle.sol:DodoDHedgePoolPriceOracle",
      [pool, decimals],
    );
    contracts.Oracles.push({
      assetAddress: pool,
      oracleAddress: dHedgePoolPriceOracle.address,
      oracleName: "DodoDHedgePoolPriceOracle",
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
