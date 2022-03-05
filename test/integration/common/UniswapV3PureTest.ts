import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import type { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { describe, it } from "mocha";
import { INonfungiblePositionManager, IV3SwapRouter } from "../../../types";
import { units } from "../../TestHelpers";
import { approveToken, getAccountToken, getBalance } from "../utils/getAccountTokens";
import { getCurrentTick, getV3LpBalances, mintLpAsUser, UniV3LpMintSettings } from "../utils/uniswapv3Utils";
import { utils } from "../utils/utils";

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
    token0PriceInUSD: number;
    token1PriceInUSD: number;
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

    describe.only("Pricing is manipulation resistant", () => {
      [bothSupportedNonStablePair].forEach((pair) => {
        it(`Using pair: ${pair.token0}-${pair.token1}`, async () => {
          // Mint Uniswap v3 LP
          const token0 = pair.token0;
          const token1 = pair.token1;
          const fee = pair.fee;
          const tick = await getCurrentTick(uniswapV3.factory, token0, token1, fee);
          const tickSpacing = fee / 50;
          const mintSettings: UniV3LpMintSettings = {
            token0,
            token1,
            fee,
            amount0: pair.amount0,
            amount1: pair.amount1,
            tickLower: tick - tickSpacing * 1000,
            tickUpper: tick + tickSpacing * 1000,
          };
          const token0BalanceBeforeLP = await getBalance(logicOwner.address, token0);
          const token1BalanceBeforeLP = await getBalance(logicOwner.address, token1);
          await mintLpAsUser(nonfungiblePositionManager, logicOwner, mintSettings);

          const costToMintToken0 = token0BalanceBeforeLP.sub(await getBalance(logicOwner.address, token0));
          const costToMintToken1 = token1BalanceBeforeLP.sub(await getBalance(logicOwner.address, token1));

          const price = (amount: BigNumber, decimals: number, price: number) => {
            return amount.mul(price).div(ethers.BigNumber.from(10).pow(decimals));
          };

          const priceLp0 = price(costToMintToken0, pair.token0Decimals, pair.token0PriceInUSD);
          console.log("Token0 amount0", pair.amount0.toString());
          console.log("Token0 actualc", costToMintToken0.toString());
          console.log("Token0 price$$", priceLp0.toString());

          const priceLp1 = price(costToMintToken1, pair.token1Decimals, pair.token1PriceInUSD);
          console.log("Token1 amount0", pair.amount1.toString());
          console.log("Token1 actualc", costToMintToken1.toString());
          console.log("Token1 price$$", priceLp1.toString());
          const lpCost = priceLp0.add(priceLp1);
          console.log("Total Cost", lpCost.toString());

          const swapRouter: IV3SwapRouter = await ethers.getContractAt("IV3SwapRouter", uniswapV3.router);
          const [token0Liquidity, _] = await getV3LpBalances(uniswapV3.factory, pair.token0, pair.token1, pair.fee);

          const LIQUIDITY_MULTIPLIER = 10;
          console.log("Getting one side of pair", LIQUIDITY_MULTIPLIER, "x", token0Liquidity.toString());
          const amountIn = token0Liquidity.mul(LIQUIDITY_MULTIPLIER);
          await getAccountToken(amountIn, logicOwner.address, pair.token0, pair.token0Slot);
          await approveToken(logicOwner, swapRouter.address, pair.token0, amountIn);

          console.log("Dumping one side of pair");
          await swapRouter.exactInputSingle({
            tokenIn: pair.token0,
            tokenOut: pair.token1,
            amountIn,
            amountOutMinimum: 0,
            fee: pair.fee,
            recipient: logicOwner.address,
            sqrtPriceLimitX96: 0,
          });

          expect(await nonfungiblePositionManager.balanceOf(logicOwner.address)).to.equal(1);
          const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(logicOwner.address, 0);
          const position = await nonfungiblePositionManager.positions(tokenId);

          const token0BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, token0);
          const token1BalanceBeforeDecreaseLP = await getBalance(logicOwner.address, token1);

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

          const returnedToUser0 = (await getBalance(logicOwner.address, token0)).sub(token0BalanceBeforeDecreaseLP);
          const returnedToUser1 = (await getBalance(logicOwner.address, token1)).sub(token1BalanceBeforeDecreaseLP);

          const returnedLp0 = price(returnedToUser0, pair.token0Decimals, pair.token0PriceInUSD);
          console.log("Token0 Returned", returnedToUser0.toString(), returnedLp0.toString());

          const returnedLp1 = price(returnedToUser1, pair.token1Decimals, pair.token1PriceInUSD);
          console.log("Token1 Returned", returnedToUser1.toString(), returnedLp1.toString());

          const totalReturned = returnedLp0.add(returnedLp1);
          console.log("Total Returned", totalReturned.toString());
          console.log("Cost:Return", lpCost.toString(), ":", totalReturned.toString());
          console.log("LPer Made money?", lpCost < totalReturned);
        }).timeout(30000);
      });
    });
  });
};
