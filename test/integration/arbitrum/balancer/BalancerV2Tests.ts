import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber, BigNumberish } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import {
  IERC20,
  IRewardsOnlyGauge,
  PoolLogic,
  PoolManagerLogic,
  IBalancerV2Vault__factory,
  IRewardsOnlyGauge__factory,
  IERC20__factory,
  IBalancerPool,
  IBalancerWeightedPool,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";
import { deployBalancerAssets, deployBalancerGuards } from "./deploymentTestHelpers";
import { units } from "../../../testHelpers";
import { getAccountToken } from "../../utils/getAccountTokens";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault__factory.abi);
const iRewardsOnlyGauge = new ethers.utils.Interface(IRewardsOnlyGauge__factory.abi);
const FIVE_MINUTES = 60 * 5;
const ONE_DAY = 60 * 60 * 24;
const TEN_USDC = units(10, 6);

describe("Balancer V2", () => {
  let deployments: IBackboneDeployments;
  let poolLogicProxy: PoolLogic;
  let poolManagerLogicProxy: PoolManagerLogic;
  let WETH: IERC20, wstETH: IERC20, BAL: IERC20, USDC: IERC20;
  let wstETH_WETH_STABLE_POOL: IBalancerPool;
  let wstETH_WETH_STABLE_POOL_GAUGE: IRewardsOnlyGauge;
  let wstETH_USDC_WEIGHTED_POOL: IBalancerWeightedPool;
  let poolLogicAddress: string;
  let wethAddress: string, wstETHAddress: string, usdcAddress: string;
  let balancerV2VaultAddress: string;
  let manager: SignerWithAddress, logicOwner: SignerWithAddress;

  utils.beforeAfterReset(beforeEach, afterEach);
  utils.beforeAfterReset(before, after);

  before(async () => {
    deployments = await deployBackboneContracts(arbitrumChainData);
    balancerV2VaultAddress = await deployBalancerGuards(deployments);
    const balancerAssets = await deployBalancerAssets(deployments);
    USDC = deployments.assets.USDC;
    WETH = deployments.assets.WETH;
    wstETH = balancerAssets.wstETH;
    BAL = balancerAssets.BAL;
    usdcAddress = USDC.address;
    wethAddress = WETH.address;
    wstETHAddress = wstETH.address;
    wstETH_WETH_STABLE_POOL = balancerAssets.wstETH_WETH_STABLE_POOL;
    wstETH_WETH_STABLE_POOL_GAUGE = balancerAssets.wstETH_WETH_STABLE_POOL_GAUGE;
    wstETH_USDC_WEIGHTED_POOL = balancerAssets.wstETH_USDC_WEIGHTED_POOL;
    manager = deployments.manager;
    logicOwner = deployments.owner;

    const supportedAssets = [
      {
        asset: wethAddress,
        isDeposit: true,
      },
      {
        asset: wstETHAddress,
        isDeposit: true,
      },
      {
        asset: wstETH_WETH_STABLE_POOL.address,
        isDeposit: false,
      },
      {
        asset: usdcAddress,
        isDeposit: true,
      },
      {
        asset: wstETH_USDC_WEIGHTED_POOL.address,
        isDeposit: false,
      },
    ];
    const poolProxies = await createFund(
      deployments.poolFactory,
      deployments.owner,
      deployments.manager,
      supportedAssets,
    );
    poolLogicProxy = poolProxies.poolLogicProxy;
    poolManagerLogicProxy = poolProxies.poolManagerLogicProxy;
    poolLogicAddress = poolLogicProxy.address;

    // Fund logic owner with assets
    await getAccountToken(units(100), logicOwner.address, wethAddress, arbitrumChainData.assetsBalanceOfSlot.weth);
    await getAccountToken(units(100), logicOwner.address, wstETHAddress, arbitrumChainData.assetsBalanceOfSlot.wstETH);
    await getAccountToken(units(100, 6), logicOwner.address, usdcAddress, arbitrumChainData.assetsBalanceOfSlot.usdc);

    // This is to test poolLogicProxy.withdraw()
    await deployments.poolFactory.setExitCooldown(FIVE_MINUTES);

    // Deposit assets into pool
    await WETH.approve(poolLogicAddress, units(10));
    await poolLogicProxy.deposit(wethAddress, units(10));
    await wstETH.approve(poolLogicAddress, units(10));
    await poolLogicProxy.deposit(wstETHAddress, units(10));
    await USDC.approve(poolLogicAddress, TEN_USDC);
    await poolLogicProxy.deposit(usdcAddress, TEN_USDC);

    // Approve Balancer Vault to spend assets
    const approveTxData = iERC20.encodeFunctionData("approve", [balancerV2VaultAddress, units(10)]);
    await poolLogicProxy.connect(manager).execTransaction(wethAddress, approveTxData);
    await poolLogicProxy.connect(manager).execTransaction(wstETHAddress, approveTxData);
    await poolLogicProxy
      .connect(manager)
      .execTransaction(usdcAddress, iERC20.encodeFunctionData("approve", [balancerV2VaultAddress, TEN_USDC]));
  });

  // assets should be sorted numerically by token address
  const joinBalancerPool = async (
    assets: { address: string; amount: BigNumberish }[],
    balancerPool: IBalancerPool,
    sender: string,
    recipient: string,
    userData?: string,
  ) => {
    const poolId = await balancerPool.getPoolId();
    const maxAmountsIn = assets.map(({ amount }) => amount);
    const userDataBytes =
      userData ??
      ethers.utils.defaultAbiCoder.encode(
        ["uint256", "uint256[]", "uint256"],
        // https://docs.balancer.fi/reference/joins-and-exits/pool-joins.html#userdata
        [1, maxAmountsIn, 0],
      ); // by default, use join with exact tokens
    const joinPoolTxData = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      sender,
      recipient,
      [assets.map(({ address }) => address), maxAmountsIn, userDataBytes, false],
    ]);
    await poolLogicProxy.connect(manager).execTransaction(balancerV2VaultAddress, joinPoolTxData);
  };

  const exitBalancerPool = async (
    assets: string[],
    balancerPool: IBalancerPool,
    sender: string,
    recipient: string,
    userData?: string,
  ) => {
    const poolId = await balancerPool.getPoolId();
    const minAmountsOut = [0, 0];
    const userDataBytes =
      userData ??
      ethers.utils.defaultAbiCoder.encode(
        ["uint256", "uint256", "uint256"],
        // https://docs.balancer.fi/reference/joins-and-exits/pool-exits.html#userdata
        [0, await balancerPool.balanceOf(poolLogicAddress), 0],
      ); // by default, use single asset exit (to wstETH)
    const exitPoolTxData = iBalancerV2Vault.encodeFunctionData("exitPool", [
      poolId,
      sender,
      recipient,
      [assets, minAmountsOut, userDataBytes, false],
    ]);
    await poolLogicProxy.connect(manager).execTransaction(balancerV2VaultAddress, exitPoolTxData);
  };

  it("should correctly price balancer MetaStablePool asset using its BalancerStablePoolAggregator", async () => {
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(10) },
        { address: wethAddress, amount: units(10) },
      ],
      wstETH_WETH_STABLE_POOL,
      poolLogicAddress,
      poolLogicAddress,
    );

    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

    // pool value is in the balancer pool plus left USDC
    expect(await poolManagerLogicProxy["assetValue(address)"](wstETH_WETH_STABLE_POOL.address)).to.be.equal(
      totalFundValueAfter.sub(await poolManagerLogicProxy["assetValue(address)"](usdcAddress)),
    );
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should correctly price balancer WeightedPool asset using its BalancerV2LPAggregator", async () => {
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(1) },
        { address: usdcAddress, amount: TEN_USDC },
      ],
      wstETH_USDC_WEIGHTED_POOL,
      poolLogicAddress,
      poolLogicAddress,
    );

    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should be able to join MetaStablePool with Exact Tokens Join", async () => {
    const amount = units(1);
    const wethBalanceBefore = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicAddress);
    const balancerPoolBalanceBefore = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    expect(balancerPoolBalanceBefore).to.equal(0);

    await joinBalancerPool(
      [
        { address: wstETHAddress, amount },
        { address: wethAddress, amount },
      ],
      wstETH_WETH_STABLE_POOL,
      poolLogicAddress,
      poolLogicAddress,
    );

    const wethBalanceAfter = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceAfter = await wstETH.balanceOf(poolLogicAddress);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    const balancerPoolBalanceAfter = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);
    expect(balancerPoolBalanceAfter).not.to.equal(0);

    expect(wethBalanceAfter).to.equal(wethBalanceBefore.sub(amount));
    expect(wstETHBalanceAfter).to.equal(wstETHBalanceBefore.sub(amount));
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should be able to join MetaStablePool with Single Token Join and Exact BPT Out", async () => {
    const wethBalanceBefore = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicAddress);
    const balancerPoolBalanceBefore = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    expect(balancerPoolBalanceBefore).to.equal(0);

    const amountOfBPTOut = units(1);
    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(1) },
        { address: wethAddress, amount: units(1) },
      ],
      wstETH_WETH_STABLE_POOL,
      poolLogicAddress,
      poolLogicAddress,
      ethers.utils.defaultAbiCoder.encode(
        ["uint256", "uint256", "uint256"],
        // https://docs.balancer.fi/reference/joins-and-exits/pool-exits.html#userdata
        [2, amountOfBPTOut, 0], // join using only wstETH
      ),
    );

    const wethBalanceAfter = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceAfter = await wstETH.balanceOf(poolLogicAddress);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    const balancerPoolBalanceAfter = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);
    expect(balancerPoolBalanceAfter).to.equal(amountOfBPTOut);

    expect(wethBalanceAfter).to.equal(wethBalanceBefore); // remains the same as we only used wstETH
    expect(wstETHBalanceAfter).to.be.lt(wstETHBalanceBefore);
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should be able to join WeightedPool with Exact Tokens Join", async () => {
    const amount = units(1);
    const usdcBalanceBefore = await USDC.balanceOf(poolLogicAddress);
    const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicAddress);
    const balancerPoolBalanceBefore = await wstETH_USDC_WEIGHTED_POOL.balanceOf(poolLogicAddress);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    expect(balancerPoolBalanceBefore).to.equal(0);

    await joinBalancerPool(
      [
        { address: wstETHAddress, amount },
        { address: usdcAddress, amount: TEN_USDC },
      ],
      wstETH_USDC_WEIGHTED_POOL,
      poolLogicAddress,
      poolLogicAddress,
    );

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicAddress);
    const wstETHBalanceAfter = await wstETH.balanceOf(poolLogicAddress);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    const balancerPoolBalanceAfter = await wstETH_USDC_WEIGHTED_POOL.balanceOf(poolLogicAddress);
    expect(balancerPoolBalanceAfter).not.to.equal(0);

    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore.sub(TEN_USDC));
    expect(wstETHBalanceAfter).to.equal(wstETHBalanceBefore.sub(amount));
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should be able to join WeightedPool with Single Token Join and Exact BPT Out", async () => {
    const usdcBalanceBefore = await USDC.balanceOf(poolLogicAddress);
    const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicAddress);
    const balancerPoolBalanceBefore = await wstETH_USDC_WEIGHTED_POOL.balanceOf(poolLogicAddress);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    expect(balancerPoolBalanceBefore).to.equal(0);

    const amountOfBPTOut = units(1);
    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(1) },
        { address: usdcAddress, amount: TEN_USDC },
      ],
      wstETH_USDC_WEIGHTED_POOL,
      poolLogicAddress,
      poolLogicAddress,
      ethers.utils.defaultAbiCoder.encode(
        ["uint256", "uint256", "uint256"],
        // https://docs.balancer.fi/reference/joins-and-exits/pool-exits.html#userdata
        [2, amountOfBPTOut, 0], // join using only wstETH
      ),
    );

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicAddress);
    const wstETHBalanceAfter = await wstETH.balanceOf(poolLogicAddress);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    const balancerPoolBalanceAfter = await wstETH_USDC_WEIGHTED_POOL.balanceOf(poolLogicAddress);
    expect(balancerPoolBalanceAfter).to.equal(amountOfBPTOut);

    expect(usdcBalanceAfter).to.equal(usdcBalanceBefore); // remains the same as we only used wstETH
    expect(wstETHBalanceAfter).to.be.lt(wstETHBalanceBefore);
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should be able to join WeightedPool with Proportional Join and Exact BPT Out", async () => {
    const usdcBalanceBefore = await USDC.balanceOf(poolLogicAddress);
    const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicAddress);
    const balancerPoolBalanceBefore = await wstETH_USDC_WEIGHTED_POOL.balanceOf(poolLogicAddress);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    expect(balancerPoolBalanceBefore).to.equal(0);

    const amountOfBPTOut = units(1, 17);
    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(1) },
        { address: usdcAddress, amount: TEN_USDC },
      ],
      wstETH_USDC_WEIGHTED_POOL,
      poolLogicAddress,
      poolLogicAddress,
      ethers.utils.defaultAbiCoder.encode(
        ["uint256", "uint256"],
        // https://docs.balancer.fi/reference/joins-and-exits/pool-exits.html#userdata
        [3, amountOfBPTOut],
      ),
    );

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicAddress);
    const wstETHBalanceAfter = await wstETH.balanceOf(poolLogicAddress);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    const balancerPoolBalanceAfter = await wstETH_USDC_WEIGHTED_POOL.balanceOf(poolLogicAddress);
    expect(balancerPoolBalanceAfter).to.equal(amountOfBPTOut);

    expect(usdcBalanceAfter).to.be.lt(usdcBalanceBefore);
    expect(wstETHBalanceAfter).to.be.lt(wstETHBalanceBefore);
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should be able to exit MetaStablePool with Single Asset Exit", async () => {
    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(1) },
        { address: wethAddress, amount: units(1) },
      ],
      wstETH_WETH_STABLE_POOL,
      poolLogicAddress,
      poolLogicAddress,
    );

    const wethBalanceBefore = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicAddress);
    const balancerPoolBalanceBefore = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(wethBalanceBefore).to.equal(units(9));
    expect(wstETHBalanceBefore).to.equal(units(9));
    expect(balancerPoolBalanceBefore).not.to.equal(0);

    await exitBalancerPool([wstETHAddress, wethAddress], wstETH_WETH_STABLE_POOL, poolLogicAddress, poolLogicAddress);

    const wethBalanceAfter = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceAfter = await wstETH.balanceOf(poolLogicAddress);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    const balancerPoolBalanceAfter = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);

    expect(wethBalanceAfter).to.be.equal(wethBalanceBefore); // we made a single exit to wstETH
    expect(wstETHBalanceAfter).to.be.gt(wstETHBalanceBefore);
    expect(balancerPoolBalanceAfter).to.equal(0);
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should be able to exit MetaStablePool with Proportional Exit", async () => {
    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(1) },
        { address: wethAddress, amount: units(1) },
      ],
      wstETH_WETH_STABLE_POOL,
      poolLogicAddress,
      poolLogicAddress,
    );

    const wethBalanceBefore = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicAddress);
    const balancerPoolBalanceBefore = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(wethBalanceBefore).to.equal(units(9));
    expect(wstETHBalanceBefore).to.equal(units(9));
    expect(balancerPoolBalanceBefore).not.to.equal(0);

    await exitBalancerPool(
      [wstETHAddress, wethAddress],
      wstETH_WETH_STABLE_POOL,
      poolLogicAddress,
      poolLogicAddress,
      ethers.utils.defaultAbiCoder.encode(
        ["uint256", "uint256"],
        // https://docs.balancer.fi/reference/joins-and-exits/pool-exits.html#userdata
        [1, await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress)],
      ),
    );

    const wethBalanceAfter = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceAfter = await wstETH.balanceOf(poolLogicAddress);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    const balancerPoolBalanceAfter = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);

    expect(wethBalanceAfter).to.be.gt(wethBalanceBefore);
    expect(wstETHBalanceAfter).to.be.gt(wstETHBalanceBefore);
    expect(balancerPoolBalanceAfter).to.equal(0);
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should be able to exit MetaStablePool with Custom Exit", async () => {
    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(2) },
        { address: wethAddress, amount: units(2) },
      ],
      wstETH_WETH_STABLE_POOL,
      poolLogicAddress,
      poolLogicAddress,
    );

    const wethBalanceBefore = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicAddress);
    const balancerPoolBalanceBefore = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(wethBalanceBefore).to.equal(units(8));
    expect(wstETHBalanceBefore).to.equal(units(8));
    expect(balancerPoolBalanceBefore).not.to.equal(0);

    await exitBalancerPool(
      [wstETHAddress, wethAddress],
      wstETH_WETH_STABLE_POOL,
      poolLogicAddress,
      poolLogicAddress,
      ethers.utils.defaultAbiCoder.encode(
        ["uint256", "uint256[]", "uint256"],
        // https://docs.balancer.fi/reference/joins-and-exits/pool-exits.html#userdata
        [2, [0, units(1)], await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress)], // passing explicit amounts to receive upon exit
      ),
    );

    const wethBalanceAfter = await WETH.balanceOf(poolLogicAddress);
    const wstETHBalanceAfter = await wstETH.balanceOf(poolLogicAddress);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    const balancerPoolBalanceAfter = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicAddress);

    expect(wethBalanceAfter).to.be.gt(wethBalanceBefore);
    expect(wstETHBalanceAfter).to.be.equal(wstETHBalanceBefore); // we passed 0 amount of wstETH to receive
    expect(balancerPoolBalanceAfter).to.be.lt(balancerPoolBalanceBefore);
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should be able to exit WeightedPool with Single Asset Exit", async () => {
    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(1) },
        { address: usdcAddress, amount: TEN_USDC },
      ],
      wstETH_USDC_WEIGHTED_POOL,
      poolLogicAddress,
      poolLogicAddress,
    );

    const usdcBalanceBefore = await USDC.balanceOf(poolLogicAddress);
    const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicAddress);
    const balancerPoolBalanceBefore = await wstETH_USDC_WEIGHTED_POOL.balanceOf(poolLogicAddress);
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    expect(usdcBalanceBefore).to.equal(0);
    expect(wstETHBalanceBefore).to.equal(units(9));
    expect(balancerPoolBalanceBefore).not.to.equal(0);

    await exitBalancerPool([wstETHAddress, usdcAddress], wstETH_USDC_WEIGHTED_POOL, poolLogicAddress, poolLogicAddress);

    const usdcBalanceAfter = await USDC.balanceOf(poolLogicAddress);
    const wstETHBalanceAfter = await wstETH.balanceOf(poolLogicAddress);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    const balancerPoolBalanceAfter = await wstETH_USDC_WEIGHTED_POOL.balanceOf(poolLogicAddress);

    expect(usdcBalanceAfter).to.be.equal(usdcBalanceBefore); // we made a single exit to wstETH
    expect(wstETHBalanceAfter).to.be.gt(wstETHBalanceBefore);
    expect(balancerPoolBalanceAfter).to.equal(0);
    expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(10_000)); // this is 0.01% delta
  });

  it("should revert if sender is not pool", async () => {
    await expect(
      joinBalancerPool(
        [
          { address: wstETHAddress, amount: units(1) },
          { address: wethAddress, amount: units(1) },
        ],
        wstETH_WETH_STABLE_POOL,
        logicOwner.address,
        poolLogicAddress,
      ),
    ).to.be.revertedWith("sender is not pool");
    await expect(
      exitBalancerPool([wstETHAddress, wethAddress], wstETH_WETH_STABLE_POOL, logicOwner.address, poolLogicAddress),
    ).to.be.revertedWith("sender is not pool");
  });

  it("should revert if recipient is not pool", async () => {
    await expect(
      joinBalancerPool(
        [
          { address: wstETHAddress, amount: units(1) },
          { address: wethAddress, amount: units(1) },
        ],
        wstETH_WETH_STABLE_POOL,
        poolLogicAddress,
        manager.address,
      ),
    ).to.be.revertedWith("recipient is not pool");
    await expect(
      exitBalancerPool([wstETHAddress, wethAddress], wstETH_WETH_STABLE_POOL, poolLogicAddress, manager.address),
    ).to.be.revertedWith("recipient is not pool");
  });

  it("should revert on join if lp asset is disabled", async () => {
    await poolManagerLogicProxy.connect(manager).changeAssets([], [wstETH_WETH_STABLE_POOL.address]);
    await expect(
      joinBalancerPool(
        [
          { address: wstETHAddress, amount: units(1) },
          { address: wethAddress, amount: units(1) },
        ],
        wstETH_WETH_STABLE_POOL,
        poolLogicAddress,
        poolLogicAddress,
      ),
    ).to.be.revertedWith("unsupported lp asset");
  });

  it("should revert on exit if exiting to unsupported asset", async () => {
    await joinBalancerPool(
      [
        { address: wstETHAddress, amount: units(10) },
        { address: wethAddress, amount: units(10) },
      ],
      wstETH_WETH_STABLE_POOL,
      poolLogicAddress,
      poolLogicAddress,
    );
    await poolManagerLogicProxy.connect(manager).changeAssets([], [wstETHAddress]);
    await expect(
      exitBalancerPool([wstETHAddress, wethAddress], wstETH_WETH_STABLE_POOL, poolLogicAddress, poolLogicAddress),
    ).to.be.revertedWith("unsupported asset");
  });

  // Gauge block is copied from
  // - test/integration/polygon/balancerV2/BalancerV2GaugeContractGuardTest.ts
  // - test/integration/polygon/balancerV2/BalancerV2GaugeAssetGuardTest.ts
  describe("BalancerV2GaugeContractGuard", () => {
    let lpAmount: BigNumberish;

    before(async () => {
      await joinBalancerPool(
        [
          { address: wstETHAddress, amount: units(1) },
          { address: wethAddress, amount: units(1) },
        ],
        wstETH_WETH_STABLE_POOL,
        poolLogicAddress,
        poolLogicAddress,
      );
      lpAmount = await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicProxy.address);
      await poolLogicProxy
        .connect(manager)
        .execTransaction(
          wstETH_WETH_STABLE_POOL.address,
          iERC20.encodeFunctionData("approve", [wstETH_WETH_STABLE_POOL_GAUGE.address, lpAmount]),
        );
    });

    const stakeLPTokens = async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: BAL.address,
            isDeposit: false,
          },
          { asset: wstETH_WETH_STABLE_POOL_GAUGE.address, isDeposit: false },
        ],
        [],
      );
      const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI);
    };

    const stakeLPTokensAndLetTimeFly = async (seconds: number) => {
      await stakeLPTokens();

      await poolManagerLogicProxy.connect(manager).changeAssets([], [BAL.address, wstETH_WETH_STABLE_POOL.address]);

      await ethers.provider.send("evm_increaseTime", [seconds]);
      await ethers.provider.send("evm_mine", []);
    };

    describe("deposit", () => {
      describe("deposit(uint256)", () => {
        it("Reverts if gauge asset is not enabled", async () => {
          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI),
          ).to.revertedWith("enable gauge token");
        });

        it("Reverts if gauge reward tokens are not enabled", async () => {
          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
          await poolManagerLogicProxy
            .connect(manager)
            .changeAssets([{ asset: wstETH_WETH_STABLE_POOL_GAUGE.address, isDeposit: false }], []);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI),
          ).to.revertedWith("enable reward token");
        });

        it("Allow deposit", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
              { asset: wstETH_WETH_STABLE_POOL_GAUGE.address, isDeposit: false },
            ],
            [],
          );

          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
          await poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI);
        });
      });

      describe("deposit(uint256,address)", () => {
        it("Reverts if receiver is not pool", async () => {
          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address)", [
            lpAmount,
            manager.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI),
          ).to.revertedWith("user is not pool");
        });

        it("Reverts if gauge asset is not enabled", async () => {
          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address)", [
            lpAmount,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI),
          ).to.revertedWith("enable gauge token");
        });

        it("Reverts if gauge reward tokens are not enabled", async () => {
          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address)", [
            lpAmount,
            poolLogicProxy.address,
          ]);
          await poolManagerLogicProxy
            .connect(manager)
            .changeAssets([{ asset: wstETH_WETH_STABLE_POOL_GAUGE.address, isDeposit: false }], []);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI),
          ).to.revertedWith("enable reward token");
        });

        it("Allow deposit", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
              { asset: wstETH_WETH_STABLE_POOL_GAUGE.address, isDeposit: false },
            ],
            [],
          );

          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address)", [
            lpAmount,
            poolLogicProxy.address,
          ]);
          await poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI);
        });
      });

      describe("deposit(uint256,address,bool)", () => {
        it("Reverts if receiver is not pool", async () => {
          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address,bool)", [
            lpAmount,
            manager.address,
            true,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI),
          ).to.revertedWith("user is not pool");
        });

        it("Reverts if gauge asset is not enabled", async () => {
          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address,bool)", [
            lpAmount,
            poolLogicProxy.address,
            true,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI),
          ).to.revertedWith("enable gauge token");
        });

        it("Reverts if gauge reward tokens are not enabled", async () => {
          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address,bool)", [
            lpAmount,
            poolLogicProxy.address,
            true,
          ]);
          await poolManagerLogicProxy
            .connect(manager)
            .changeAssets([{ asset: wstETH_WETH_STABLE_POOL_GAUGE.address, isDeposit: false }], []);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI),
          ).to.revertedWith("enable reward token");
        });

        it("Allow deposit", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
              { asset: wstETH_WETH_STABLE_POOL_GAUGE.address, isDeposit: false },
            ],
            [],
          );

          const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address,bool)", [
            lpAmount,
            poolLogicProxy.address,
            true,
          ]);
          await poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, depositABI);
        });
      });
    });

    describe("withdraw", () => {
      beforeEach(async () => {
        await stakeLPTokensAndLetTimeFly(ONE_DAY);
      });

      describe("withdraw(uint256)", () => {
        it("Reverts if underlying balancer lp token is not enabled", async () => {
          const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256)", [lpAmount]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, withdrawABI),
          ).to.revertedWith("enable lp token");
        });

        it("Allows withdraw", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
              {
                asset: wstETH_WETH_STABLE_POOL.address,
                isDeposit: false,
              },
            ],
            [],
          );

          const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256)", [lpAmount]);
          await poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, withdrawABI);
        });
      });

      describe("withdraw(uint256,bool)", () => {
        it("Reverts if underlying balancer lp token is not enabled", async () => {
          const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256,bool)", [lpAmount, true]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, withdrawABI),
          ).to.revertedWith("enable lp token");
        });

        it("Reverts if claim is true and reward tokens are not enabled", async () => {
          const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256,bool)", [lpAmount, true]);
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: wstETH_WETH_STABLE_POOL.address,
                isDeposit: false,
              },
            ],
            [],
          );
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, withdrawABI),
          ).to.revertedWith("enable reward token");
        });

        it("Allows withdraw", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
              {
                asset: wstETH_WETH_STABLE_POOL.address,
                isDeposit: false,
              },
            ],
            [],
          );

          const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256,bool)", [lpAmount, true]);
          await poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, withdrawABI);
        });
      });
    });

    describe("claim", () => {
      beforeEach(async () => {
        await stakeLPTokensAndLetTimeFly(ONE_DAY);
        await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward_write(poolLogicProxy.address, BAL.address);
      });

      describe("claim_rewards()", () => {
        it("Reverts if rewards tokens are not enabled", async function () {
          if ((await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward(poolLogicProxy.address, BAL.address)).eq(0)) {
            console.log("Skipping... no rewards available");
            this.skip();
          } else {
            const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards()", []);
            await expect(
              poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, claimABI),
            ).to.revertedWith("enable reward token");
          }
        });

        it("Allows claim", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
            ],
            [],
          );
          const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards()", []);
          await poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, claimABI);
        });
      });

      describe("claim_rewards(address) - claim for", () => {
        it("Reverts if rewards tokens are not enabled", async function () {
          if ((await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward(poolLogicProxy.address, BAL.address)).eq(0)) {
            console.log("Skipping... no rewards available");
            this.skip();
          } else {
            const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address)", [poolLogicProxy.address]);
            await expect(
              poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, claimABI),
            ).to.revertedWith("enable reward token");
          }
        });

        it("Reverts if claim for is not pool", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
            ],
            [],
          );
          const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address)", [manager.address]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, claimABI),
          ).to.revertedWith("user is not pool");
        });

        it("Allows claim", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
            ],
            [],
          );
          const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address)", [poolLogicProxy.address]);
          await poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, claimABI);
        });
      });

      describe("claim_rewards(address,address) - claim for, claim to", () => {
        it("Reverts if rewards tokens are not enabled", async function () {
          if ((await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward(poolLogicProxy.address, BAL.address)).eq(0)) {
            console.log("Skipping... no rewards available");
            this.skip();
          } else {
            const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address,address)", [
              poolLogicProxy.address,
              poolLogicProxy.address,
            ]);
            await expect(
              poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, claimABI),
            ).to.revertedWith("enable reward token");
          }
        });

        it("Reverts if claim for is not pool", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
            ],
            [],
          );

          const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address,address)", [
            manager.address,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, claimABI),
          ).to.revertedWith("user is not pool");
        });

        it("Reverts if claim to is not pool", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
            ],
            [],
          );

          const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address,address)", [
            poolLogicProxy.address,
            manager.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, claimABI),
          ).to.revertedWith("receiver is not pool");
        });

        it("Allows claim", async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              {
                asset: BAL.address,
                isDeposit: false,
              },
            ],
            [],
          );

          const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address,address)", [
            poolLogicProxy.address,
            poolLogicProxy.address,
          ]);
          await poolLogicProxy.connect(manager).execTransaction(wstETH_WETH_STABLE_POOL_GAUGE.address, claimABI);
        });
      });
    });

    describe("withdrawProcessing", () => {
      beforeEach(async () => {
        await stakeLPTokensAndLetTimeFly(FIVE_MINUTES);
      });

      it("Pool has expected funds after withdraw", async () => {
        const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
        const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicProxy.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const gaugeBalanceBefore = await wstETH_WETH_STABLE_POOL_GAUGE.balanceOf(poolLogicProxy.address);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        // includes additional rewards, hence 0.01% delta
        expect(wethBalanceBefore.div(2)).to.be.closeTo(
          await WETH.balanceOf(poolLogicProxy.address),
          wethBalanceBefore.div(2).div(10_000),
        );
        expect(wstETHBalanceBefore.div(2)).to.be.closeTo(
          await wstETH.balanceOf(poolLogicProxy.address),
          wstETHBalanceBefore.div(2).div(10_000),
        );
        expect(totalFundValueBefore.div(2)).to.be.closeTo(
          await poolManagerLogicProxy.totalFundValue(),
          totalFundValueBefore.div(2).div(10_000),
        );
        expect(gaugeBalanceBefore.div(2)).to.be.closeTo(
          await wstETH_WETH_STABLE_POOL_GAUGE.balanceOf(poolLogicProxy.address),
          gaugeBalanceBefore.div(2).div(10_000),
        );
      });

      it("Pool receives expected rewards", async () => {
        await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward_write(poolLogicProxy.address, BAL.address);
        const claimAmount = await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward(poolLogicProxy.address, BAL.address);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        expect(claimAmount.div(2)).to.be.equal(await BAL.balanceOf(poolLogicProxy.address));
      });

      it("Withdrawer receives their portion of Balancer LP Tokens and Rewards", async () => {
        await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward_write(poolLogicProxy.address, BAL.address);
        const claimAmount = await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward(poolLogicProxy.address, BAL.address);

        // withdraw half
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
        expect(BigNumber.from(lpAmount).div(2)).to.be.closeTo(
          await wstETH_WETH_STABLE_POOL.balanceOf(logicOwner.address),
          BigNumber.from(lpAmount).div(2).div(10_000),
        );
        expect(claimAmount.div(2)).to.be.equal(await BAL.balanceOf(logicOwner.address));
      });
    });

    describe("getBalance", () => {
      it("Prices underlying Balancer LP token correctly", async () => {
        const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
        const wstETHBalanceBefore = await wstETH.balanceOf(poolLogicProxy.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await stakeLPTokens();

        expect(await wstETH_WETH_STABLE_POOL.balanceOf(poolLogicProxy.address)).to.be.eq(0);
        expect(await WETH.balanceOf(poolLogicProxy.address)).to.be.eq(wethBalanceBefore);
        expect(await wstETH.balanceOf(poolLogicProxy.address)).to.be.eq(wstETHBalanceBefore);
        expect(await poolManagerLogicProxy.totalFundValue()).to.equal(totalFundValueBefore);
      });

      it("Includes unclaimed rewards in Price", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        await stakeLPTokensAndLetTimeFly(FIVE_MINUTES);

        await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward_write(poolLogicProxy.address, BAL.address);
        const claimAmount = await wstETH_WETH_STABLE_POOL_GAUGE.claimable_reward(poolLogicProxy.address, BAL.address);

        expect(await poolManagerLogicProxy.totalFundValue()).equal(
          totalFundValueBefore.add(
            await poolManagerLogicProxy["assetValue(address,uint256)"](BAL.address, claimAmount),
          ),
        );
      });
    });
  });
});
