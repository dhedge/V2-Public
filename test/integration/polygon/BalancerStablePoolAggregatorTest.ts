import { ethers } from "hardhat";
import { expect } from "chai";

import { units } from "../../TestHelpers";
import { polygonChainData } from "../../../config/chainData/polygon-data";
const { balancer, assets, assetsBalanceOfSlot } = polygonChainData;

import { IBalancerV2Vault__factory, IERC20__factory, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../types";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { utils } from "../utils/utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../utils/createFund";
import { approveToken, getAccountToken } from "../utils/getAccountTokens";

describe("Balancer Stable Pool Aggregator Test", function () {
  const usdcAmount = units(200, 6);
  const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault__factory.abi);
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let snapId: string;

  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    snapId = await utils.evmTakeSnap();
    poolFactory = deployments.poolFactory;
    const fund = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.dai, isDeposit: true },
      { asset: assets.miMatic, isDeposit: true },
      { asset: assets.usdt, isDeposit: true },
      { asset: balancer.stablePools.BPSP, isDeposit: false },
    ]);

    poolLogicProxy = fund.poolLogicProxy;
    poolManagerLogicProxy = fund.poolManagerLogicProxy;

    await getAccountToken(usdcAmount, logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await approveToken(logicOwner, poolLogicProxy.address, assets.usdc, usdcAmount);
    await poolLogicProxy.deposit(assets.usdc, usdcAmount);
    // Dai
    await getAccountToken(usdcAmount, logicOwner.address, assets.dai, assetsBalanceOfSlot.dai);
    await approveToken(logicOwner, poolLogicProxy.address, assets.dai, usdcAmount);
    await poolLogicProxy.deposit(assets.dai, usdcAmount);
    // miMatic
    await getAccountToken(usdcAmount, logicOwner.address, assets.miMatic, assetsBalanceOfSlot.miMatic);
    await approveToken(logicOwner, poolLogicProxy.address, assets.miMatic, usdcAmount);
    await poolLogicProxy.deposit(assets.miMatic, usdcAmount);
    // usdt
    await getAccountToken(usdcAmount, logicOwner.address, assets.usdt, assetsBalanceOfSlot.usdt);
    await approveToken(logicOwner, poolLogicProxy.address, assets.usdt, usdcAmount);
    await poolLogicProxy.deposit(assets.usdt, usdcAmount);
  });

  it("Stable Pool - USDC, TUSD, DAI, USDT", async function () {
    // We LP all the assets so we don't pay the join swap fee
    const balancerPool = await ethers.getContractAt("IBalancerPool", balancer.stablePools.BPSP);
    const poolId = await balancerPool.getPoolId();
    const assetsArray = [assets.usdc, assets.dai, assets.miMatic, assets.usdt];
    const maxAmountsIn = [usdcAmount, usdcAmount, usdcAmount, usdcAmount];

    const joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      poolId,
      poolLogicProxy.address,
      poolLogicProxy.address,
      [
        assetsArray,
        maxAmountsIn,
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, maxAmountsIn, 1]),
        false,
      ],
    ]);
    const approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, usdcAmount]);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);
    await poolLogicProxy.connect(manager).execTransaction(assets.miMatic, approveABI);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdt, approveABI);
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx);
    // Check the fund is still worth $200
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    // All value is in the balancer pool
    expect(await poolManagerLogicProxy["assetValue(address)"](balancer.stablePools.BPSP)).to.be.equal(
      totalFundValueAfter,
    );
    // 1%
    expect(totalFundValueAfter).to.be.closeTo(totalFundValueBefore, totalFundValueBefore.div(100));
  });
});
