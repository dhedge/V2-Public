import fs from "fs";
import csv from "csvtojson";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx } from "../../../helpers/safe";
import { tryVerify } from "../../../helpers/verify";
import { addOrReplaceGuardInFile } from "../../../helpers/csv";
import { IDeployedAssetGuard, IJob, IProposeTxProperties, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { AssetType } from "../assetsJob";
import { TAssetConfig } from "../oracles/oracleTypes";

/// Asset types a new ERC20Guard deployment must be registered for: every type mapped to
/// ERC20Guard in the asset guards CSV that still has assets in the assets JSON, plus type 0,
/// which PoolLogicLib reads directly as the fallback guard for any unregistered asset.
const resolveErc20GuardAssetTypes = async (filenames: IFileNames): Promise<number[]> => {
  const csvAssetGuards: IDeployedAssetGuard[] = await csv().fromFile(filenames.assetGuardsFileName);
  const assets: TAssetConfig[] = JSON.parse(fs.readFileSync(filenames.assetsFileName, "utf-8"));
  const assetTypesInUse = new Set<number>(assets.map((asset) => Number(asset.assetType)));

  const assetTypes = new Set<number>([AssetType["Chainlink direct USD price feed with 8 decimals"]]);
  for (const csvAssetGuard of csvAssetGuards) {
    if (csvAssetGuard.guardName === "ERC20Guard" && assetTypesInUse.has(Number(csvAssetGuard.assetType))) {
      assetTypes.add(Number(csvAssetGuard.assetType));
    }
  }
  return [...assetTypes].sort((a, b) => a - b);
};

export const erc20GuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  versions: IVersions,
  filenames: IFileNames,
  addresses: IProposeTxProperties,
) => {
  const ethers = hre.ethers;
  const Governance = await hre.artifacts.readArtifact("Governance");
  const governanceABI = new ethers.utils.Interface(Governance.abi);

  console.log("Will deploy ERC20Guard");

  if (config.execute) {
    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    await erc20Guard.deployed();
    const erc20GuardAddress = erc20Guard.address;
    console.log("ERC20Guard deployed at", erc20GuardAddress);
    versions[config.newTag].contracts.ERC20Guard = erc20GuardAddress;
    await tryVerify(hre, erc20GuardAddress, "contracts/guards/assetGuards/ERC20Guard.sol:ERC20Guard", []);

    const governance = await ethers.getContractAt("Governance", versions[config.oldTag].contracts.Governance);

    const assetTypesToSetGuardTo = await resolveErc20GuardAssetTypes(filenames);

    for (const assetType of assetTypesToSetGuardTo) {
      const existingAssetGuardAddress = await governance.assetGuards(assetType);

      // If the asset guard is not set, set it
      if (existingAssetGuardAddress.toLowerCase() !== erc20GuardAddress.toLowerCase()) {
        console.log(`Setting ERC20Guard for assetType ${assetType}`);
        const setAssetGuardTxData = governanceABI.encodeFunctionData("setAssetGuard", [assetType, erc20GuardAddress]);

        await proposeTx(
          versions[config.oldTag].contracts.Governance,
          setAssetGuardTxData,
          `setAssetGuard for ERC20Guard AssetType ${assetType}`,
          config,
          addresses,
        );
      }

      const deployedGuard = {
        assetType,
        guardName: "ERC20Guard",
        guardAddress: erc20GuardAddress,
        description: "ERC20 tokens",
      };

      await addOrReplaceGuardInFile(filenames.assetGuardsFileName, deployedGuard, "assetType");
    }
  }
};
