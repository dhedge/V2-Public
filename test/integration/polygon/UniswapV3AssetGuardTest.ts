import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import type { Wallet } from "ethers";
import {} from "@nomiclabs/hardhat-ethers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { describe, it } from "mocha";

import { assets, assetsBalanceOfSlot, uniswapV3 } from "../../../config/chainData/polygon-data";
import { INonfungiblePositionManager, PoolFactory, PoolLogic, AssetHandler } from "../../../types";
import { units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { IDeployments } from "../utils/deployContracts";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { utils } from "../utils/utils";
import { getCurrentTick, mintLpAsPool, mintLpAsUser, UniV3LpMintSettings } from "../utils/uniswapv3Utils";

describe("UniswapV3AssetGuardTest", function () {
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, assetHandler: AssetHandler;
  let nonfungiblePositionManager: INonfungiblePositionManager;
  let deployments: IDeployments;
  let user: Wallet;
  let snapId: string;

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();

    nonfungiblePositionManager = await ethers.getContractAt(
      "INonfungiblePositionManager",
      uniswapV3.nonfungiblePositionManager,
    );

    deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;
    assetHandler = deployments.assetHandler;

    await getAccountToken(units(9), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
    await getAccountToken(units(18000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
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

  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();
  });

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  // What we want to test here is if a nft position gets transferred directly
  // to a pool that we only count the first three that the pool mints
  // not matter what order they are created.
  describe("Ensure balance is calculated for first three LP positions", () => {
    it("User mints, manager mints 3x, User direct transfer", async () => {
      // Mint Uniswap v3 LP
      const token0 = assets.usdc;
      const token1 = assets.weth;
      const fee = 500;
      const tick = await getCurrentTick(token0, token1, fee);
      const tickSpacing = fee / 50;
      const mintSettings: UniV3LpMintSettings = {
        token0,
        token1,
        fee,
        amount0: units(2000, 6),
        amount1: units(1),
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await mintLpAsUser(nonfungiblePositionManager, user, mintSettings);
      await mintLpAsPool(poolLogicProxy, manager, mintSettings);
      await mintLpAsPool(poolLogicProxy, manager, mintSettings);
      await mintLpAsPool(poolLogicProxy, manager, mintSettings);

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
      // Mint Uniswap v3 LP
      const token0 = assets.usdc;
      const token1 = assets.weth;
      const fee = 500;
      const tick = await getCurrentTick(token0, token1, fee);
      const tickSpacing = fee / 50;
      const mintSettings: UniV3LpMintSettings = {
        token0,
        token1,
        fee,
        amount0: units(2000, 6),
        amount1: units(1),
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await mintLpAsPool(poolLogicProxy, manager, mintSettings);
      await mintLpAsPool(poolLogicProxy, manager, mintSettings);
      await mintLpAsPool(poolLogicProxy, manager, mintSettings);
      await mintLpAsUser(nonfungiblePositionManager, user, mintSettings);

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
    it("tokenPrice and withdraw works if both LP assets are unsupported", async () => {
      // Mint Uniswap v3 LP
      await assetHandler.removeAsset(assets.frax); // Remove LP assets first
      await assetHandler.removeAsset(assets.miMatic);
      const token0 = assets.frax; // unsupported asset
      const token1 = assets.miMatic; // unsupported asset
      const fee = 500;
      const tick = await getCurrentTick(token0, token1, fee);
      const tickSpacing = fee / 50;
      const mintSettings: UniV3LpMintSettings = {
        token0,
        token1,
        fee,
        amount0: units(1),
        amount1: units(1),
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await mintLpAsUser(nonfungiblePositionManager, user, mintSettings);
      await ethers.provider.send("evm_increaseTime", [60 * 3]); // 3 minutes due to TWAP on pricing. TODO: remove if we decide to not use the TWAP
      await ethers.provider.send("evm_mine", []);

      // Act
      const tokenPriceBefore = await poolLogicProxy.tokenPrice();
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(user.address, 0);
      await nonfungiblePositionManager.connect(user).transferFrom(user.address, poolLogicProxy.address, tokenId);
      const tokenPriceAfter = await poolLogicProxy.tokenPrice();
      const totalFundValueBeforeWithdraw = (await poolLogicProxy.availableManagerFeeAndTotalFundValue()).fundValue;

      // Assert
      expect(totalFundValueBeforeWithdraw).to.gt(0);
      expect(await nonfungiblePositionManager.balanceOf(user.address)).to.equal(0);
      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(1);
      expect(tokenPriceAfter).to.equal(tokenPriceBefore); // TODO: Currently fails because tokenPriceAfter is higher for some reason

      // Can withdraw
      await poolFactory.setExitCooldown(0);
      await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

      // Assert that all pool value is withdrawn
      const totalFundValueAfterWithdraw = (await poolLogicProxy.availableManagerFeeAndTotalFundValue()).fundValue;
      expect(totalFundValueAfterWithdraw).to.equal(0);
    });

    it("tokenPrice and withdraw works if one LP asset is unsupported", async () => {
      // Mint Uniswap v3 LP
      const token0 = assets.xsgd; // unsupported asset
      const token1 = assets.weth; // supported asset
      const fee = 500;
      const currentTick = await getCurrentTick(token0, token1, fee);
      const tickSpacing = fee / 50;
      const mintSettings: UniV3LpMintSettings = {
        token0,
        token1,
        fee,
        amount0: units(1),
        amount1: units(1),
        tickLower: currentTick - tickSpacing,
        tickUpper: currentTick + tickSpacing,
      };
      await mintLpAsUser(nonfungiblePositionManager, user, mintSettings);
      await ethers.provider.send("evm_increaseTime", [60 * 3]); // 3 minutes due to TWAP on pricing. TODO: remove if we decide to not use the TWAP
      await ethers.provider.send("evm_mine", []);

      // Act
      const tokenPriceBefore = await poolLogicProxy.tokenPrice();
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(user.address, 0);
      await nonfungiblePositionManager.connect(user).transferFrom(user.address, poolLogicProxy.address, tokenId);
      const tokenPriceAfter = await poolLogicProxy.tokenPrice();
      const totalFundValueBeforeWithdraw = (await poolLogicProxy.availableManagerFeeAndTotalFundValue()).fundValue;

      // Assert
      expect(totalFundValueBeforeWithdraw).to.gt(0);
      expect(await nonfungiblePositionManager.balanceOf(user.address)).to.equal(0);
      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(1);
      expect(tokenPriceAfter).to.gt(tokenPriceBefore); // Assumes the LP value should be counted

      // Can withdraw
      await poolFactory.setExitCooldown(0);
      await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address)); // TODO: Currently fails on withdrawal with ERC20: transfer amount exceeds balance

      // Assert that all pool value is withdrawn
      const totalFundValueAfterWithdraw = (await poolLogicProxy.availableManagerFeeAndTotalFundValue()).fundValue;
      expect(totalFundValueAfterWithdraw).to.equal(0);
    });
  });
});
