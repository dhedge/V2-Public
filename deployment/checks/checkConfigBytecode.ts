import { assert } from "chai";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Contract } from "ethers";

import { InitType } from "./initialize";
import { isSameBytecode } from "../deploymentHelpers";
import { IContracts } from "../types";

export const checkBytecode = async (initializeData: InitType, hre: HardhatRuntimeEnvironment) => {
  const { ethers } = hre;
  const { contracts } = initializeData;

  const PoolFactoryProxy = await ethers.getContractFactory("PoolFactory");
  const PoolFactory = PoolFactoryProxy;
  const Governance = await ethers.getContractFactory("Governance");
  const AssetHandlerProxy = await ethers.getContractFactory("AssetHandler");
  const AssetHandler = AssetHandlerProxy;
  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  const UniswapV2RouterGuard = await ethers.getContractFactory("ERC20Guard");
  const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
  const SushiMiniChefV2Guard = await ethers.getContractFactory("SushiMiniChefV2Guard");
  const AaveLendingPoolAssetGuard = await ethers.getContractFactory("AaveLendingPoolAssetGuard");
  const AaveLendingPoolGuardV2 = await ethers.getContractFactory("AaveLendingPoolGuardV2");
  const AaveLendingPoolGuardV3 = await ethers.getContractFactory("AaveLendingPoolGuardV3");
  const LendingEnabledAssetGuard = await ethers.getContractFactory("LendingEnabledAssetGuard");
  const AaveIncentivesControllerGuard = await ethers.getContractFactory("AaveIncentivesControllerGuard");
  const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
  const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");
  const QuickStakingRewardsGuard = await ethers.getContractFactory("QuickStakingRewardsGuard");
  const OneInchV4Guard = await ethers.getContractFactory("OneInchV4Guard");
  const BalancerV2Guard = await ethers.getContractFactory("BalancerV2Guard");

  const contractsArray = [
    { contract: Governance, name: "Governance" },
    { contract: PoolFactory, name: "PoolFactory" },
    { contract: PoolLogic, name: "PoolLogic" },
    { contract: PoolManagerLogic, name: "PoolManagerLogic" },
    { contract: AssetHandler, name: "AssetHandler" },
    { contract: ERC20Guard, name: "ERC20Guard" },
    { contract: UniswapV2RouterGuard, name: "UniswapV2RouterGuard" },
    { contract: SushiMiniChefV2Guard, name: "SushiMiniChefV2Guard" },
    { contract: AaveLendingPoolAssetGuard, name: "AaveLendingPoolAssetGuard" },
    { contract: AaveLendingPoolGuardV2, name: "AaveLendingPoolGuardV2" },
    { contract: AaveLendingPoolGuardV3, name: "AaveLendingPoolGuardV3" },
    { contract: LendingEnabledAssetGuard, name: "LendingEnabledAssetGuard" },
    { contract: AaveIncentivesControllerGuard, name: "AaveIncentivesControllerGuard" },
    { contract: OpenAssetGuard, name: "OpenAssetGuard" },
    { contract: QuickLPAssetGuard, name: "QuickLPAssetGuard" },
    { contract: QuickStakingRewardsGuard, name: "QuickStakingRewardsGuard" },
    { contract: OneInchV4Guard, name: "OneInchV4Guard" },
    { contract: BalancerV2Guard, name: "BalancerV2Guard" },
  ];

  // Check latest contract bytecodes (what needs to be upgraded on next release)
  console.log("Checking latest bytecodes against last deployment..");
  await hre.run("compile");

  const bytecodeErrors: string[] = [];
  for (const contract of contractsArray) {
    const contractAddress = contracts[contract.name as keyof IContracts];

    if (contractAddress) {
      const creationBytecode = contract.contract.bytecode;
      const runtimeBytecode = await ethers.provider.getCode(contractAddress as string);
      const bytecodeCheck = isSameBytecode(creationBytecode, runtimeBytecode);
      if (runtimeBytecode.length < 10) {
        bytecodeErrors.push(`Missing bytecode in deployed address for ${contract.name}`);
        continue;
      }
      if (!bytecodeCheck) {
        bytecodeErrors.push(`Bytecode difference found for ${contract.name}`);
        continue;
      }
    }
  }

  // Check asset aggregators
  for (const asset of contracts.Assets) {
    if (asset.oracleType) {
      let aggregator: Contract;
      try {
        aggregator = (await ethers.getContractFactory(asset.oracleType)) as Contract;
      } catch {
        // Skip this oracle. Not deployed by dHEDGE.
        continue;
      }
      if (aggregator?.bytecode) {
        const creationBytecode = aggregator.bytecode;
        const runtimeBytecode = await ethers.provider.getCode(asset.oracleAddress);
        const bytecodeCheck = isSameBytecode(creationBytecode, runtimeBytecode);
        if (runtimeBytecode.length < 10)
          bytecodeErrors.push(`Missing bytecode in deployed address for ${asset.oracleType}`);
        if (!bytecodeCheck) bytecodeErrors.push(`Bytecode difference found for ${asset.oracleType}`);
      }
    }
  }

  for (const bytecodeError of bytecodeErrors) {
    console.log(bytecodeError);
  }

  assert(!bytecodeErrors.length, "Bytecode differences or errors found.");

  console.log("Bytecode checks complete!");
  console.log("_________________________________________");
};
