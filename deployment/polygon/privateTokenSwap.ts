import { utils } from "ethers";
import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { PrivateTokenSwap } from "../../types";
import { tryVerify } from "../deploymentHelpers";

// Deployment params
const users: string[] = [
  "", // add addresses as needed
  "", // add addresses as needed
  "", // add addresses as needed
  "", // add addresses as needed
  "", // add addresses as needed
];
const owner = ""; // owner address for the deployed contracts
const originalToken = "0x8c92e38eca8210f4fcbf17f0951b198dd7668292"; // DHT
const exchangeToken = "0x2791bca1f2de4661ed88a30c99a7a9449aa84174"; // USDC
const exchangeRate = utils.parseUnits("0.075", 18); // $0.075

task("privateTokenSwap", "Deploy Private Token Swap contract").setAction(async (taskArgs, hre) => {
  const ethers = hre.ethers;
  const network = await ethers.provider.getNetwork();
  console.log("Network:", network.name);
  await hre.run("compile");

  for (const user of users) {
    const privateTokenSwap = await deployContract(hre, user);
    console.log("Private Token Swap deployed to", privateTokenSwap, "for user", user);
  }
});

const deployContract = async (hre: HardhatRuntimeEnvironment, user: string) => {
  const ethers = hre.ethers;

  // Deploy
  const initParams = [originalToken, exchangeToken, exchangeRate, user];
  const privateTokenSwap: PrivateTokenSwap = (await ethers.deployContract(
    "PrivateTokenSwap",
    initParams,
  )) as PrivateTokenSwap;
  await privateTokenSwap.deployed();
  const privateTokenSwapAddress = privateTokenSwap.address;

  console.log("privateTokenSwap deployed to:", privateTokenSwapAddress);

  const transferOwnershipTx = await privateTokenSwap.transferOwnership(owner);
  await transferOwnershipTx.wait(5);
  console.log("Ownership transferred to", owner);

  await tryVerify(hre, privateTokenSwapAddress, "contracts/swappers/PrivateTokenSwap.sol:PrivateTokenSwap", initParams);

  return privateTokenSwapAddress;
};
