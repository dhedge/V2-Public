import { ethers } from "hardhat";
import { BigNumber } from "ethers";

import { ICompoundV3Comet__factory, ICompoundV3CometRewards__factory } from "../../../../types";
import { ICompoundV3TestParams, deployCompoundV3Infrastructure, iERC20 } from "./compoundV3TestDeploymentHelpers";
import { deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";

export const iCompoundV3Comet = new ethers.utils.Interface(ICompoundV3Comet__factory.abi);

export const iCompoundV3CometRewards = new ethers.utils.Interface(ICompoundV3CometRewards__factory.abi);

export const setupCompoundV3ContractGuardTestBefore = async (testParams: ICompoundV3TestParams) => {
  const { cAsset, baseAsset, baseAssetSlot, baseAssetAmount, rewards } = testParams;

  const deployments = await deployBackboneContracts(testParams);

  const manager = deployments.manager;
  const logicOwner = deployments.owner;
  const poolFactory = deployments.poolFactory;

  await deployCompoundV3Infrastructure(deployments, testParams);

  const funds = await createFund(
    poolFactory,
    logicOwner,
    manager,
    [
      { asset: cAsset, isDeposit: false },
      { asset: baseAsset, isDeposit: true },
    ],
    {
      performance: BigNumber.from("0"),
      management: BigNumber.from("0"),
    },
  );
  const poolLogicProxy = funds.poolLogicProxy;
  const poolManagerLogicProxy = funds.poolManagerLogicProxy;

  await getAccountToken(baseAssetAmount, logicOwner.address, baseAsset, baseAssetSlot);

  const baseAssetContract = await ethers.getContractAt("IERC20", baseAsset);

  await baseAssetContract.approve(poolLogicProxy.address, baseAssetAmount);
  await poolLogicProxy.deposit(baseAsset, baseAssetAmount);

  const approveTxData = iERC20.encodeFunctionData("approve", [cAsset, baseAssetAmount]);
  await poolLogicProxy.connect(manager).execTransaction(baseAsset, approveTxData);

  return {
    logicOwner,
    manager,
    poolLogicProxy,
    poolManagerLogicProxy,
    cAsset,
    baseAsset,
    baseAssetAmount,
    rewards,
    poolFactory,
  };
};
