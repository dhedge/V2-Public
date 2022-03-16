import hre from "hardhat";
import fs from "fs";

const oracleVersionFile = "./publish/matic/oracle-versions.json";
const weth_dth = "0xa375d23a751124359568f3a22576528bD1C8C3e3";
const dht = "0x8C92e38eCA8210f4fcBf17F0951b198Dd7668292";
const eth_oracle = "0xF9680D99D6C9589e2a93a78A04A279e509205945";

import { tryVerify } from "../../Helpers";

const main = async () => {
  await hre.run("compile:one", { contractName: "MedianTWAPAggregator" });

  const network = await ethers.provider.getNetwork();
  const versionPath = `../../../publish/${network.name}/oracle-versions.json`;
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const versions = require(versionPath);
  const tag = Object.keys(versions)[Object.keys(versions).length - 1];
  versions[tag].network = network;
  versions[tag].date = new Date().toUTCString();

  const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
  console.log("Deploying Median TWAP oracle..");
  const dhedgeMedianTwapAggregator = await MedianTWAPAggregator.deploy(weth_dth, dht, eth_oracle, 300, 25); // 5 minute update interval, 25% volatility trip
  await dhedgeMedianTwapAggregator.deployed();

  // wait 5 confirmations before verifying
  const tx = dhedgeMedianTwapAggregator.deployTransaction;
  await tx.wait(5);
  console.log(`Median TWAP oracle for ${weth_dth} deployed at ${dhedgeMedianTwapAggregator.address}`);
  await tryVerify(
    hre,
    dhedgeMedianTwapAggregator.address,
    "contracts/priceAggregators/MedianTWAPAggregator.sol:MedianTWAPAggregator",
    [weth_dth, dht, eth_oracle, 300, 25],
  );

  versions[tag].contracts.Oracles.push({
    assetAddress: weth_dth,
    oracleAddress: dhedgeMedianTwapAggregator.address,
    oracleName: "dhtTwapOracle",
  });

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
