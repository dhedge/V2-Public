const hre = require("hardhat");
const fs = require("fs");

const oracleVersionFile = "./publish/matic/oracle-versions.json";
const weth_dth = "0xa375d23a751124359568f3a22576528bD1C8C3e3";
const dht = "0x8C92e38eCA8210f4fcBf17F0951b198Dd7668292";
const eth_oracle = "0xF9680D99D6C9589e2a93a78A04A279e509205945";

const main = async () => {
  await hre.run("compile:one", { contractName: "MedianTWAPAggregator" });

  const network = await ethers.provider.getNetwork();
  const versionPath = `../publish/${network.name}/oracle-versions.json`;
  const versions = require(versionPath);
  let contracts = versions.contracts;

  const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
  const dhedgeMedianTwapAggregator = await MedianTWAPAggregator.deploy(weth_dth, dht, eth_oracle, 1000);
  await dhedgeMedianTwapAggregator.deployed();
  contracts.push({ pool: weth_dth, dhedgeOracle: dhedgeMedianTwapAggregator.address });

  const tag = Object.keys(versions)[Object.keys(versions).length - 1];
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
