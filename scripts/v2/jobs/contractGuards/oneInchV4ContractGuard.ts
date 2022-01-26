import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { IDeployedContractGuard, IJob, IUpgradeConfig } from "../types";

export const oneInchV4ContractGuard: IJob<IDeployedContractGuard[] | undefined> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This should be types and optimally should not be mutated
  versions: any,
  filenames: {},
  addresses: { protocolDaoAddress: string; oneInchV4RouterAddress?: string },
) => {
  if (!addresses.oneInchV4RouterAddress) {
    console.warn("oneInchV4RouterAddress not configured for oneInchV4ContractGuard: skipping.");
    return;
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy oneinchv4guard");
  if (config.execute) {
    const OneInchV3Guard = await ethers.getContractFactory("OneInchV3Guard");
    const oneInchV4Guard = await OneInchV3Guard.deploy(10, 100); // set slippage 10%
    await oneInchV4Guard.deployed();
    console.log("oneInchV4Guard deployed at", oneInchV4Guard.address);
    versions[config.newTag].contracts.OneInchV4Guard = oneInchV4Guard.address;

    await tryVerify(
      hre,
      oneInchV4Guard.address,
      "contracts/guards/contractGuards/OneInchV3Guard.sol:OneInchV3Guard",
      [10, 100],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.oneInchV4RouterAddress,
      oneInchV4Guard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for oneInchV4Guard",
      config.execute,
      config.restartnonce,
    );

    return [
      {
        ContractAddress: addresses.oneInchV4RouterAddress,
        GuardName: "OneInchV4Guard",
        GuardAddress: oneInchV4Guard.address,
        Description: "OneInch V4 Router",
      },
    ];
  }
};
