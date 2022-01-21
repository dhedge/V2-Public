import { ethers } from "hardhat";
import { expect } from "chai";
import { units } from "../../TestHelpers";
import {
  assets,
  assetsBalanceOfSlot,
  dhedgeEasySwapperAddress,
  ZERO_ADDRESS,
} from "../../../config/chainData/polygon-data";
import { IERC20, PoolFactory, PoolLogic, PoolManagerLogic__factory, DhedgeEasySwapper__factory } from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { Interface } from "@ethersproject/abi";
import { createFund } from "../utils/createFund";

const oneDollar = units(1);

describe("EasySwapperGuard", () => {
  let USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic;
  let DhedgeEasySwapperInterface: Interface;

  let snapshot: any;
  before(async () => {
    snapshot = await ethers.provider.send("evm_snapshot", []);

    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;
    DhedgeEasySwapperInterface = await new ethers.utils.Interface(DhedgeEasySwapper__factory.abi);
    await poolFactory.setExitCooldown(0);
  });
  after(async () => {
    await ethers.provider.send("evm_revert", [snapshot]);
  });

  beforeEach(async () => {
    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    USDC = await ethers.getContractAt("IERC20", assets.usdc);
    // Create the fund we're going to use for testing
    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      // Note: we're enabling one of the toros pools as an asset
      { asset: assets.ETHBEAR2X, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
  });

  it("Manager can use easy swapper deposit and withdraw", async () => {
    // Deposit $1 conventional way
    await USDC.approve(poolLogicProxy.address, units(500, 6));
    await poolLogicProxy.deposit(assets.usdc, units(500, 6));
    // Check token price is $1
    expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(oneDollar, oneDollar.div(100) as any);

    let approveABI = USDC.interface.encodeFunctionData("approve", [dhedgeEasySwapperAddress, units(500, 6)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    const depositEncoded = DhedgeEasySwapperInterface.encodeFunctionData("deposit", [
      assets.ETHBEAR2X,
      assets.usdc,
      units(500, 6),
      assets.usdc,
      0,
    ]);

    // Deposit via EasySwapper to receive toros Tokens
    await poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapperAddress, depositEncoded);

    const poolManagerLogicProxy = PoolManagerLogic__factory.connect(
      await poolLogicProxy.poolManagerLogic(),
      logicOwner,
    );
    const torosBalance = await poolManagerLogicProxy.assetBalance(assets.ETHBEAR2X);
    expect(torosBalance.gt(0)).to.be.true;

    // Check token price is $1
    expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(oneDollar, oneDollar.div(100) as any);

    let approveTorosABI = USDC.interface.encodeFunctionData("approve", [dhedgeEasySwapperAddress, torosBalance]);
    await poolLogicProxy.connect(manager).execTransaction(assets.ETHBEAR2X, approveTorosABI);

    const withdrawEncoded = DhedgeEasySwapperInterface.encodeFunctionData("withdraw", [
      assets.ETHBEAR2X,
      torosBalance,
      assets.usdc,
      0,
    ]);

    // Withdraw via EasySwapper to receive money
    // EasySwapper has 5 minute lockup
    await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
    await poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapperAddress, withdrawEncoded);

    const torosBalanceAfterWithdraw = await poolManagerLogicProxy.assetBalance(assets.ETHBEAR2X);
    expect(torosBalanceAfterWithdraw).to.equal(0);

    // Check token price is 98c to $1.02
    expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(oneDollar, oneDollar.div(50) as any);
  });

  it("manager cannot use other functions", async () => {
    const setPoolAllowedEncoded = DhedgeEasySwapperInterface.encodeFunctionData("setPoolAllowed", [ZERO_ADDRESS, true]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction(assets.usdc, setPoolAllowedEncoded),
    ).to.be.revertedWith("invalid transaction");
  });

  it("manager cannot use deposit if asset is not supported", async () => {
    const poolManagerLogicProxy = PoolManagerLogic__factory.connect(
      await poolLogicProxy.poolManagerLogic(),
      logicOwner,
    );

    // Remove toros pool from supported assets
    await poolManagerLogicProxy.connect(manager).changeAssets([], [assets.ETHBEAR2X]);

    const depositEncoded = DhedgeEasySwapperInterface.encodeFunctionData("deposit", [
      assets.ETHBEAR2X,
      assets.usdc,
      units(500, 6),
      assets.usdc,
      0,
    ]);

    // Deposit via EasySwapper to receive toros Tokens
    await expect(
      poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapperAddress, depositEncoded),
    ).to.be.revertedWith("unsupported asset");
  });

  it("manager cannot use withdraw if asset is not supported", async () => {
    const poolManagerLogicProxy = PoolManagerLogic__factory.connect(
      await poolLogicProxy.poolManagerLogic(),
      logicOwner,
    );

    // Remove toros pool from supported assets
    await poolManagerLogicProxy.connect(manager).changeAssets([], [assets.usdc]);

    const withdrawEncoded = DhedgeEasySwapperInterface.encodeFunctionData("withdraw", [
      assets.ETHBEAR2X,
      1,
      assets.usdc,
      0,
    ]);

    // Withdraw via EasySwapper to receive money
    await expect(
      poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapperAddress, withdrawEncoded),
    ).to.be.revertedWith("unsupported asset");
  });
});
