import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../../deploymentHelpers";
import { IAddresses, IFileNames, IJob, IUpgradeConfig, IVersions } from "../../../types";

export const ondoAttestationOracleConfigurationJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  _filenames: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Will configure OndoAttestationOracle");

  const ondoAttestationOracleProxy = versions[config.newTag].contracts.OndoAttestationOracleProxy;
  if (!ondoAttestationOracleProxy) return console.warn("OndoAttestationOracleProxy not deployed... skipping.");

  const attestationConfig = addresses.ondo?.attestationOracle;
  if (!attestationConfig) return console.warn("ondo.attestationOracle not configured... skipping.");

  const ethers = hre.ethers;

  const OndoAttestationOracle = await hre.artifacts.readArtifact("OndoAttestationOracle");
  const ondoAttestationOracleAbi = new ethers.utils.Interface(OndoAttestationOracle.abi);
  const oracle = new ethers.Contract(ondoAttestationOracleProxy, OndoAttestationOracle.abi, ethers.provider);

  // Check if allowedUserId needs updating
  const currentAllowedUserId: string = await oracle.allowedUserId();
  const desiredAllowedUserId = attestationConfig.allowedUserId;

  if (currentAllowedUserId !== desiredAllowedUserId) {
    console.log(`allowedUserId mismatch: current=${currentAllowedUserId}, desired=${desiredAllowedUserId}`);

    const setAllowedUserIdTxData = ondoAttestationOracleAbi.encodeFunctionData("setAllowedUserId", [
      desiredAllowedUserId,
    ]);

    await proposeTx(
      ondoAttestationOracleProxy,
      setAllowedUserIdTxData,
      "OndoAttestationOracle - Set allowedUserId",
      config,
      addresses,
    );
  } else {
    console.log("allowedUserId already up to date, skipping.");
  }

  // Check if proofConfig needs updating
  const currentProofConfig = await oracle.proofConfig();
  const desiredProofConfig = {
    maxProofAge: ethers.BigNumber.from(attestationConfig.maxProofAge),
    sanityDeviationBps: ethers.BigNumber.from(attestationConfig.sanityDeviationBps),
    minQuoteValue: ethers.BigNumber.from(attestationConfig.minQuoteValue),
    maxQuoteValue: ethers.BigNumber.from(attestationConfig.maxQuoteValue),
  };

  const proofConfigChanged =
    !currentProofConfig.maxProofAge.eq(desiredProofConfig.maxProofAge) ||
    !currentProofConfig.sanityDeviationBps.eq(desiredProofConfig.sanityDeviationBps) ||
    !currentProofConfig.minQuoteValue.eq(desiredProofConfig.minQuoteValue) ||
    !currentProofConfig.maxQuoteValue.eq(desiredProofConfig.maxQuoteValue);

  if (proofConfigChanged) {
    console.log("proofConfig mismatch:");
    console.log(
      `  maxProofAge: current=${currentProofConfig.maxProofAge.toString()}, desired=${desiredProofConfig.maxProofAge.toString()}`,
    );
    console.log(
      `  sanityDeviationBps: current=${currentProofConfig.sanityDeviationBps.toString()}, desired=${desiredProofConfig.sanityDeviationBps.toString()}`,
    );
    console.log(
      `  minQuoteValue: current=${currentProofConfig.minQuoteValue.toString()}, desired=${desiredProofConfig.minQuoteValue.toString()}`,
    );
    console.log(
      `  maxQuoteValue: current=${currentProofConfig.maxQuoteValue.toString()}, desired=${desiredProofConfig.maxQuoteValue.toString()}`,
    );

    const setProofConfigTxData = ondoAttestationOracleAbi.encodeFunctionData("setProofConfig", [
      [
        desiredProofConfig.maxProofAge,
        desiredProofConfig.sanityDeviationBps,
        desiredProofConfig.minQuoteValue,
        desiredProofConfig.maxQuoteValue,
      ],
    ]);

    await proposeTx(
      ondoAttestationOracleProxy,
      setProofConfigTxData,
      "OndoAttestationOracle - Set proofConfig",
      config,
      addresses,
    );
  } else {
    console.log("proofConfig already up to date, skipping.");
  }
};
