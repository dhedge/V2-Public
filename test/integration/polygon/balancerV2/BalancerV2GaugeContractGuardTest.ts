import { ethers } from "hardhat";
import { expect } from "chai";
import { units } from "../../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
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
import { createFund } from "../../utils/createFund";
import { polygonChainData } from "../../../../config/chainData/polygonData";
const { assets, assetsBalanceOfSlot, balancer } = polygonChainData;
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";

describe("Balancer V2 Gauge Contract Guard Test", function () {
  let WMATIC: IERC20, STMATIC: IERC20, BALANCER_STMATIC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, userNotPool: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let lpAmount;
  let stGauge: IRewardsOnlyGauge;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iBalancerV2Vault = new ethers.utils.Interface(IBalancerV2Vault__factory.abi);
  const iRewardsOnlyGauge = new ethers.utils.Interface(IRewardsOnlyGauge__factory.abi);

  before(async function () {
    [logicOwner, manager, userNotPool] = await ethers.getSigners();
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

  describe("deposit", () => {
    describe("deposit(uint256)", () => {
      it("Reverts if gauge asset is not enabled", async () => {
        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI),
        ).to.revertedWith("enable gauge token");
      });

      it("Reverts if gauge reward tokens are not enabled", async () => {
        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false }], []);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI),
        ).to.revertedWith("enable reward token");
      });

      it("Allow deposit", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
            { asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false },
          ],
          [],
        );

        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI);
      });
    });

    describe("deposit(uint256,address)", () => {
      it("Reverts if receiver is not pool", async () => {
        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address)", [
          lpAmount,
          userNotPool.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI),
        ).to.revertedWith("user is not pool");
      });

      it("Reverts if gauge asset is not enabled", async () => {
        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address)", [
          lpAmount,
          poolLogicProxy.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI),
        ).to.revertedWith("enable gauge token");
      });

      it("Reverts if gauge reward tokens are not enabled", async () => {
        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address)", [
          lpAmount,
          poolLogicProxy.address,
        ]);
        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false }], []);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI),
        ).to.revertedWith("enable reward token");
      });

      it("Allow deposit", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
            { asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false },
          ],
          [],
        );

        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address)", [
          lpAmount,
          poolLogicProxy.address,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI);
      });
    });

    describe("deposit(uint256,address,bool)", () => {
      it("Reverts if receiver is not pool", async () => {
        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address,bool)", [
          lpAmount,
          userNotPool.address,
          true,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI),
        ).to.revertedWith("user is not pool");
      });

      it("Reverts if gauge asset is not enabled", async () => {
        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address,bool)", [
          lpAmount,
          poolLogicProxy.address,
          true,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI),
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
          .changeAssets([{ asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false }], []);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI),
        ).to.revertedWith("enable reward token");
      });

      it("Allow deposit", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
            { asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false },
          ],
          [],
        );

        const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256,address,bool)", [
          lpAmount,
          poolLogicProxy.address,
          true,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI);
      });
    });
  });

  describe("withdraw", () => {
    beforeEach(async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: assets.balancer,
            isDeposit: false,
          },
          { asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false },
        ],
        [],
      );
      const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI);

      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([], [assets.balancer, balancer.gaugePools.stMATIC.pool]);

      await ethers.provider.send("evm_increaseTime", [60 * 5]);
      await ethers.provider.send("evm_mine", []);
    });

    describe("withdraw(uint256)", () => {
      it("Reverts if underlying balancer lp token is not enabled", async () => {
        const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256)", [lpAmount]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, withdrawABI),
        ).to.revertedWith("enable lp token");
      });

      it("Allows withdraw", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
            {
              asset: balancer.gaugePools.stMATIC.pool,
              isDeposit: false,
            },
          ],
          [],
        );

        const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256)", [lpAmount]);
        await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, withdrawABI);
      });
    });

    describe("withdraw(uint256,bool)", () => {
      it("Reverts if underlying balancer lp token is not enabled", async () => {
        const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256,bool)", [lpAmount, true]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, withdrawABI),
        ).to.revertedWith("enable lp token");
      });

      it("Reverts if claim is true and reward tokens are not enabled", async () => {
        const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256,bool)", [lpAmount, true]);
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: balancer.gaugePools.stMATIC.pool,
              isDeposit: false,
            },
          ],
          [],
        );
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, withdrawABI),
        ).to.revertedWith("enable reward token");
      });

      it("Allows withdraw", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
            {
              asset: balancer.gaugePools.stMATIC.pool,
              isDeposit: false,
            },
          ],
          [],
        );

        const withdrawABI = iRewardsOnlyGauge.encodeFunctionData("withdraw(uint256,bool)", [lpAmount, true]);
        await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, withdrawABI);
      });
    });
  });

  describe("claim", () => {
    beforeEach(async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: assets.balancer,
            isDeposit: false,
          },
          { asset: balancer.gaugePools.stMATIC.gauge, isDeposit: false },
        ],
        [],
      );

      const depositABI = iRewardsOnlyGauge.encodeFunctionData("deposit(uint256)", [lpAmount]);
      await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, depositABI);

      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([], [assets.balancer, balancer.gaugePools.stMATIC.pool]);

      await ethers.provider.send("evm_increaseTime", [60 * 5]);
      await ethers.provider.send("evm_mine", []);

      await stGauge.claimable_reward_write(poolLogicProxy.address, assets.balancer);
    });

    describe("claim_rewards()", () => {
      it("Reverts if rewards tokens are not enabled", async function () {
        if ((await stGauge.claimable_reward(poolLogicProxy.address, assets.balancer)).eq(0)) {
          console.log("Skipping... no rewards available");
          this.skip();
        } else {
          const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards()", []);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, claimABI),
          ).to.revertedWith("enable reward token");
        }
      });

      it("Allows claim", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
          ],
          [],
        );
        const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards()", []);
        await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, claimABI);
      });
    });

    describe("claim_rewards(address) - claim for", () => {
      it("Reverts if rewards tokens are not enabled", async function () {
        if ((await stGauge.claimable_reward(poolLogicProxy.address, assets.balancer)).eq(0)) {
          console.log("Skipping... no rewards available");
          this.skip();
        } else {
          const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address)", [poolLogicProxy.address]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, claimABI),
          ).to.revertedWith("enable reward token");
        }
      });

      it("Reverts if claim for is not pool", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
          ],
          [],
        );
        const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address)", [userNotPool.address]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, claimABI),
        ).to.revertedWith("user is not pool");
      });

      it("Allows claim", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
          ],
          [],
        );
        const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address)", [poolLogicProxy.address]);
        await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, claimABI);
      });
    });

    describe("claim_rewards(address,address) - claim for, claim to", () => {
      it("Reverts if rewards tokens are not enabled", async function () {
        if ((await stGauge.claimable_reward(poolLogicProxy.address, assets.balancer)).eq(0)) {
          console.log("Skipping... no rewards available");
          this.skip();
        } else {
          const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address,address)", [
            poolLogicProxy.address,
            poolLogicProxy.address,
          ]);
          await expect(
            poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, claimABI),
          ).to.revertedWith("enable reward token");
        }
      });

      it("Reverts if claim for is not pool", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
          ],
          [],
        );

        const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address,address)", [
          userNotPool.address,
          poolLogicProxy.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, claimABI),
        ).to.revertedWith("user is not pool");
      });

      it("Reverts if claim to is not pool", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
          ],
          [],
        );

        const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address,address)", [
          poolLogicProxy.address,
          userNotPool.address,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, claimABI),
        ).to.revertedWith("receiver is not pool");
      });

      it("Allows claim", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: assets.balancer,
              isDeposit: false,
            },
          ],
          [],
        );

        const claimABI = iRewardsOnlyGauge.encodeFunctionData("claim_rewards(address,address)", [
          poolLogicProxy.address,
          poolLogicProxy.address,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(balancer.gaugePools.stMATIC.gauge, claimABI);
      });
    });
  });
});
