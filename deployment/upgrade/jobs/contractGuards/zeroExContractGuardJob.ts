import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { IJob, IUpgradeConfig, IVersions, IFileNames, IAddresses } from "../../../types";

export const zeroExContractGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  const zeroExExchangeProxy = addresses.zeroExExchangeProxy;

  if (!zeroExExchangeProxy) {
    return console.warn("ZeroEx ExchangeProxy address not configured for zeroExContractGuard: skipping.");
  }

  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy zeroExContractGuard");

  if (config.execute) {
    const ZeroExContractGuard = await ethers.getContractFactory("ZeroExContractGuard");
    const slippageAccumulatorAddress = versions[config.oldTag].contracts.SlippageAccumulator;

    if (!slippageAccumulatorAddress) {
      return console.warn("SlippageAccumulator could not be found: skipping.");
    }

    const args: [string] = [slippageAccumulatorAddress];
    const zeroExContractGuard = await ZeroExContractGuard.deploy(...args);
    await zeroExContractGuard.deployed();
    const zeroExContractGuardAddress = zeroExContractGuard.address;
    console.log("zeroExContractGuard deployed at", zeroExContractGuardAddress);
    versions[config.newTag].contracts.ZeroExContractGuard = zeroExContractGuardAddress;

    await tryVerify(
      hre,
      zeroExContractGuardAddress,
      "contracts/guards/contractGuards/ZeroExContractGuard.sol:ZeroExContractGuard",
      args,
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      zeroExExchangeProxy,
      zeroExContractGuardAddress,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for ZeroExContractGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: zeroExExchangeProxy,
      guardName: "ZeroExContractGuard",
      guardAddress: zeroExContractGuardAddress,
      description: "ZeroEx Exchange Proxy",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
