import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const dhedgeStakingV2NFTJSONJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _: IFileNames,
  addresses: IAddresses,
) => {
  const ethers = hre.ethers;
  console.log("Will deploy DhedgeStakingV2NFTJson");
  if (config.execute) {
    const Contract = await ethers.getContractFactory("DhedgeStakingV2NFTJson");
    const contract = await Contract.deploy();
    await contract.deployed();

    await tryVerify(hre, contract.address, "contracts/stakingv2/DhedgeStakingV2NFTJson.sol:DhedgeStakingV2NFTJson", []);

    versions[config.newTag].contracts.DhedgeStakingV2NFTJson = contract.address;
    console.log("DhedgeStakingV2NFTJson deployed at ", contract.address);

    const stakingProxyAddress = versions[config.newTag].contracts.DhedgeStakingV2Proxy;
    if (stakingProxyAddress) {
      console.log("Proposing tx for new DhedgeStakingV2NFTJson in DhedgeStakingV2Proxy");
      const DhedgeStakingV2 = await hre.artifacts.readArtifact("DhedgeStakingV2");
      const dhedgeStakingV2ABI = new ethers.utils.Interface(DhedgeStakingV2.abi);

      const setTokenUriGeneratorABI = dhedgeStakingV2ABI.encodeFunctionData("setTokenUriGenerator", [contract.address]);
      await proposeTx(
        stakingProxyAddress,
        setTokenUriGeneratorABI,
        `set StakingV2 TokenUriGenerator to ${contract.address}`,
        config,
        addresses,
      );
    }
  }
};
