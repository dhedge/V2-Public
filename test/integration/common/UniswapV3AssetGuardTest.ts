import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { Wallet, BigNumber } from "ethers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { describe, it } from "mocha";

import { INonfungiblePositionManager, PoolFactory, PoolLogic, AssetHandler } from "../../../types";
import { createFund } from "../utils/createFund";
import { deployContracts, IDeployments, NETWORK } from "../utils/deployContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { utils } from "../utils/utils";
import { getCurrentTick, mintLpAsPool, mintLpAsUser, UniV3LpMintSettings } from "../utils/uniswapv3Utils";

interface IUniswapV3AssetGuardTestParameters {
  network: NETWORK;
  uniswapV3: {
    factory: string;
    router: string;
    nonfungiblePositionManager: string;
  };
  pairs: {
    bothSupportedPair: {
      fee: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot: number;
      token1Slot: number;
    };
    bothUnsupportedPair: {
      fee: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot?: number;
      token1Slot?: number;
    };
    token0UnsupportedPair: {
      fee: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot?: number;
      token1Slot?: number;
    };
  };
}

export const uniswapV3AssetGuardTest = (params: IUniswapV3AssetGuardTestParameters) => {
  const { network, uniswapV3, pairs } = params;
  const { bothSupportedPair, bothUnsupportedPair, token0UnsupportedPair } = pairs;

  describe("UniswapV3AssetGuardTest", function () {
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, assetHandler: AssetHandler;
    let deployments: IDeployments;
    let nonfungiblePositionManager: INonfungiblePositionManager;
    let user: Wallet;
    let snapId: string;

    before(async function () {
      [logicOwner, manager] = await ethers.getSigners();

      nonfungiblePositionManager = await ethers.getContractAt(
        "INonfungiblePositionManager",
        uniswapV3.nonfungiblePositionManager,
      );

      deployments = await deployContracts(network);

      poolFactory = deployments.poolFactory;
      assetHandler = deployments.assetHandler;

      await getAccountToken(
        bothSupportedPair.amount0.mul(3),
        logicOwner.address,
        bothSupportedPair.token0,
        bothSupportedPair.token0Slot,
      );
      await getAccountToken(
        bothSupportedPair.amount1.mul(3),
        logicOwner.address,
        bothSupportedPair.token1,
        bothSupportedPair.token1Slot,
      );
      const funds = await createFund(
        poolFactory,
        logicOwner,
        manager,
        [
          { asset: bothSupportedPair.token0, isDeposit: true },
          { asset: bothSupportedPair.token1, isDeposit: true },
          { asset: uniswapV3.nonfungiblePositionManager, isDeposit: false },
        ],
        0, // 0% performance fee
      );
      poolLogicProxy = funds.poolLogicProxy;

      await (
        await ethers.getContractAt("IERC20", bothSupportedPair.token0)
      ).approve(poolLogicProxy.address, bothSupportedPair.amount0.mul(3));
      await poolLogicProxy.deposit(bothSupportedPair.token0, bothSupportedPair.amount0.mul(3));
      await (
        await ethers.getContractAt("IERC20", bothSupportedPair.token1)
      ).approve(poolLogicProxy.address, bothSupportedPair.amount1.mul(3));
      await poolLogicProxy.deposit(bothSupportedPair.token1, bothSupportedPair.amount1.mul(3));
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
        const token0 = bothSupportedPair.token0;
        const token1 = bothSupportedPair.token1;
        const fee = bothSupportedPair.fee;
        const tick = await getCurrentTick(uniswapV3.factory, token0, token1, fee);
        const tickSpacing = fee / 50;
        const mintSettings: UniV3LpMintSettings = {
          token0,
          token1,
          fee,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing,
          tickUpper: tick + tickSpacing,
        };
        await mintLpAsUser(nonfungiblePositionManager, user, mintSettings);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);

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

      it("User mints, manager mints 3x, User direct transfer [out-range]", async () => {
        // Mint Uniswap v3 LP
        const token0 = bothSupportedPair.token0;
        const token1 = bothSupportedPair.token1;
        const fee = bothSupportedPair.fee;
        const tick = await getCurrentTick(uniswapV3.factory, token0, token1, fee);
        const tickSpacing = fee / 50;
        const mintSettings: UniV3LpMintSettings = {
          token0,
          token1,
          fee,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing * 2,
          tickUpper: tick - tickSpacing,
        };
        await mintLpAsUser(nonfungiblePositionManager, user, mintSettings);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);

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
        const token0 = bothSupportedPair.token0;
        const token1 = bothSupportedPair.token1;
        const fee = bothSupportedPair.fee;
        const tick = await getCurrentTick(uniswapV3.factory, token0, token1, fee);
        const tickSpacing = fee / 50;
        const mintSettings: UniV3LpMintSettings = {
          token0,
          token1,
          fee,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing,
          tickUpper: tick + tickSpacing,
        };
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
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

      it("Manager mints 3x, User mints, User direct transfer [out-range]", async () => {
        // Mint Uniswap v3 LP
        const token0 = bothSupportedPair.token0;
        const token1 = bothSupportedPair.token1;
        const fee = bothSupportedPair.fee;
        const tick = await getCurrentTick(uniswapV3.factory, token0, token1, fee);
        const tickSpacing = fee / 50;
        const mintSettings: UniV3LpMintSettings = {
          token0,
          token1,
          fee,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing * 2,
          tickUpper: tick - tickSpacing,
        };
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
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
        await assetHandler.removeAsset(bothUnsupportedPair.token0); // Remove LP assets first
        await assetHandler.removeAsset(bothUnsupportedPair.token1);
        const token0 = bothUnsupportedPair.token0; // unsupported asset
        const token1 = bothUnsupportedPair.token1; // unsupported asset
        const fee = bothUnsupportedPair.fee;
        const tick = await getCurrentTick(uniswapV3.factory, token0, token1, fee);
        const tickSpacing = fee / 50;
        const mintSettings: UniV3LpMintSettings = {
          token0,
          token1,
          fee,
          amount0: bothUnsupportedPair.amount0,
          amount1: bothUnsupportedPair.amount1,
          tickLower: tick - tickSpacing,
          tickUpper: tick + tickSpacing,
        };
        await mintLpAsUser(nonfungiblePositionManager, user, mintSettings, [
          bothUnsupportedPair.token0Slot || 0,
          bothUnsupportedPair.token1Slot || 0,
        ]);

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

      it("tokenPrice and withdraw works if both LP assets are unsupported [out-range]", async () => {
        // Mint Uniswap v3 LP
        await assetHandler.removeAsset(bothUnsupportedPair.token0); // Remove LP assets first
        await assetHandler.removeAsset(bothUnsupportedPair.token1);
        const token0 = bothUnsupportedPair.token0; // unsupported asset
        const token1 = bothUnsupportedPair.token1; // unsupported asset
        const fee = bothUnsupportedPair.fee;
        const tick = await getCurrentTick(uniswapV3.factory, token0, token1, fee);
        const tickSpacing = fee / 50;
        const mintSettings: UniV3LpMintSettings = {
          token0,
          token1,
          fee,
          amount0: bothUnsupportedPair.amount0,
          amount1: bothUnsupportedPair.amount1,
          tickLower: tick - tickSpacing * 2,
          tickUpper: tick - tickSpacing,
        };
        await mintLpAsUser(nonfungiblePositionManager, user, mintSettings, [
          bothUnsupportedPair.token0Slot || 0,
          bothUnsupportedPair.token1Slot || 0,
        ]);

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
        const token0 = token0UnsupportedPair.token0; // unsupported asset
        const token1 = token0UnsupportedPair.token1; // supported asset
        const fee = token0UnsupportedPair.fee;
        const currentTick = await getCurrentTick(uniswapV3.factory, token0, token1, fee);
        const tickSpacing = fee / 50;
        const mintSettings: UniV3LpMintSettings = {
          token0,
          token1,
          fee,
          amount0: token0UnsupportedPair.amount0,
          amount1: token0UnsupportedPair.amount1,
          tickLower: currentTick - tickSpacing,
          tickUpper: currentTick + tickSpacing,
        };
        await mintLpAsUser(nonfungiblePositionManager, user, mintSettings, [
          token0UnsupportedPair.token0Slot || 0,
          token0UnsupportedPair.token1Slot || 0,
        ]);

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
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        // Assert that all pool value is withdrawn
        const totalFundValueAfterWithdraw = (await poolLogicProxy.availableManagerFeeAndTotalFundValue()).fundValue;
        expect(totalFundValueAfterWithdraw).eq(0); // there are no manager fees minted (performance fee set to 0)
      });

      it("tokenPrice and withdraw works if one LP asset is unsupported [out-range]", async () => {
        // Mint Uniswap v3 LP
        const token0 = token0UnsupportedPair.token0; // unsupported asset
        const token1 = token0UnsupportedPair.token1; // supported asset
        const fee = token0UnsupportedPair.fee;
        const currentTick = await getCurrentTick(uniswapV3.factory, token0, token1, fee);
        const tickSpacing = fee / 50;
        const mintSettings: UniV3LpMintSettings = {
          token0,
          token1,
          fee,
          amount0: token0UnsupportedPair.amount0,
          amount1: token0UnsupportedPair.amount1,
          tickLower: currentTick - tickSpacing * 2,
          tickUpper: currentTick - tickSpacing,
        };
        await mintLpAsUser(nonfungiblePositionManager, user, mintSettings, [
          token0UnsupportedPair.token0Slot || 0,
          token0UnsupportedPair.token1Slot || 0,
        ]);

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
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        // Assert that all pool value is withdrawn
        const totalFundValueAfterWithdraw = (await poolLogicProxy.availableManagerFeeAndTotalFundValue()).fundValue;
        expect(totalFundValueAfterWithdraw).eq(0); // there are no manager fees minted (performance fee set to 0)
      });
    });
  });
};
