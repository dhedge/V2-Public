import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../deploymentHelpers";
import { IAddresses, IJob, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { addOrReplaceGuardInFile } from "../helpers";

const MAX_NUMBER_LP_POSITIONS = 3;

export const uniswapV3NonFungiblePositionGuardJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: IFileNames,
  addresses: IAddresses,
) => {
  if (!addresses.uniV3.uniSwapV3NonfungiblePositionManagerAddress) {
    throw new Error("No config for uniSwapV3NonfungiblePositionManagerAddress");
  }

  const nftTrackerAddress = versions[config.oldTag].contracts.DhedgeNftTrackerStorageProxy;
  if (!nftTrackerAddress) {
    console.warn("nftTracker not deployed, skipping");
    return;
  }

  console.log("Will deploy uniswapv3nonfungiblepositionguard");
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const UniswapV3NonfungiblePositionGuard = await ethers.getContractFactory("UniswapV3NonfungiblePositionGuard");
    const uniswapV3NonfungiblePositionGuard = await UniswapV3NonfungiblePositionGuard.deploy(
      MAX_NUMBER_LP_POSITIONS,
      nftTrackerAddress,
    );
    await uniswapV3NonfungiblePositionGuard.deployed();
    console.log("UniswapV3NonfungiblePositionGuard deployed at", uniswapV3NonfungiblePositionGuard.address);
    versions[config.newTag].contracts.UniswapV3NonfungiblePositionGuard = uniswapV3NonfungiblePositionGuard.address;

    await tryVerify(
      hre,
      uniswapV3NonfungiblePositionGuard.address,
      "contracts/guards/contractGuards/uniswapV3/UniswapV3NonfungiblePositionGuard.sol:UniswapV3NonfungiblePositionGuard",
      [MAX_NUMBER_LP_POSITIONS, nftTrackerAddress],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.uniV3.uniSwapV3NonfungiblePositionManagerAddress,
      uniswapV3NonfungiblePositionGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for UniswapV3NonfungiblePositionGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      contractAddress: addresses.uniV3.uniSwapV3NonfungiblePositionManagerAddress,
      guardName: "UniswapV3NonfungiblePositionGuard",
      guardAddress: uniswapV3NonfungiblePositionGuard.address,
      description: "Uniswap V3 Nonfungible Position contract",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "contractAddress");
  }
};
