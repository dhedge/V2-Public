import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, Wallet } from "ethers";
import { ethers } from "hardhat";
import {
  AssetHandler,
  INonfungiblePositionManager,
  IV3SwapRouter,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { deployContracts, IDeployments, NETWORK } from "../utils/deployContracts/deployContracts";
import { approveToken, getAccountToken } from "../utils/getAccountTokens";
import {
  getCurrentSqrtPriceX96,
  getCurrentTick,
  getOracleSqrtPriceX96,
  getV3LpBalances,
  mintLpAsPool,
  mintLpAsUser,
  UniV3LpMintSettings,
} from "../utils/uniV3Utils";
import { utils } from "../utils/utils";

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
    bothSupportedNonStablePair: {
      fee: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot: number;
      token1Slot: number;
    };
  };
}

export const uniswapV3AssetGuardTest = (params: IUniswapV3AssetGuardTestParameters) => {
  const { network, uniswapV3, pairs } = params;
  const { bothSupportedPair, bothUnsupportedPair, token0UnsupportedPair, bothSupportedNonStablePair } = pairs;

  describe("UniswapV3AssetGuardTest", function () {
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory,
      poolLogicProxy: PoolLogic,
      assetHandler: AssetHandler,
      poolManagerLogicProxy: PoolManagerLogic;
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
        {
          performance: BigNumber.from("0"),
          management: BigNumber.from("0"),
        },
      );
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      await (
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token0)
      ).approve(poolLogicProxy.address, bothSupportedPair.amount0.mul(3));
      await poolLogicProxy.deposit(bothSupportedPair.token0, bothSupportedPair.amount0.mul(3));
      await (
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token1)
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

    describe("Pricing is manipulation resistant", () => {
      [bothSupportedPair, bothSupportedNonStablePair].forEach((pair) => {
        it(`Using pair: ${pair.token0}-${pair.token1}`, async () => {
          await poolManagerLogicProxy.connect(manager).changeAssets(
            [
              { asset: pair.token0, isDeposit: true },
              { asset: pair.token1, isDeposit: true },
            ],
            [],
          );

          await getAccountToken(pair.amount0, logicOwner.address, pair.token0, pair.token0Slot);
          await getAccountToken(pair.amount1, logicOwner.address, pair.token1, pair.token1Slot);

          await approveToken(logicOwner, poolLogicProxy.address, pair.token0, pair.amount0);
          await poolLogicProxy.deposit(pair.token0, pair.amount0);
          await approveToken(logicOwner, poolLogicProxy.address, pair.token1, pair.amount1);
          await poolLogicProxy.deposit(pair.token1, pair.amount1);

          const poolSqrtPriceX96 = await getCurrentSqrtPriceX96(uniswapV3.factory, pair);
          const oracleSqrtPriceX96 = await getOracleSqrtPriceX96(poolFactory, pair);
          console.log(
            "Square root price deviation from oracle:",
            (poolSqrtPriceX96.mul(100000).div(oracleSqrtPriceX96).toNumber() - 100000) / 1000,
            "%",
          );

          // Mint Uniswap v3 LP
          const tick = await getCurrentTick(uniswapV3.factory, pair);
          const tickRange = (pair.fee / 50) * 1000;
          const mintSettings: UniV3LpMintSettings = {
            token0: pair.token0,
            token1: pair.token1,
            fee: pair.fee,
            amount0: pair.amount0,
            amount1: pair.amount1,
            tickLower: tick - tickRange,
            tickUpper: tick + tickRange,
          };

          await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings, true);
          const tokenPriceBefore = await poolLogicProxy.tokenPrice();

          // Act
          const swapRouter: IV3SwapRouter = await ethers.getContractAt("IV3SwapRouter", uniswapV3.router);
          const [token0Liquidity] = await getV3LpBalances(uniswapV3.factory, pair);
          // We dump 2x extra liquidity on one side, draining the other side
          const LIQUIDITY_MULTIPLIER = 10;
          const amountIn = token0Liquidity.mul(LIQUIDITY_MULTIPLIER);
          await getAccountToken(amountIn, logicOwner.address, pair.token0, pair.token0Slot);
          await approveToken(logicOwner, swapRouter.address, pair.token0, amountIn);

          await swapRouter.exactInputSingle({
            tokenIn: pair.token0,
            tokenOut: pair.token1,
            amountIn,
            amountOutMinimum: 0,
            fee: pair.fee,
            recipient: logicOwner.address,
            sqrtPriceLimitX96: 0,
          });

          // Assert
          const [token0LiquidityAfter] = await getV3LpBalances(uniswapV3.factory, pair);
          // console.log("tokenPrice before", tokenPriceBefore.toString());
          // console.log("liq before: ", token0Liquidity.toString(), "liq after: ", token0LiquidityAfter.toString());

          // Assert that the pool has been manipulated
          await expect(poolLogicProxy.tokenPrice()).to.be.revertedWith("Uni v3 LP price mismatch");
          expect(tokenPriceBefore).to.be.closeTo(units(1), tokenPriceBefore.div(1000).toNumber());
          expect(token0LiquidityAfter.gt(token0Liquidity)).to.be.true;
        });
      });
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
        const tick = await getCurrentTick(uniswapV3.factory, bothSupportedPair);
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
        const tick = await getCurrentTick(uniswapV3.factory, bothSupportedPair);
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
        const tick = await getCurrentTick(uniswapV3.factory, bothSupportedPair);
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
        const tick = await getCurrentTick(uniswapV3.factory, bothSupportedPair);
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
        const tick = await getCurrentTick(uniswapV3.factory, bothUnsupportedPair);
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
        expect(tokenPriceAfter).to.equal(tokenPriceBefore);

        // Can withdraw
        await ethers.provider.send("evm_increaseTime", [86400]);
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
        const tick = await getCurrentTick(uniswapV3.factory, bothUnsupportedPair);
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
        expect(tokenPriceAfter).to.equal(tokenPriceBefore);

        // Can withdraw
        await ethers.provider.send("evm_increaseTime", [86400]);
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        // Assert that all pool value is withdrawn
        const totalFundValueAfterWithdraw = (await poolLogicProxy.availableManagerFeeAndTotalFundValue()).fundValue;
        expect(totalFundValueAfterWithdraw).to.equal(0);
      });

      it("tokenPrice and withdraw works if one LP asset is unsupported", async () => {
        // Mint Uniswap v3 LP
        const token0 = token0UnsupportedPair.token0; // unsupported asset
        const token1 = token0UnsupportedPair.token1; // supported asset
        await assetHandler.removeAsset(token0);
        const fee = token0UnsupportedPair.fee;
        const currentTick = await getCurrentTick(uniswapV3.factory, token0UnsupportedPair);
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
        expect(tokenPriceAfter).to.eq(tokenPriceBefore); // Assumes the LP value is not counted

        // Can withdraw
        await ethers.provider.send("evm_increaseTime", [86400]);
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        // Assert that all pool value is withdrawn
        const totalFundValueAfterWithdraw = (await poolLogicProxy.availableManagerFeeAndTotalFundValue()).fundValue;
        expect(totalFundValueAfterWithdraw).eq(0); // there are no manager fees minted (performance fee set to 0)
      });

      it("tokenPrice and withdraw works if one LP asset is unsupported [out-range]", async () => {
        // Mint Uniswap v3 LP
        const token0 = token0UnsupportedPair.token0; // unsupported asset
        const token1 = token0UnsupportedPair.token1; // supported asset
        await assetHandler.removeAsset(token0);
        const fee = token0UnsupportedPair.fee;
        const currentTick = await getCurrentTick(uniswapV3.factory, token0UnsupportedPair);
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
        expect(tokenPriceAfter).to.eq(tokenPriceBefore); // Assumes the LP value is not counted

        // Can withdraw
        await ethers.provider.send("evm_increaseTime", [86400]);
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        // Assert that all pool value is withdrawn
        const totalFundValueAfterWithdraw = (await poolLogicProxy.availableManagerFeeAndTotalFundValue()).fundValue;
        expect(totalFundValueAfterWithdraw).eq(0); // there are no manager fees minted (performance fee set to 0)
      });
    });
  });
};
