import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { units } from "../../../TestHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  IERC20,
  IERC20__factory,
  IVelodromeGauge__factory,
  IVelodromeRouter__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { ovmChainData } from "../../../../config/chainData/ovm-data";
const { assets, assetsBalanceOfSlot, velodrome } = ovmChainData;
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";

use(solidity);

describe("VelodromeGaugeContractGuard Test", function () {
  let USDC: IERC20, DAI: IERC20, VELO: IERC20, VELODROME_USDC_DAI: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, userNotPool: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let lpAmount;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iVelodromeRouter = new ethers.utils.Interface(IVelodromeRouter__factory.abi);
  const iVelodromeGauge = new ethers.utils.Interface(IVelodromeGauge__factory.abi);

  before(async function () {
    [logicOwner, manager, userNotPool] = await ethers.getSigners();
    const deployments = await deployContracts("ovm");
    poolFactory = deployments.poolFactory;

    USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);
    DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
    VELO = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", velodrome.velo);
    VELODROME_USDC_DAI = <IERC20>(
      await ethers.getContractAt(
        "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
        velodrome.STABLE_USDC_DAI.poolAddress,
      )
    );

    await getAccountToken(units(10000), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await getAccountToken(units(10000), logicOwner.address, assets.dai, assetsBalanceOfSlot.dai);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.dai, isDeposit: true },
      { asset: velodrome.STABLE_USDC_DAI.poolAddress, isDeposit: false },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    // Deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, units(200, 6));
    await poolLogicProxy.deposit(assets.usdc, units(200, 6));
    // Deposit 200 DAI
    await DAI.approve(poolLogicProxy.address, units(200));
    await poolLogicProxy.deposit(assets.dai, units(200));

    let approveABI = iERC20.encodeFunctionData("approve", [velodrome.router, units(200, 6)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    approveABI = iERC20.encodeFunctionData("approve", [velodrome.router, units(200)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);

    const addLiquidityTx = iVelodromeRouter.encodeFunctionData("addLiquidity", [
      assets.usdc,
      assets.dai,
      velodrome.STABLE_USDC_DAI.isStable,
      units(100, 6),
      units(100),
      0,
      0,
      poolLogicProxy.address,
      ethers.constants.MaxUint256,
    ]);
    await poolLogicProxy.connect(manager).execTransaction(velodrome.router, addLiquidityTx);

    lpAmount = await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address);

    approveABI = iERC20.encodeFunctionData("approve", [velodrome.STABLE_USDC_DAI.gaugeAddress, lpAmount]);
    await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.poolAddress, approveABI);
  });

  let snapId: string;
  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();
  });

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  describe("deposit", () => {
    it("Reverts if lp asset is not supported", async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(velodrome.VARIABLE_WETH_USDC.gaugeAddress, depositTx),
      ).to.revertedWith("unsupported lp asset");
    });

    it("Allow deposit", async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);

      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, depositTx);

      expect(await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address)).to.equal(0);
    });
  });

  describe("depositAll", () => {
    it("Reverts if lp asset is not supported", async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("depositAll", [0]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(velodrome.VARIABLE_WETH_USDC.gaugeAddress, depositTx),
      ).to.revertedWith("unsupported lp asset");
    });

    it("Allow deposit", async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("depositAll", [0]);

      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, depositTx);

      expect(await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address)).to.equal(0);
    });
  });

  describe("withdraw", () => {
    beforeEach(async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, depositTx);
    });

    it("Reverts if lp asset is not supported", async () => {
      const withdrawTx = iVelodromeGauge.encodeFunctionData("withdraw", [lpAmount]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(velodrome.VARIABLE_WETH_USDC.gaugeAddress, withdrawTx),
      ).to.revertedWith("unsupported lp asset");
    });

    it("Allow withdraw", async () => {
      const withdrawTx = iVelodromeGauge.encodeFunctionData("withdraw", [lpAmount]);

      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, withdrawTx);

      expect(await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address)).to.equal(lpAmount);
    });
  });

  describe("withdrawAll", () => {
    beforeEach(async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, depositTx);
    });

    it("Reverts if lp asset is not supported", async () => {
      const withdrawTx = iVelodromeGauge.encodeFunctionData("withdrawAll", []);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(velodrome.VARIABLE_WETH_USDC.gaugeAddress, withdrawTx),
      ).to.revertedWith("unsupported lp asset");
    });

    it("Allow withdraw", async () => {
      const withdrawTx = iVelodromeGauge.encodeFunctionData("withdrawAll", []);

      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, withdrawTx);

      expect(await VELODROME_USDC_DAI.balanceOf(poolLogicProxy.address)).to.equal(lpAmount);
    });
  });

  describe("getReward", () => {
    beforeEach(async () => {
      const depositTx = iVelodromeGauge.encodeFunctionData("deposit", [lpAmount, 0]);
      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, depositTx);

      // increase time by 1 day
      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine", []);
    });

    it("Reverts if reward token is not supported", async () => {
      const claimTx = iVelodromeGauge.encodeFunctionData("getReward", [poolLogicProxy.address, [velodrome.velo]]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(velodrome.VARIABLE_WETH_USDC.gaugeAddress, claimTx),
      ).to.revertedWith("unsupported reward token");
    });

    it("Reverts if invalid claimer", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: velodrome.velo,
            isDeposit: false,
          },
        ],
        [],
      );

      const claimTx = iVelodromeGauge.encodeFunctionData("getReward", [userNotPool.address, [velodrome.velo]]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, claimTx),
      ).to.revertedWith("invalid claimer");
    });

    it("Allow claim", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: velodrome.velo,
            isDeposit: false,
          },
        ],
        [],
      );

      const claimTx = iVelodromeGauge.encodeFunctionData("getReward", [poolLogicProxy.address, [velodrome.velo]]);

      await poolLogicProxy.connect(manager).execTransaction(velodrome.STABLE_USDC_DAI.gaugeAddress, claimTx);

      expect(await VELO.balanceOf(poolLogicProxy.address)).to.gt(0);
    });
  });
});
