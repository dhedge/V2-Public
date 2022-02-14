import { HardhatRuntimeEnvironment } from "hardhat/types";
import { proposeTx, tryVerify } from "../../../Helpers";
import { addOrReplaceGuardInFile } from "../helpers";
import { Address, IJob, IProposeTxProperties, IUpgradeConfig, IVersions } from "../../../types";

const MAX_NUMBER_LP_POSITIONS = 3;

export const uniswapV3NonFungiblePositionGuard: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  // TODO: This optimally should not be mutated
  versions: IVersions,
  filenames: { contractGuardsFileName: string },
  addresses: { uniSwapV3NonfungiblePositionManagerAddress?: Address } & IProposeTxProperties,
) => {
  if (!addresses.uniSwapV3NonfungiblePositionManagerAddress) {
    throw new Error("No config for uniSwapV3NonfungiblePositionManagerAddress");
  }

  console.log("Will deploy uniswapv3nonfungiblepositionguard");
  if (config.execute) {
    const ethers = hre.ethers;
    const Governance = await hre.artifacts.readArtifact("Governance");
    const governanceABI = new ethers.utils.Interface(Governance.abi);
    const UniswapV3NonfungiblePositionGuard = await ethers.getContractFactory("UniswapV3NonfungiblePositionGuard");
    const uniswapV3NonfungiblePositionGuard = await UniswapV3NonfungiblePositionGuard.deploy(
      addresses.uniSwapV3NonfungiblePositionManagerAddress,
      MAX_NUMBER_LP_POSITIONS,
    );
    await uniswapV3NonfungiblePositionGuard.deployed();
    console.log("UniswapV3NonfungiblePositionGuard deployed at", uniswapV3NonfungiblePositionGuard.address);
    versions[config.newTag].contracts.UniswapV3NonfungiblePositionGuard = uniswapV3NonfungiblePositionGuard.address;

    await tryVerify(
      hre,
      uniswapV3NonfungiblePositionGuard.address,
      "contracts/guards/contractGuards/uniswapV3/UniswapV3NonfungiblePositionGuard.sol:UniswapV3NonfungiblePositionGuard",
      [addresses.uniSwapV3NonfungiblePositionManagerAddress, MAX_NUMBER_LP_POSITIONS],
    );

    const setContractGuardABI = governanceABI.encodeFunctionData("setContractGuard", [
      addresses.uniSwapV3NonfungiblePositionManagerAddress,
      uniswapV3NonfungiblePositionGuard.address,
    ]);

    await proposeTx(
      versions[config.oldTag].contracts.Governance,
      setContractGuardABI,
      "setContractGuard for uniswapV3NonfungiblePositionGuard",
      config,
      addresses,
    );

    const deployedGuard = {
      ContractAddress: addresses.uniSwapV3NonfungiblePositionManagerAddress,
      GuardName: "UniswapV3NonfungiblePositionGuard",
      GuardAddress: uniswapV3NonfungiblePositionGuard.address,
      Description: "Uniswap V3 Nonfungible Position contract",
    };

    await addOrReplaceGuardInFile(filenames.contractGuardsFileName, deployedGuard, "ContractAddress");
  }
};
