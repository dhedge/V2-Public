import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import type { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { INonfungiblePositionManager, IV3SwapRouter } from "../../../../types";
import { units } from "../../../testHelpers";
import { approveToken, getAccountToken, getBalance } from "../../utils/getAccountTokens";
import {
  getCurrentPrice,
  getCurrentTick,
  getV3LpBalances,
  mintLpAsUser,
  UniV3LpMintSettings,
} from "../../utils/uniV3Utils";
import { utils } from "../../utils/utils";

export const UniswapV3PureTest = (
  uniswapV3: {
    factory: string;
    router: string;
    nonfungiblePositionManager: string;
  },
  bothSupportedNonStablePair: {
    fee: number;
    token0: string;
    token1: string;
    amount0: BigNumber;
    amount1: BigNumber;
    token0Slot: number;
    token1Slot: number;
    token0Decimals: number;
    token1Decimals: number;
  },
) => {
  describe("UniswapV3AssetGuardTest", function () {
    let logicOwner: SignerWithAddress;

    let nonfungiblePositionManager: INonfungiblePositionManager;
    let snapId: string;

    before(async function () {
      [logicOwner] = await ethers.getSigners();

      nonfungiblePositionManager = await ethers.getContractAt(
        "INonfungiblePositionManager",
        uniswapV3.nonfungiblePositionManager,
      );

      await getAccountToken(
        bothSupportedNonStablePair.amount0,
        logicOwner.address,
        bothSupportedNonStablePair.token0,
        bothSupportedNonStablePair.token0Slot,
      );
      await getAccountToken(
        bothSupportedNonStablePair.amount1,
        logicOwner.address,
        bothSupportedNonStablePair.token1,
        bothSupportedNonStablePair.token1Slot,
      );
    });

    beforeEach(async () => {
      snapId = await utils.evmTakeSnap();
    });

    afterEach(async () => {
      await utils.evmRestoreSnap(snapId);
    });

    describe("Traders cannot steal value from lp'ers", () => {
      // This proves that traders cannot steal value from an LP
      // On Slack: For univ3 assets, intrablock, they can manipulate the ratio of the two to the point where the pool seems like it's holding a less favourable split long term (but in reality it's not) but the culminative value will be relatively the same
      // https://dhedge-workspace.slack.com/archives/C01TB26C9N2/p1645415332424759
      // The price of the LP cannot be reduced by trading into it.
      // This does mean that someone using withdrawSingle could inflate the price of the LP
      // And then withdraw more of one other asset from the pool than they should be able to
      // The cost of doing this is .6% of the volume that is required to shift the price of the lp to the desired price
      // The deeper the liquidity the higher the cost.
      it("One directional trade cannot steal", async () => {
        const pair = bothSupportedNonStablePair;
        const tick = await getCurrentTick(uniswapV3.factory, pair);
        console.log("Current Tick", tick);
        const token0Price = await getCurrentPrice(uniswapV3.factory, pair);
        const token0PriceInUSD = token0Price.div(units(1, pair.token1Decimals));
        console.log("Token0 Price in Token1", token0Price.toString());
        console.log("Token0 Price in Token1 whole unit", token0PriceInUSD.toString());

        // Full range for 0.05%
        // https://github.com/0xTomoyo/fullrange/blob/f0c30c64fe3af1ba0eff51f9e5a2aa5ee475ccbd/src/test/TickMath.t.sol
        // https://github.com/0xTomoyo/fullrange/blob/f0c30c64fe3af1ba0eff51f9e5a2aa5ee475ccbd/src/libraries/TickMath.sol
        const tickRange = {
          tickLower: -887270,
          tickUpper: 887270,
        };
        console.log("Tick range", tickRange);
        const mintSettings: UniV3LpMintSettings = { ...pair, ...tickRange };
        const token0BalanceBeforeLP = await getBalance(logicOwner.address, pair.token0);
        const token1BalanceBeforeLP = await getBalance(logicOwner.address, pair.token1);
        await mintLpAsUser(nonfungiblePositionManager, logicOwner, mintSettings);

        const costToMintToken0 = token0BalanceBeforeLP.sub(await getBalance(logicOwner.address, pair.token0));
        const costToMintToken1 = token1BalanceBeforeLP.sub(await getBalance(logicOwner.address, pair.token1));

        const price = (amount: BigNumber, decimals: number, price: BigNumber) => {
          return amount.mul(price).div(ethers.BigNumber.from(10).pow(decimals));
        };

        const priceLp0 = price(costToMintToken0, pair.token0Decimals, token0PriceInUSD);
        const priceLp1 = price(costToMintToken1, pair.token1Decimals, ethers.BigNumber.from(1));
        const lpCost = priceLp0.add(priceLp1);
        console.log("Token0:Token1 in", pair.amount0.toString(), ":", pair.amount1.toString());
        console.log("Token0:Token1 taken", costToMintToken0.toString(), ":", costToMintToken1.toString());
        console.log("Token0:Token1 cost$$", priceLp0.toString(), ":", priceLp1.toString());
        console.log("Total LP Cost", lpCost.toString());

        const swapRouter: IV3SwapRouter = await ethers.getContractAt("IV3SwapRouter", uniswapV3.router);

        const [token0Liquidity] = await getV3LpBalances(uniswapV3.factory, pair);

        const LIQUIDITY_MULTIPLIER = 10;
        console.log("Getting", LIQUIDITY_MULTIPLIER, "x the current liquidity of token0", token0Liquidity.toString());
        const amountIn = token0Liquidity.mul(LIQUIDITY_MULTIPLIER);
        await getAccountToken(amountIn, logicOwner.address, pair.token0, pair.token0Slot);
        await approveToken(logicOwner, swapRouter.address, pair.token0, amountIn);

        console.log("Exchanging", LIQUIDITY_MULTIPLIER, "x token0 liquidity for token1");
        await swapRouter.exactInputSingle({
          tokenIn: pair.token0,
          tokenOut: pair.token1,
          amountIn,
          amountOutMinimum: 0,
          fee: pair.fee,
          recipient: logicOwner.address,
          sqrtPriceLimitX96: 0,
        });

        const token0PriceAfterSwap = await getCurrentPrice(uniswapV3.factory, pair);
        const token0PriceInUSDAfterSwap = token0PriceAfterSwap.div(units(1, pair.token1Decimals));
        // This is proving the swap mangled the ratios and changed the tick
        console.log("Tick after swap", await getCurrentTick(uniswapV3.factory, pair));
        console.log("Uniswap price of Token0 in token1 after exchange", token0PriceAfterSwap.toString());
        // this can be < 1 whole unit and therefore will be 0 as a bigNumber
        console.log(
          "Uniswap price of Token0 in token1 after exchange whole unit",
          token0PriceInUSDAfterSwap.toString(),
        );
        console.log("^^The price has not changed anywhere else except on uniswap");
        console.log("Chainlink price is still", token0PriceInUSD.toString());

        expect(await nonfungiblePositionManager.balanceOf(logicOwner.address)).to.equal(1);
        const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(logicOwner.address, 0);
        const position = await nonfungiblePositionManager.positions(tokenId);

        const token0BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, pair.token0);
        const token1BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, pair.token1);

        console.log("Decreasing liquidity");
        await nonfungiblePositionManager.connect(logicOwner).decreaseLiquidity({
          liquidity: position.liquidity,
          tokenId: tokenId,
          amount0Min: 0,
          amount1Min: 0,
          deadline: Math.floor(Date.now() / 1000 + 100000000),
        });
        console.log("Collecting");
        await nonfungiblePositionManager.connect(logicOwner).collect({
          tokenId,
          recipient: logicOwner.address,
          amount0Max: units(1000000),
          amount1Max: units(1000000),
        });

        const returnedToUser0 = (await getBalance(logicOwner.address, pair.token0)).sub(token0BalanceBeforeDecreaseLP);
        const returnedToUser1 = (await getBalance(logicOwner.address, pair.token1)).sub(token1BalanceBeforeDecreaseLP);

        const returnedLp0 = price(returnedToUser0, pair.token0Decimals, token0PriceInUSD);
        console.log("Token0 Returned", returnedToUser0.toString(), returnedLp0.toString());

        const returnedLp1 = price(returnedToUser1, pair.token1Decimals, ethers.BigNumber.from(1));
        console.log("Token1 Returned", returnedToUser1.toString(), returnedLp1.toString());

        const totalReturned = returnedLp0.add(returnedLp1);
        console.log("Total Returned", totalReturned.toString());
        console.log("Cost:Return", lpCost.toString(), ":", totalReturned.toString());
        console.log("LPer lost money?", lpCost.gt(totalReturned));
        expect(lpCost.gt(totalReturned)).to.be.false;
      }).timeout(30000);

      it("Swing trade (aka flashloan) cannot steal from lpers", async () => {
        const pair = bothSupportedNonStablePair;
        const tick = await getCurrentTick(uniswapV3.factory, pair);
        console.log("Current Tick", tick);
        const token0Price = await getCurrentPrice(uniswapV3.factory, pair);
        const token0PriceInUSD = token0Price.div(units(1, pair.token1Decimals));
        console.log("Token0 Price in Token1", token0Price.toString());
        console.log("Token0 Price in Token1 whole unit", token0PriceInUSD.toString());
        // Full range for 0.05%
        // https://github.com/0xTomoyo/fullrange/blob/f0c30c64fe3af1ba0eff51f9e5a2aa5ee475ccbd/src/test/TickMath.t.sol
        // https://github.com/0xTomoyo/fullrange/blob/f0c30c64fe3af1ba0eff51f9e5a2aa5ee475ccbd/src/libraries/TickMath.sol

        const tickRange = {
          tickLower: -887270,
          tickUpper: 887270,
        };
        console.log("Tick range", tickRange);
        const mintSettings: UniV3LpMintSettings = { ...pair, ...tickRange };

        const token0BalanceBeforeLP = await getBalance(logicOwner.address, pair.token0);
        const token1BalanceBeforeLP = await getBalance(logicOwner.address, pair.token1);
        await mintLpAsUser(nonfungiblePositionManager, logicOwner, mintSettings);

        const costToMintToken0 = token0BalanceBeforeLP.sub(await getBalance(logicOwner.address, pair.token0));
        const costToMintToken1 = token1BalanceBeforeLP.sub(await getBalance(logicOwner.address, pair.token1));

        const price = (amount: BigNumber, decimals: number, price: BigNumber) => {
          return amount.mul(price).div(ethers.BigNumber.from(10).pow(decimals));
        };

        const priceLp0 = price(costToMintToken0, pair.token0Decimals, token0PriceInUSD);
        const priceLp1 = price(costToMintToken1, pair.token1Decimals, ethers.BigNumber.from(1));
        const lpCost = priceLp0.add(priceLp1);
        console.log("Token0:Token1 in", pair.amount0.toString(), ":", pair.amount1.toString());
        console.log("Token0:Token1 taken", costToMintToken0.toString(), ":", costToMintToken1.toString());
        console.log("Token0:Token1 cost$$", priceLp0.toString(), ":", priceLp1.toString());
        console.log("Total LP Cost", lpCost.toString());

        const swapRouter: IV3SwapRouter = await ethers.getContractAt("IV3SwapRouter", uniswapV3.router);

        const [token0Liquidity, token1Liquidity] = await getV3LpBalances(uniswapV3.factory, pair);

        const LIQUIDITY_MULTIPLIER = 10;
        console.log("Getting", LIQUIDITY_MULTIPLIER, "x the current liquidity of token0", token0Liquidity.toString());
        const amountIn = token0Liquidity.mul(LIQUIDITY_MULTIPLIER);
        await getAccountToken(amountIn, logicOwner.address, pair.token0, pair.token0Slot);
        await approveToken(logicOwner, swapRouter.address, pair.token0, amountIn);

        console.log("Exchanging", LIQUIDITY_MULTIPLIER, "x token0 liquidity for token1");
        await swapRouter.exactInputSingle({
          tokenIn: pair.token0,
          tokenOut: pair.token1,
          amountIn,
          amountOutMinimum: 0,
          fee: pair.fee,
          recipient: logicOwner.address,
          sqrtPriceLimitX96: 0,
        });

        const token0PriceAfterSwap = await getCurrentPrice(uniswapV3.factory, pair);
        const token0PriceInUSDAfterSwap = token0PriceAfterSwap.div(units(1, pair.token1Decimals));
        // This is proving the swap mangled the ratios and changed the tick
        console.log("Tick after swap", await getCurrentTick(uniswapV3.factory, pair));
        console.log("Uniswap price of Token0 in token1 after exchange", token0PriceAfterSwap.toString());
        // this can be < 1 whole unit and therefore will be 0 as a bigNumber
        console.log(
          "Uniswap price of Token0 in token1 after exchange whole unit",
          token0PriceInUSDAfterSwap.toString(),
        );
        console.log("^^The price has not changed anywhere else except on uniswap");
        console.log("Chainlink price is still", token0PriceInUSD.toString());

        // At this point the pool is extremely unbalanced relative to the rest of the world
        // a massive arb opportunity for another trader has emerged.

        // Rebalance the pool by putting back the previous liquidity that was drained
        const rebalanceLiquidityIn = token1Liquidity;
        await getAccountToken(rebalanceLiquidityIn, logicOwner.address, pair.token1, pair.token1Slot);
        await approveToken(logicOwner, swapRouter.address, pair.token1, rebalanceLiquidityIn);

        console.log("Exchanging", LIQUIDITY_MULTIPLIER, "x token0 liquidity for token1");
        await swapRouter.exactInputSingle({
          tokenIn: pair.token1,
          tokenOut: pair.token0,
          amountIn: rebalanceLiquidityIn,
          amountOutMinimum: 0,
          fee: pair.fee,
          recipient: logicOwner.address,
          sqrtPriceLimitX96: 0,
        });

        expect(await nonfungiblePositionManager.balanceOf(logicOwner.address)).to.equal(1);
        const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(logicOwner.address, 0);
        const position = await nonfungiblePositionManager.positions(tokenId);

        const token0BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, pair.token0);
        const token1BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, pair.token1);

        console.log("Decreasing liquidity");
        await nonfungiblePositionManager.connect(logicOwner).decreaseLiquidity({
          liquidity: position.liquidity,
          tokenId: tokenId,
          amount0Min: 0,
          amount1Min: 0,
          deadline: Math.floor(Date.now() / 1000 + 100000000),
        });
        console.log("Collecting");
        await nonfungiblePositionManager.connect(logicOwner).collect({
          tokenId,
          recipient: logicOwner.address,
          amount0Max: units(1000000),
          amount1Max: units(1000000),
        });

        const returnedToUser0 = (await getBalance(logicOwner.address, pair.token0)).sub(token0BalanceBeforeDecreaseLP);
        const returnedToUser1 = (await getBalance(logicOwner.address, pair.token1)).sub(token1BalanceBeforeDecreaseLP);

        const returnedLp0 = price(returnedToUser0, pair.token0Decimals, token0PriceInUSD);
        console.log("Token0 Returned", returnedToUser0.toString(), returnedLp0.toString());

        const returnedLp1 = price(returnedToUser1, pair.token1Decimals, ethers.BigNumber.from(1));
        console.log("Token1 Returned", returnedToUser1.toString(), returnedLp1.toString());

        const totalReturned = returnedLp0.add(returnedLp1);
        console.log("Total Returned", totalReturned.toString());
        console.log("Cost:Return", lpCost.toString(), ":", totalReturned.toString());
        console.log("LPer lost money?", lpCost.gt(totalReturned));
        console.log(
          "The difference here is the fees around:",
          pair.fee / 10000,
          "x 2 =",
          (pair.fee * 2) / 10000,
          "% of the volume traded through the pool",
        );
        expect(lpCost.gt(totalReturned)).to.be.false;
      }).timeout(30000);

      it("LP out of range, only token0", async () => {
        const pair = bothSupportedNonStablePair;
        const tick = await getCurrentTick(uniswapV3.factory, pair);
        console.log("Current Tick", tick);
        const token0Price = await getCurrentPrice(uniswapV3.factory, pair);
        const token0PriceInUSD = token0Price.div(units(1, pair.token1Decimals));
        console.log("Token0 Price in Token1", token0Price.toString());
        console.log("Token0 Price in Token1 whole unit", token0PriceInUSD.toString());

        // out of range
        // Will create LP position with only token0 (WETH)
        const tickRange = {
          tickLower: tick + 50000,
          tickUpper: 887270,
        };
        console.log("Tick range", tickRange);
        const mintSettings: UniV3LpMintSettings = { ...pair, ...tickRange };
        const token0BalanceBeforeLP = await getBalance(logicOwner.address, pair.token0);
        const token1BalanceBeforeLP = await getBalance(logicOwner.address, pair.token1);
        await mintLpAsUser(nonfungiblePositionManager, logicOwner, mintSettings);

        const costToMintToken0 = token0BalanceBeforeLP.sub(await getBalance(logicOwner.address, pair.token0));
        const costToMintToken1 = token1BalanceBeforeLP.sub(await getBalance(logicOwner.address, pair.token1));

        const price = (amount: BigNumber, decimals: number, price: BigNumber) => {
          return amount.mul(price).div(ethers.BigNumber.from(10).pow(decimals));
        };

        const priceLp0 = price(costToMintToken0, pair.token0Decimals, token0PriceInUSD);
        const priceLp1 = price(costToMintToken1, pair.token1Decimals, ethers.BigNumber.from(1));
        const lpCost = priceLp0.add(priceLp1);
        console.log("Token0:Token1 in", pair.amount0.toString(), ":", pair.amount1.toString());
        console.log("Token0:Token1 taken", costToMintToken0.toString(), ":", costToMintToken1.toString());
        console.log("Token0:Token1 cost$$", priceLp0.toString(), ":", priceLp1.toString());
        console.log("Total LP Cost", lpCost.toString());

        const swapRouter: IV3SwapRouter = await ethers.getContractAt("IV3SwapRouter", uniswapV3.router);

        const [token0Liquidity] = await getV3LpBalances(uniswapV3.factory, pair);

        const LIQUIDITY_MULTIPLIER = 10;
        console.log("Getting", LIQUIDITY_MULTIPLIER, "x the current liquidity of token0", token0Liquidity.toString());
        const amountIn = token0Liquidity.mul(LIQUIDITY_MULTIPLIER);
        await getAccountToken(amountIn, logicOwner.address, pair.token0, pair.token0Slot);
        await approveToken(logicOwner, swapRouter.address, pair.token0, amountIn);

        console.log("Exchanging", LIQUIDITY_MULTIPLIER, "x token0 liquidity for token1");
        await swapRouter.exactInputSingle({
          tokenIn: pair.token0,
          tokenOut: pair.token1,
          amountIn,
          amountOutMinimum: 0,
          fee: pair.fee,
          recipient: logicOwner.address,
          sqrtPriceLimitX96: 0,
        });

        const token0PriceAfterSwap = await getCurrentPrice(uniswapV3.factory, pair);
        const token0PriceInUSDAfterSwap = token0PriceAfterSwap.div(units(1, pair.token1Decimals));
        // This is proving the swap mangled the ratios and changed the tick
        console.log("Tick after swap", await getCurrentTick(uniswapV3.factory, pair));
        console.log("Uniswap price of Token0 in token1 after exchange", token0PriceAfterSwap.toString());
        // this can be < 1 whole unit and therefore will be 0 as a bigNumber
        console.log(
          "Uniswap price of Token0 in token1 after exchange whole unit",
          token0PriceInUSDAfterSwap.toString(),
        );
        console.log("^^The price has not changed anywhere else except on uniswap");
        console.log("Chainlink price is still", token0PriceInUSD.toString());

        expect(await nonfungiblePositionManager.balanceOf(logicOwner.address)).to.equal(1);
        const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(logicOwner.address, 0);
        const position = await nonfungiblePositionManager.positions(tokenId);

        const token0BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, pair.token0);
        const token1BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, pair.token1);

        console.log("Decreasing liquidity");
        await nonfungiblePositionManager.connect(logicOwner).decreaseLiquidity({
          liquidity: position.liquidity,
          tokenId: tokenId,
          amount0Min: 0,
          amount1Min: 0,
          deadline: Math.floor(Date.now() / 1000 + 100000000),
        });
        console.log("Collecting");
        await nonfungiblePositionManager.connect(logicOwner).collect({
          tokenId,
          recipient: logicOwner.address,
          amount0Max: units(1000000),
          amount1Max: units(1000000),
        });

        const returnedToUser0 = (await getBalance(logicOwner.address, pair.token0)).sub(token0BalanceBeforeDecreaseLP);
        const returnedToUser1 = (await getBalance(logicOwner.address, pair.token1)).sub(token1BalanceBeforeDecreaseLP);

        const returnedLp0 = price(returnedToUser0, pair.token0Decimals, token0PriceInUSD);
        console.log("Token0 Returned", returnedToUser0.toString(), returnedLp0.toString());

        const returnedLp1 = price(returnedToUser1, pair.token1Decimals, ethers.BigNumber.from(1));
        console.log("Token1 Returned", returnedToUser1.toString(), returnedLp1.toString());

        const totalReturned = returnedLp0.add(returnedLp1);
        console.log("Total Returned", totalReturned.toString());
        console.log("Cost:Return", lpCost.toString(), ":", totalReturned.toString());
        console.log("LPer lost money?", lpCost.gt(totalReturned));
        expect(lpCost.gt(totalReturned)).to.be.false;
      }).timeout(30000);

      it("LP out of range, only token1", async () => {
        const pair = bothSupportedNonStablePair;
        const tick = await getCurrentTick(uniswapV3.factory, pair);
        console.log("Current Tick", tick);
        const token0Price = await getCurrentPrice(uniswapV3.factory, pair);
        const token0PriceInUSD = token0Price.div(units(1, pair.token1Decimals));
        console.log("Token0 Price in Token1", token0Price.toString());
        console.log("Token0 Price in Token1 whole unit", token0PriceInUSD.toString());

        // out of range
        // Will create LP position with only token1 (USDC)
        const tickRange = {
          tickLower: -887270,
          tickUpper: tick - 50000,
        };
        console.log("Tick range", tickRange);
        const mintSettings: UniV3LpMintSettings = { ...pair, ...tickRange };
        const token0BalanceBeforeLP = await getBalance(logicOwner.address, pair.token0);
        const token1BalanceBeforeLP = await getBalance(logicOwner.address, pair.token1);
        await mintLpAsUser(nonfungiblePositionManager, logicOwner, mintSettings);

        const costToMintToken0 = token0BalanceBeforeLP.sub(await getBalance(logicOwner.address, pair.token0));
        const costToMintToken1 = token1BalanceBeforeLP.sub(await getBalance(logicOwner.address, pair.token1));

        const price = (amount: BigNumber, decimals: number, price: BigNumber) => {
          return amount.mul(price).div(ethers.BigNumber.from(10).pow(decimals));
        };

        const priceLp0 = price(costToMintToken0, pair.token0Decimals, token0PriceInUSD);
        const priceLp1 = price(costToMintToken1, pair.token1Decimals, ethers.BigNumber.from(1));
        const lpCost = priceLp0.add(priceLp1);
        console.log("Token0:Token1 in", pair.amount0.toString(), ":", pair.amount1.toString());
        console.log("Token0:Token1 taken", costToMintToken0.toString(), ":", costToMintToken1.toString());
        console.log("Token0:Token1 cost$$", priceLp0.toString(), ":", priceLp1.toString());
        console.log("Total LP Cost", lpCost.toString());

        const swapRouter: IV3SwapRouter = await ethers.getContractAt("IV3SwapRouter", uniswapV3.router);

        const [token0Liquidity] = await getV3LpBalances(uniswapV3.factory, pair);

        const LIQUIDITY_MULTIPLIER = 10;
        console.log("Getting", LIQUIDITY_MULTIPLIER, "x the current liquidity of token0", token0Liquidity.toString());
        const amountIn = token0Liquidity.mul(LIQUIDITY_MULTIPLIER);
        await getAccountToken(amountIn, logicOwner.address, pair.token0, pair.token0Slot);
        await approveToken(logicOwner, swapRouter.address, pair.token0, amountIn);

        console.log("Exchanging", LIQUIDITY_MULTIPLIER, "x token0 liquidity for token1");
        await swapRouter.exactInputSingle({
          tokenIn: pair.token0,
          tokenOut: pair.token1,
          amountIn,
          amountOutMinimum: 0,
          fee: pair.fee,
          recipient: logicOwner.address,
          sqrtPriceLimitX96: 0,
        });

        const token0PriceAfterSwap = await getCurrentPrice(uniswapV3.factory, pair);
        const token0PriceInUSDAfterSwap = token0PriceAfterSwap.div(units(1, pair.token1Decimals));
        // This is proving the swap mangled the ratios and changed the tick
        console.log("Tick after swap", await getCurrentTick(uniswapV3.factory, pair));
        console.log("Uniswap price of Token0 in token1 after exchange", token0PriceAfterSwap.toString());
        // this can be < 1 whole unit and therefore will be 0 as a bigNumber
        console.log(
          "Uniswap price of Token0 in token1 after exchange whole unit",
          token0PriceInUSDAfterSwap.toString(),
        );
        console.log("^^The price has not changed anywhere else except on uniswap");
        console.log("Chainlink price is still", token0PriceInUSD.toString());

        expect(await nonfungiblePositionManager.balanceOf(logicOwner.address)).to.equal(1);
        const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(logicOwner.address, 0);
        const position = await nonfungiblePositionManager.positions(tokenId);

        const token0BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, pair.token0);
        const token1BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, pair.token1);

        console.log("Decreasing liquidity");
        await nonfungiblePositionManager.connect(logicOwner).decreaseLiquidity({
          liquidity: position.liquidity,
          tokenId: tokenId,
          amount0Min: 0,
          amount1Min: 0,
          deadline: Math.floor(Date.now() / 1000 + 100000000),
        });
        console.log("Collecting");
        await nonfungiblePositionManager.connect(logicOwner).collect({
          tokenId,
          recipient: logicOwner.address,
          amount0Max: units(1000000),
          amount1Max: units(1000000),
        });

        const returnedToUser0 = (await getBalance(logicOwner.address, pair.token0)).sub(token0BalanceBeforeDecreaseLP);
        const returnedToUser1 = (await getBalance(logicOwner.address, pair.token1)).sub(token1BalanceBeforeDecreaseLP);

        const returnedLp0 = price(returnedToUser0, pair.token0Decimals, token0PriceInUSD);
        console.log("Token0 Returned", returnedToUser0.toString(), returnedLp0.toString());

        const returnedLp1 = price(returnedToUser1, pair.token1Decimals, ethers.BigNumber.from(1));
        console.log("Token1 Returned", returnedToUser1.toString(), returnedLp1.toString());

        const totalReturned = returnedLp0.add(returnedLp1);
        console.log("Total Returned", totalReturned.toString());
        console.log("Cost:Return", lpCost.toString(), ":", totalReturned.toString());
        console.log("LPer lost money?", lpCost.gt(totalReturned));
        expect(lpCost.gt(totalReturned)).to.be.false;
      }).timeout(30000);
    });
  });
};
