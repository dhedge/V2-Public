import { ethers } from "hardhat";
import { BigNumber } from "ethers";

import { IERC20, IVelodromeNonfungiblePositionManager, PoolLogic, PoolManagerLogic } from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IVelodromeCLTestParams,
  deployVelodromeCLInfrastructure,
  iERC20,
  iERC721,
} from "./velodromeCLTestDeploymentHelpers";
import { deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { VelodromeCLMintSettings, getCurrentTick, mintLpAsPool } from "../../utils/velodromeCLUtils";

type initializedTestReturnObjects = {
  logicOwner: SignerWithAddress;
  manager: SignerWithAddress;
  poolLogicProxy: PoolLogic;
  poolManagerLogicProxy: PoolManagerLogic;
  tokenId: BigNumber;
  PROTOCOL_TOKEN: IERC20;
  nonfungiblePositionManager: IVelodromeNonfungiblePositionManager;
  token0: IERC20;
  token1: IERC20;
  testParams: IVelodromeCLTestParams;
};

export const setupGaugeContractGuardTestBefore = async (
  testParams: IVelodromeCLTestParams,
): Promise<initializedTestReturnObjects> => {
  const { pairs, factory } = testParams;
  const { bothSupportedPair } = pairs;

  const deployments = await deployBackboneContracts(testParams);

  const manager = deployments.manager;
  const logicOwner = deployments.owner;
  const poolFactory = deployments.poolFactory;

  const { nonfungiblePositionManager, PROTOCOL_TOKEN } = await deployVelodromeCLInfrastructure(deployments, testParams);

  const funds = await createFund(
    poolFactory,
    logicOwner,
    manager,
    [
      { asset: bothSupportedPair.token0, isDeposit: true },
      { asset: bothSupportedPair.token1, isDeposit: true },
      { asset: PROTOCOL_TOKEN.address, isDeposit: false },
    ],
    {
      performance: BigNumber.from("0"),
      management: BigNumber.from("0"),
    },
  );
  const poolLogicProxy = funds.poolLogicProxy;
  const poolManagerLogicProxy = funds.poolManagerLogicProxy;

  await getAccountToken(
    bothSupportedPair.amount0.mul(2),
    logicOwner.address,
    bothSupportedPair.token0,
    bothSupportedPair.token0Slot,
  );
  await getAccountToken(
    bothSupportedPair.amount1.mul(2),
    logicOwner.address,
    bothSupportedPair.token1,
    bothSupportedPair.token1Slot,
  );

  const token0 = await ethers.getContractAt("IERC20", bothSupportedPair.token0);
  const token1 = await ethers.getContractAt("IERC20", bothSupportedPair.token1);

  await token1.approve(poolLogicProxy.address, bothSupportedPair.amount1.mul(2));
  await token0.approve(poolLogicProxy.address, bothSupportedPair.amount0.mul(2));
  await poolLogicProxy.deposit(bothSupportedPair.token0, bothSupportedPair.amount0.mul(2));

  await poolLogicProxy.deposit(bothSupportedPair.token1, bothSupportedPair.amount1.mul(2));
  let approveABI = iERC20.encodeFunctionData("approve", [
    nonfungiblePositionManager.address,
    bothSupportedPair.amount0,
  ]);
  await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token0, approveABI);
  approveABI = iERC20.encodeFunctionData("approve", [nonfungiblePositionManager.address, bothSupportedPair.amount1]);
  await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token1, approveABI);

  const token0Address = bothSupportedPair.token0;
  const token1Address = bothSupportedPair.token1;
  const tickSpacing = bothSupportedPair.tickSpacing;
  const tick = await getCurrentTick(factory, bothSupportedPair);
  const mintSettings: VelodromeCLMintSettings = {
    token0: token0Address,
    token1: token1Address,
    tickSpacing,
    amount0: bothSupportedPair.amount0,
    amount1: bothSupportedPair.amount1,
    tickLower: tick - tickSpacing,
    tickUpper: tick + tickSpacing,
  };

  await poolManagerLogicProxy
    .connect(manager)
    .changeAssets([{ asset: nonfungiblePositionManager.address, isDeposit: false }], []);
  await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);

  const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

  //approve for staking in gauge
  approveABI = iERC721.encodeFunctionData("approve", [bothSupportedPair.gauge, tokenId]);
  await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, approveABI);

  return {
    logicOwner,
    manager,
    poolLogicProxy,
    poolManagerLogicProxy,
    tokenId,
    PROTOCOL_TOKEN,
    nonfungiblePositionManager,
    token0,
    token1,
    testParams,
  };
};
