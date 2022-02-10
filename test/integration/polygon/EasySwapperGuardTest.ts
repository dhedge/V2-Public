import { Interface } from "@ethersproject/abi";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { assets, assetsBalanceOfSlot, ZERO_ADDRESS } from "../../../config/chainData/polygon-data";
import {
  DhedgeEasySwapper,
  DhedgeEasySwapper__factory,
  IERC20,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic__factory,
} from "../../../types";
import { units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { getAccountToken } from "../utils/getAccountTokens";

const oneDollar = units(1);

describe("EasySwapperGuard", () => {
  let USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic;
  let DhedgeEasySwapperInterface: Interface;
  let dhedgeEasySwapper: DhedgeEasySwapper;
  let torosAssetAddress: string;

  let snapshot: any;
  before(async () => {
    snapshot = await ethers.provider.send("evm_snapshot", []);
    [logicOwner, manager] = await ethers.getSigners();
    DhedgeEasySwapperInterface = await new ethers.utils.Interface(DhedgeEasySwapper__factory.abi);
    USDC = await ethers.getContractAt("IERC20", assets.usdc);

    const deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;
    dhedgeEasySwapper = deployments.dhedgeEasySwapper;

    const torosAsset = await createFund(poolFactory, logicOwner, manager, [{ asset: assets.usdc, isDeposit: true }]);
    torosAssetAddress = torosAsset.poolLogicProxy.address;
    // If the pool is empty than we can't get a price
    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await USDC.approve(torosAssetAddress, units(500, 6));
    await torosAsset.poolLogicProxy.deposit(assets.usdc, units(500, 6));

    await dhedgeEasySwapper.setPoolAllowed(torosAssetAddress, true);

    const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
    const dhedgePoolAggregator = await DHedgePoolAggregator.deploy(torosAssetAddress);
    await dhedgePoolAggregator.deployed();
    deployments.assetHandler.addAsset(torosAssetAddress, 0, dhedgePoolAggregator.address);
  });
  after(async () => {
    await ethers.provider.send("evm_revert", [snapshot]);
  });

  beforeEach(async () => {
    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    // Create a fund that can be used as an asset inside a pool.
    // This simulates a toros pool

    // Create the fund we're going to use for testing
    const fund = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      // Note: we're enabling the torosAsset as an asset of this pool
      { asset: torosAssetAddress, isDeposit: true },
    ]);

    poolLogicProxy = fund.poolLogicProxy;
  });

  it("Manager can use easy swapper deposit and withdraw", async () => {
    // Deposit $1 conventional way
    await USDC.approve(poolLogicProxy.address, units(500, 6));
    await poolLogicProxy.deposit(assets.usdc, units(500, 6));
    // Check token price is $1
    expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(oneDollar, oneDollar.div(100) as any);

    let approveABI = USDC.interface.encodeFunctionData("approve", [dhedgeEasySwapper.address, units(500, 6)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    const depositEncoded = DhedgeEasySwapperInterface.encodeFunctionData("deposit", [
      torosAssetAddress,
      assets.usdc,
      units(500, 6),
      assets.usdc,
      0,
    ]);

    // Deposit via EasySwapper to receive toros Tokens
    await poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, depositEncoded);

    const poolManagerLogicProxy = PoolManagerLogic__factory.connect(
      await poolLogicProxy.poolManagerLogic(),
      logicOwner,
    );
    const torosBalance = await poolManagerLogicProxy.assetBalance(torosAssetAddress);
    expect(torosBalance.gt(0)).to.be.true;

    // Check token price is $1
    expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(oneDollar, oneDollar.div(100) as any);

    let approveTorosABI = USDC.interface.encodeFunctionData("approve", [dhedgeEasySwapper.address, torosBalance]);
    await poolLogicProxy.connect(manager).execTransaction(torosAssetAddress, approveTorosABI);

    const withdrawEncoded = DhedgeEasySwapperInterface.encodeFunctionData("withdraw", [
      torosAssetAddress,
      torosBalance,
      assets.usdc,
      0,
    ]);

    // Withdraw via EasySwapper to receive money
    // EasySwapper has 5 minute lockup
    await ethers.provider.send("evm_increaseTime", [3600]); // 1 hour
    await poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, withdrawEncoded);

    const torosBalanceAfterWithdraw = await poolManagerLogicProxy.assetBalance(torosAssetAddress);
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
    await poolManagerLogicProxy.connect(manager).changeAssets([], [torosAssetAddress]);

    const depositEncoded = DhedgeEasySwapperInterface.encodeFunctionData("deposit", [
      torosAssetAddress,
      assets.usdc,
      units(500, 6),
      assets.usdc,
      0,
    ]);

    // Deposit via EasySwapper to receive toros Tokens
    await expect(
      poolLogicProxy.connect(manager).execTransaction(dhedgeEasySwapper.address, depositEncoded),
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
