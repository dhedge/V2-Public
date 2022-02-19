import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { Wallet } from "ethers";
import {} from "@nomiclabs/hardhat-ethers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { describe, it } from "mocha";
import { assets, assetsBalanceOfSlot, uniswapV3 } from "../../../config/chainData/polygon-data";
import {
  IERC20__factory,
  INonfungiblePositionManager,
  INonfungiblePositionManager__factory,
  PoolFactory,
  PoolLogic,
} from "../../../types";
import { units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { IDeployments } from "../utils/deployContracts";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { getAccountToken } from "../utils/getAccountTokens";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager__factory.abi);
const deadLine = Math.floor(Date.now() / 1000 + 100000000);

const mintAsUser = async (nonfungiblePositionManager: INonfungiblePositionManager, user: Wallet) => {
  await getAccountToken(units(1), user.address, assets.weth, assetsBalanceOfSlot.weth);
  await getAccountToken(units(2000, 6), user.address, assets.usdc, assetsBalanceOfSlot.usdc);
  // Approve nft manager to take tokens
  const usdcContract = await await ethers.getContractAt("IERC20", assets.usdc);
  await usdcContract.connect(user).approve(uniswapV3.nonfungiblePositionManager, units(2000, 6).div(2));
  const wethContract = await ethers.getContractAt("IERC20", assets.weth);
  await wethContract.connect(user).approve(uniswapV3.nonfungiblePositionManager, units(1).div(2));
  // Minting a half position here relative to the positions
  await nonfungiblePositionManager.connect(user).mint({
    token0: assets.usdc,
    token1: assets.weth,
    fee: 10000,
    tickLower: -414400,
    tickUpper: -253200,
    amount0Desired: units(2000, 6).div(2),
    amount1Desired: units(1).div(2),
    amount0Min: 0,
    amount1Min: 0,
    recipient: user.address,
    deadline: deadLine,
  });
};

const mintUnsupportedLpAsUser = async (nonfungiblePositionManager: INonfungiblePositionManager, user: Wallet) => {
  // These assets have to be assets the AssetHandler does not have price feeds for
  const fraxAddress = "0x45c32fA6DF82ead1e2EF74d17b76547EDdFaFF89";
  const miMaticAddress = "0xa3Fa99A148fA48D14Ed51d610c367C61876997F1";

  await getAccountToken(units(1, 6), user.address, fraxAddress, 0);
  await getAccountToken(units(1, 6), user.address, miMaticAddress, 0);
  // Approve nft manager to take tokens
  const fraxContract = await await ethers.getContractAt("IERC20", fraxAddress);
  await fraxContract.connect(user).approve(uniswapV3.nonfungiblePositionManager, units(1, 6));
  const mimaticContract = await ethers.getContractAt("IERC20", miMaticAddress);
  await mimaticContract.connect(user).approve(uniswapV3.nonfungiblePositionManager, units(1, 6));

  await nonfungiblePositionManager.connect(user).mint({
    token0: fraxAddress,
    token1: miMaticAddress,
    fee: 500,
    tickLower: 276310,
    tickUpper: 276330,
    amount0Desired: units(1, 6),
    amount1Desired: units(1, 6),
    amount0Min: 0,
    amount1Min: 0,
    recipient: user.address,
    deadline: deadLine,
  });
};

const mintAsPool = async (poolLogicProxy: PoolLogic, manager: SignerWithAddress) => {
  let approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(2000, 6)]);
  await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(1)]);
  await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

  let mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
    [
      assets.usdc,
      assets.weth,
      10000,
      -414400,
      -253200,
      units(2000, 6),
      units(1),
      0,
      0,
      poolLogicProxy.address,
      deadLine,
    ],
  ]);

  await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, mintABI);
};

describe("UniswapV3AssetGuardTest", function () {
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic;
  let nonfungiblePositionManager: INonfungiblePositionManager;
  let deployments: IDeployments;
  let user: Wallet;

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();

    nonfungiblePositionManager = await ethers.getContractAt(
      "INonfungiblePositionManager",
      uniswapV3.nonfungiblePositionManager,
    );

    deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;

    await getAccountToken(units(6), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
    await getAccountToken(units(12000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
  });
  s;

  beforeEach(async function () {
    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
      { asset: uniswapV3.nonfungiblePositionManager, isDeposit: false },
    ]);
    poolLogicProxy = funds.poolLogicProxy;

    await deployments.assets.USDC.approve(poolLogicProxy.address, units(6000, 6));
    await poolLogicProxy.deposit(assets.usdc, units(6000, 6));
    await deployments.assets.WETH.approve(poolLogicProxy.address, units(3));
    await poolLogicProxy.deposit(assets.weth, units(3));

    // We don't use a getSigners() signer here because they're shared across all integration tests
    user = ethers.Wallet.createRandom().connect(ethers.provider);
    await logicOwner.sendTransaction({
      to: user.address,
      value: ethers.utils.parseEther("1"),
    });
  });

  // What we want to test here is if a nft position gets transferred directly
  // to a pool that we only count the first three that the pool mints
  // not matter what order they are created.
  describe("Ensure balance is calculated for first three LP positions", () => {
    it("User mints, manager mints 3x, User direct transfer", async () => {
      // Setup
      await mintAsUser(nonfungiblePositionManager, user);
      await mintAsPool(poolLogicProxy, manager);
      await mintAsPool(poolLogicProxy, manager);
      await mintAsPool(poolLogicProxy, manager);

      // Act
      const tokenPriceBefore = await poolLogicProxy.tokenPrice();
      const v3AssetValueBefore = await deployments.uniV3AssetGuard.getBalance(
        poolLogicProxy.address,
        nonfungiblePositionManager.address,
      );
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(user.address, 0);
      await nonfungiblePositionManager.connect(user).transferFrom(user.address, poolLogicProxy.address, tokenId);
      const v3AssetValueAfter = await deployments.uniV3AssetGuard.getBalance(
        poolLogicProxy.address,
        nonfungiblePositionManager.address,
      );

      // Assert
      expect(v3AssetValueBefore.gt(0)).to.be.true;
      expect(v3AssetValueBefore.eq(v3AssetValueAfter)).to.be.true;
      expect(await nonfungiblePositionManager.balanceOf(user.address)).to.equal(0);
      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(4);
      expect(await poolLogicProxy.tokenPrice()).to.equal(tokenPriceBefore);
    });

    it("Manager mints 3x, User mints, User direct transfer", async () => {
      // Setup
      await mintAsPool(poolLogicProxy, manager);
      await mintAsPool(poolLogicProxy, manager);
      await mintAsPool(poolLogicProxy, manager);
      await mintAsUser(nonfungiblePositionManager, user);
      // Act
      const tokenPriceBefore = await poolLogicProxy.tokenPrice();
      const v3AssetValueBefore = await deployments.uniV3AssetGuard.getBalance(
        poolLogicProxy.address,
        nonfungiblePositionManager.address,
      );
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(user.address, 0);
      await nonfungiblePositionManager.connect(user).transferFrom(user.address, poolLogicProxy.address, tokenId);
      const v3AssetValueAfter = await deployments.uniV3AssetGuard.getBalance(
        poolLogicProxy.address,
        nonfungiblePositionManager.address,
      );

      // Assert
      expect(v3AssetValueBefore.gt(0)).to.be.true;
      expect(v3AssetValueBefore.eq(v3AssetValueAfter)).to.be.true;
      expect(await nonfungiblePositionManager.balanceOf(user.address)).to.equal(0);
      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(4);
      expect(await poolLogicProxy.tokenPrice()).to.equal(tokenPriceBefore);
    });
  });

  describe("Unsuppored Assets", () => {
    // Where ensuring that the transfer of a lp with unsupported assets does not break tokenPrice/withdraw
    it("cannot break tokenPrice or withdraw", async () => {
      // Setup
      await mintUnsupportedLpAsUser(nonfungiblePositionManager, user);

      // Act
      const tokenPriceBefore = await poolLogicProxy.tokenPrice();
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(user.address, 0);
      await nonfungiblePositionManager.connect(user).transferFrom(user.address, poolLogicProxy.address, tokenId);

      // Assert
      expect(await nonfungiblePositionManager.balanceOf(user.address)).to.equal(0);
      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(1);
      expect(await poolLogicProxy.tokenPrice()).to.equal(tokenPriceBefore);
      // Can withdraw
      await poolFactory.setExitCooldown(0);
      await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));
    });
  });
});
