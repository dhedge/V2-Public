import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { polygonChainData } from "../../../../config/chainData/polygon-data";
import {
  IBalancerV2Vault__factory,
  IERC20,
  IERC20__factory,
  IRewardsOnlyGauge,
  IRewardsOnlyGauge__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { checkAlmostSame, units } from "../../../TestHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { getAccountToken } from "../../utils/getAccountTokens";
import { utils } from "../../utils/utils";
const { assets, assetsBalanceOfSlot, balancer } = polygonChainData;

describe("Balancer V2 Gauge Asset Guard Test", function () {
  let WMATIC: IERC20, STMATIC: IERC20, BALANCER_STMATIC: IERC20, BALANCER: IERC20;
  let stGauge: IRewardsOnlyGauge;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let lpAmount;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault__factory.abi);
  const iRewardsOnlyGauge = new ethers.utils.Interface(IRewardsOnlyGauge__factory.abi);

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    await poolFactory.setExitCooldown(0);

    WMATIC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.wmatic);
    STMATIC = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.stMatic)
    );
    BALANCER_STMATIC = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        balancer.gaugePools.stMATIC.pool,
      )
    );
    BALANCER = <IERC20>(
      await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.balancer)
    );
    stGauge = await ethers.getContractAt("IRewardsOnlyGauge", balancer.gaugePools.stMATIC.gauge);

    await getAccountToken(units(10000), logicOwner.address, assets.wmatic, assetsBalanceOfSlot.wmatic);
    await getAccountToken(units(10000), logicOwner.address, assets.stMatic, assetsBalanceOfSlot.stMatic);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.wmatic, isDeposit: true },
      { asset: balancer.gaugePools.stMATIC.pool, isDeposit: false },
      { asset: assets.stMatic, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    // Deposit 200 WMATIC
    await WMATIC.approve(poolLogicProxy.address, units(200));
    await poolLogicProxy.deposit(assets.wmatic, units(200));
    // Deposit 200 STMATIC
    await STMATIC.approve(poolLogicProxy.address, units(200));
    await poolLogicProxy.deposit(assets.stMatic, units(200));

    let approveABI = iERC20.encodeFunctionData("approve", [balancer.v2Vault, units(200)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.wmatic, approveABI);
    await poolLogicProxy.connect(manager).execTransaction(assets.stMatic, approveABI);

    const joinTx = iBalancerV2Vault.encodeFunctionData("joinPool", [
      "0xaf5e0b5425de1f5a630a8cb5aa9d97b8141c908d000200000000000000000366", // poolId
      poolLogicProxy.address,
      poolLogicProxy.address,
      [
        [assets.wmatic, assets.stMatic],
        [units(100), units(100)],
        ethers.utils.defaultAbiCoder.encode(["uint256", "uint256[]", "uint256"], [1, [units(100), units(100)], 1]),
        false,
      ],
    ]);
    await poolLogicProxy.connect(manager).execTransaction(balancer.v2Vault, joinTx);

    lpAmount = await BALANCER_STMATIC.balanceOf(poolLogicProxy.address);

    approveABI = iERC20.encodeFunctionData("approve", [balancer.gaugePools.stMATIC.gauge, lpAmount]);
    await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.pool, approveABI);
  });

  let snapId: string;
  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();
  });

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  describe("withdrawProcessing", () => {
    beforeEach(async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false },
          {
            asset: assets.balancer,
            isDeposit: false,
          },
        ],
        [],
      );
      const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI);

      await ethers.provider.send("evm_increaseTime", [60 * 5]);
      await ethers.provider.send("evm_mine", []);
    });

    it("Pool has expected funds after withdraw", async () => {
      const wmaticBalanceBefore = await WMATIC.balanceOf(poolLogicProxy.address);
      const stmaticBalanceBefore = await STMATIC.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const gaugeBalanceBefore = await stGauge.balanceOf(poolLogicProxy.address);

      // withdraw half
      await poolFactory.setExitCooldown(0);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      checkAlmostSame(await WMATIC.balanceOf(poolLogicProxy.address), wmaticBalanceBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
      checkAlmostSame(await STMATIC.balanceOf(poolLogicProxy.address), stmaticBalanceBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
      checkAlmostSame(await stGauge.balanceOf(poolLogicProxy.address), gaugeBalanceBefore.div(2), 0.05); // includes additional rewards, hence 0.05% threshold
    });

    it("Pool receives expected rewards", async () => {
      await stGauge.claimable_reward_write(poolLogicProxy.address, assets.balancer);
      const claimAmount = await stGauge.claimable_reward(poolLogicProxy.address, assets.balancer);

      // withdraw half
      await poolFactory.setExitCooldown(0);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      checkAlmostSame(await BALANCER.balanceOf(poolLogicProxy.address), claimAmount.div(2), 0.05);
    });

    it("Withdrawer receives their portion of Balancer LP Tokens and Rewards", async () => {
      await stGauge.claimable_reward_write(poolLogicProxy.address, assets.balancer);
      const claimAmount = await stGauge.claimable_reward(poolLogicProxy.address, assets.balancer);

      // withdraw half
      await poolFactory.setExitCooldown(0);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));
      checkAlmostSame(await BALANCER_STMATIC.balanceOf(logicOwner.address), lpAmount.div(2), 0.05);
      checkAlmostSame(await BALANCER.balanceOf(logicOwner.address), claimAmount.div(2), 0.05);
    });
  });

  describe("getBalance", () => {
    it("Prices underlying Balancer LP token correctly", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false },
          {
            asset: assets.balancer,
            isDeposit: false,
          },
        ],
        [],
      );

      const wmaticBalanceBefore = await WMATIC.balanceOf(poolLogicProxy.address);
      const stmaticBalanceBefore = await STMATIC.balanceOf(poolLogicProxy.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI);

      expect(await BALANCER_STMATIC.balanceOf(poolLogicProxy.address)).to.be.eq(0);
      expect(await WMATIC.balanceOf(poolLogicProxy.address)).to.be.eq(wmaticBalanceBefore);
      expect(await STMATIC.balanceOf(poolLogicProxy.address)).to.be.eq(stmaticBalanceBefore);
      expect(await poolManagerLogicProxy.totalFundValue()).to.equal(totalFundValueBefore);
    });

    it("Includes unclaimed rewards in Price", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false },
          {
            asset: assets.balancer,
            isDeposit: false,
          },
        ],
        [],
      );
      const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await ethers.provider.send("evm_increaseTime", [60 * 5]);
      await ethers.provider.send("evm_mine", []);

      await stGauge.claimable_reward_write(poolLogicProxy.address, assets.balancer);
      const claimAmount = await stGauge.claimable_reward(poolLogicProxy.address, assets.balancer);

      expect(await poolManagerLogicProxy.totalFundValue()).equal(
        totalFundValueBefore.add(
          await poolManagerLogicProxy["assetValue(address,uint256)"](assets.balancer, claimAmount),
        ),
      );
    });
  });
});
