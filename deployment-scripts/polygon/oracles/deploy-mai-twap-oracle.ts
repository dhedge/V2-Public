import hre from "hardhat";
import { ethers } from "hardhat";
import fs from "fs";

import { tryVerify } from "../../Helpers";

const oracleVersionFile = "./publish/polygon/oracle-versions.json";
const usdc_mai = "0x160532d2536175d65c03b97b0630a9802c274dad";
const mai = "0xa3fa99a148fa48d14ed51d610c367c61876997f1";
const usdc_oracle = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";

const main = async () => {
  await hre.run("compile:one", { contractName: "MedianTWAPAggregator" });

  const network = await ethers.provider.getNetwork();
  const versionsPath = "../../../publish/polygon/oracle-versions.json";
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const versions = require(versionsPath);
  const tag = Object.keys(versions)[Object.keys(versions).length - 1];
  versions[tag].network = network;
  versions[tag].date = new Date().toUTCString();

  const MedianTWAPAggregator = await ethers.getContractFactory("MedianTWAPAggregator");
  console.log("Deploying Median TWAP oracle..");
  const dhedgeMedianTwapAggregator = await MedianTWAPAggregator.deploy(usdc_mai, mai, usdc_oracle, 600, 5); // 10 minute update interval, 5% volatility trip
  await dhedgeMedianTwapAggregator.deployed();

  // wait 5 confirmations before verifying
  const tx = dhedgeMedianTwapAggregator.deployTransaction;
  await tx.wait(5);
  console.log(`Median TWAP oracle for ${usdc_mai} deployed at ${dhedgeMedianTwapAggregator.address}`);
  await tryVerify(
    hre,
    dhedgeMedianTwapAggregator.address,
    "contracts/priceAggregators/MedianTWAPAggregator.sol:MedianTWAPAggregator",
    [usdc_mai, mai, usdc_oracle, 600, 5],
  );

  versions[tag].contracts.Oracles.push({
    assetAddress: usdc_mai,
    oracleAddress: dhedgeMedianTwapAggregator.address,
    oracleName: "MaiMedianTWAPAggregator",
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
