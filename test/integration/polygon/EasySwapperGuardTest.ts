import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { polygonChainData } from "../../../config/chainData/polygon-data";
import {
  DhedgeEasySwapper,
  IERC20,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  PoolManagerLogic__factory,
} from "../../../types";
import { units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { utils } from "../utils/utils";

const { assets, assetsBalanceOfSlot, ZERO_ADDRESS } = polygonChainData;

const oneDollar = units(1);

describe("EasySwapperGuard", () => {
  let USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let dhedgeEasySwapper: DhedgeEasySwapper;
  let torosAssetAddress: string;

  let snapId: string;
  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });
  before(async () => {
    snapId = await utils.evmTakeSnap();

    [logicOwner, manager] = await ethers.getSigners();
    USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);

    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    dhedgeEasySwapper = deployments.dhedgeEasySwapper!;

    const pool = await createFund(poolFactory, logicOwner, manager, [{ asset: assets.usdc, isDeposit: true }]);
    torosAssetAddress = pool.poolLogicProxy.address;
    // If the pool is empty than we can't get a price
    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await USDC.approve(torosAssetAddress, units(500, 6));
    await pool.poolLogicProxy.deposit(assets.usdc, units(500, 6));

    await dhedgeEasySwapper.setPoolAllowed(torosAssetAddress, true);

    const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
    const dhedgePoolAggregator = await DHedgePoolAggregator.deploy(torosAssetAddress);
    await dhedgePoolAggregator.deployed();
    deployments.assetHandler.addAsset(torosAssetAddress, 0, dhedgePoolAggregator.address);
  });

  beforeEach(async () => {
    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    // Create a fund that can be used as an asset inside a pool.
    // This simulates a toros pool

    // Create the fund we're going to use for testing
    const fund = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      // Note: we're enabling the pool as an asset of this pool
      { asset: torosAssetAddress, isDeposit: true },
    ]);

    poolLogicProxy = fund.poolLogicProxy;
    poolManagerLogicProxy = fund.poolManagerLogicProxy;
  });

  it("manager cannot use other functions", async () => {
    const setPoolAllowedEncoded = dhedgeEasySwapper.interface.encodeFunctionData("setPoolAllowed", [
      ZERO_ADDRESS,
      true,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction(assets.usdc, setPoolAllowedEncoded),
    ).to.be.revertedWith("invalid transaction");
  });

  describe("Deposit", () => {
    it("Manager can use easy swapper deposit and withdraw", async () => {
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, units(500, 6));
      await poolLogicProxy.deposit(assets.usdc, units(500, 6));
      // Check token price is $1
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(oneDollar, oneDollar.div(100) as any);

      const approveABI = USDC.interface.encodeFunctionData("approve", [dhedgeEasySwapper.address, units(500, 6)]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
      dhedgeEasySwapper;
      const depositEncoded = dhedgeEasySwapper.interface.encodeFunctionData("deposit", [
        torosAssetAddress,
        assets.usdc,
        units(500, 6),
        assets.usdc,
        0,
      ]);

      // Deposit via EasySwapper to receive pool tokens
      await poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, depositEncoded);

      const poolManagerLogicProxy = PoolManagerLogic__factory.connect(
        await poolLogicProxy.poolManagerLogic(),
        logicOwner,
      );
      const torosBalance = await poolManagerLogicProxy.assetBalance(torosAssetAddress);
      expect(torosBalance.gt(0)).to.be.true;

      // Check token price is $1
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(oneDollar, oneDollar.div(100) as any);
    });

    it("manager cannot use deposit if asset is not supported", async () => {
      const poolManagerLogicProxy = PoolManagerLogic__factory.connect(
        await poolLogicProxy.poolManagerLogic(),
        logicOwner,
      );

      // Remove toros pool from supported assets
      await poolManagerLogicProxy.connect(manager).changeAssets([], [torosAssetAddress]);

      const depositEncoded = dhedgeEasySwapper.interface.encodeFunctionData("deposit", [
        torosAssetAddress,
        assets.usdc,
        units(500, 6),
        assets.usdc,
        0,
      ]);

      // Deposit via EasySwapper to receive pool tokens
      await expect(
        poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, depositEncoded),
      ).to.be.revertedWith("unsupported asset");
    });
  });

  describe("Withdraw", () => {
    beforeEach(async () => {
      // Deposit $1 conventional way
      await USDC.approve(poolLogicProxy.address, units(500, 6));
      await poolLogicProxy.deposit(assets.usdc, units(500, 6));
      // Check token price is $1
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(oneDollar, oneDollar.div(100) as any);

      const approveABI = USDC.interface.encodeFunctionData("approve", [dhedgeEasySwapper.address, units(500, 6)]);
      await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

      const depositEncoded = dhedgeEasySwapper.interface.encodeFunctionData("deposit", [
        torosAssetAddress,
        assets.usdc,
        units(500, 6),
        assets.usdc,
        0,
      ]);

      // Deposit via EasySwapper to receive pool tokens
      await poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, depositEncoded);
    });

    describe("withdraw", () => {
      it("can withdraw", async () => {
        const torosBalance = await poolManagerLogicProxy.assetBalance(torosAssetAddress);
        const approveTorosABI = USDC.interface.encodeFunctionData("approve", [dhedgeEasySwapper.address, torosBalance]);
        await poolLogicProxy.connect(manager).execTransaction(torosAssetAddress, approveTorosABI);

        const withdrawEncoded = dhedgeEasySwapper.interface.encodeFunctionData("withdraw", [
          torosAssetAddress,
          torosBalance,
          assets.usdc,
          0,
        ]);

        // Withdraw via EasySwapper to receive money
        // EasySwapper has 5 minute lockup
        await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
        await poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, withdrawEncoded);
      });

      it("manager cannot use withdraw if asset is not supported", async () => {
        const poolManagerLogicProxy = PoolManagerLogic__factory.connect(
          await poolLogicProxy.poolManagerLogic(),
          logicOwner,
        );

        // Remove usdc pool from supported assets
        await poolManagerLogicProxy.connect(manager).changeAssets([], [assets.usdc]);

        const withdrawEncoded = dhedgeEasySwapper.interface.encodeFunctionData("withdraw", [
          torosAssetAddress,
          1,
          assets.usdc,
          0,
        ]);

        // Withdraw via EasySwapper to receive money
        await expect(
          poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, withdrawEncoded),
        ).to.be.revertedWith("unsupported asset");
      });
    });

    describe("withdrawIntermediate", () => {
      it("can withdraw", async () => {
        const torosBalance = await poolManagerLogicProxy.assetBalance(torosAssetAddress);
        const approveTorosABI = USDC.interface.encodeFunctionData("approve", [dhedgeEasySwapper.address, torosBalance]);
        await poolLogicProxy.connect(manager).execTransaction(torosAssetAddress, approveTorosABI);

        const withdrawEncoded = dhedgeEasySwapper.interface.encodeFunctionData("withdrawIntermediate", [
          torosAssetAddress,
          torosBalance,
          assets.usdc, // intermediate
          assets.usdc, // final
          0,
        ]);

        // Withdraw via EasySwapper to receive money
        // EasySwapper has 5 minute lockup
        await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
        await poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, withdrawEncoded);
      });

      it("manager cannot use withdraw if asset is not supported", async () => {
        const poolManagerLogicProxy = PoolManagerLogic__factory.connect(
          await poolLogicProxy.poolManagerLogic(),
          logicOwner,
        );

        // Remove usdc pool from supported assets
        await poolManagerLogicProxy.connect(manager).changeAssets([], [assets.usdc]);

        const withdrawEncoded = dhedgeEasySwapper.interface.encodeFunctionData("withdrawIntermediate", [
          torosAssetAddress,
          1,
          assets.usdc, // intermediate
          assets.usdc, // final
          0,
        ]);

        // Withdraw via EasySwapper to receive money
        await expect(
          poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, withdrawEncoded),
        ).to.be.revertedWith("unsupported asset");
      });
    });

    describe("withdrawSUSD", () => {
      it("manager cannot use withdrawSUSD if asset is not supported", async () => {
        const withdrawEncoded = dhedgeEasySwapper.interface.encodeFunctionData("withdrawSUSD", [
          torosAssetAddress,
          1,
          assets.usdc,
          0,
        ]);

        // Withdraw via EasySwapper to receive money
        await expect(
          poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, withdrawEncoded),
        ).to.be.revertedWith("unsupported asset");
      });
    });
  });
});
