import { ethers } from "hardhat";
import { expect } from "chai";

import { units } from "../../../testHelpers";
import { polygonChainData } from "../../../../config/chainData/polygonData";
const { balancer, assets, assetsBalanceOfSlot } = polygonChainData;

import {
  IBalancerV2Vault__factory,
  IERC20__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../../utils/createFund";
import { approveToken, getAccountToken } from "../../utils/getAccountTokens";

describe("Balancer Stable Pool Aggregator Test", function () {
  const wmaticAmount = units(10);
  const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault__factory.abi);
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let snapId: string;

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    snapId = await utils.evmTakeSnap();
    poolFactory = deployments.poolFactory;
    const fund = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.wmatic, isDeposit: true },
      { asset: assets.maticX, isDeposit: true },
      { asset: balancer.stableComposablePools.wMaticStMatic, isDeposit: false },
      { asset: balancer.stableComposablePools.wMaticMaticX, isDeposit: false },
    ]);

    poolLogicProxy = fund.poolLogicProxy;
    poolManagerLogicProxy = fund.poolManagerLogicProxy;

    await getAccountToken(wmaticAmount, logicOwner.address, assets.wmatic, assetsBalanceOfSlot.wmatic);
    await approveToken(logicOwner, poolLogicProxy.address, assets.wmatic, wmaticAmount);
    await poolLogicProxy.deposit(assets.wmatic, wmaticAmount);
    snapId = await utils.evmTakeSnap();
  });

  it("Composable Stable Pool - Wmatc, stMatic", async function () {
    // We LP all the assets so we don't pay the join swap fee
    const balancerPool = await ethers.getContractAt("IBalancerPool", balancer.stableComposablePools.wMaticStMatic);
    const poolId = await balancerPool.getPoolId();
    const assetsArray = [assets.wmatic, assets.stMatic, balancer.stableComposablePools.wMaticStMatic];
    const maxAmountsIn = [wmaticAmount, 0, 0];

    const joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      poolLogicProxy.address,
      poolLogicProxy.address,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, [wmaticAmount, 0], 0]),
        false,
      ],
    ]);
    const approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, wmaticAmount]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    await poolLogicProxy.connect(manager).execTransaction(assets.wmatic, approveABI);
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx);
    // Check the fund is still worth $200
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    // All value is in the balancer pool
    expect(
      await poolManagerLogicProxy["assetValue(address)"](balancer.stableComposablePools.wMaticStMatic),
    ).to.be.equal(totalFundValueAfter);
    // 1%
    expect(totalFundValueAfter).to.be.closeTo(totalFundValueBefore, totalFundValueBefore.div(1000));
  });

  it("Composable Stable Pool - Wmatc, MaticX", async function () {
    // We LP all the assets so we don't pay the join swap fee
    const balancerPool = await ethers.getContractAt("IBalancerPool", balancer.stableComposablePools.wMaticMaticX);
    const poolId = await balancerPool.getPoolId();
    const assetsArray = [assets.wmatic, balancer.stableComposablePools.wMaticMaticX, assets.maticX];
    const maxAmountsIn = [wmaticAmount, 0, 0];

    const joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      poolLogicProxy.address,
      poolLogicProxy.address,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, [wmaticAmount, 0], 0]),
        false,
      ],
    ]);
    const approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, wmaticAmount]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    await poolLogicProxy.connect(manager).execTransaction(assets.wmatic, approveABI);
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx);
    // Check the fund is still worth $200
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    // All value is in the balancer pool
    expect(await poolManagerLogicProxy["assetValue(address)"](balancer.stableComposablePools.wMaticMaticX)).to.be.equal(
      totalFundValueAfter,
    );
    // 1%
    expect(totalFundValueAfter).to.be.closeTo(totalFundValueBefore, totalFundValueBefore.div(500));

    const minAmountsOut = [0, 0, 0];
    const exitTx = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      poolLogicProxy.address,
      poolLogicProxy.address,
      [
        assetsArray,
        minAmountsOut,
        ethers.utils.defaultAbiCoder.encode(
          ["uint256", "uint256", "uint256"],
          [0, await balancerPool.balanceOf(poolLogicProxy.address), 1],
        ),
        false,
      ],
    ]);

    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, exitTx);

    const maticX = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.maticX);
    expect(await maticX.balanceOf(poolLogicProxy.address)).to.be.gt(0);
  });
});
