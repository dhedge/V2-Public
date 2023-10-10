import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";

import { DhedgeUniV3V2Router } from "../../../types";
import { IERC20 } from "../../../types";
import { checkAlmostSame, units } from "../../testHelpers";
import { getAccountToken } from "../utils/getAccountTokens";

import { polygonChainData } from "../../../config/chainData/polygonData";
import { utils } from "../utils/utils";
const { assets, assetsBalanceOfSlot, uniswapV3 } = polygonChainData;

describe("DhedgeUniV3V2Router", () => {
  const swapUSDC = units(100, 6);
  const swapDAI = units(100);
  let logicOwner: SignerWithAddress;
  let USDC: IERC20, DAI: IERC20, WETH: IERC20, AGEUR: IERC20;
  let swapRouter: DhedgeUniV3V2Router;

  before(async () => {
    USDC = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);
    DAI = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
    WETH = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.weth);
    AGEUR = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.agEur);
  });

  let snapId: string;
  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();

    [logicOwner] = await ethers.getSigners();
    await getAccountToken(swapUSDC.mul(10), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    const SwapRouter = await ethers.getContractFactory("DhedgeUniV3V2Router");
    swapRouter = await SwapRouter.deploy(uniswapV3.factory, uniswapV3.router);
    await swapRouter.deployed();
  });

  it("getAmountsOut", async () => {
    checkAlmostSame((await swapRouter.getAmountsOut(swapUSDC, [assets.usdc, assets.weth, assets.dai]))[2], swapDAI);
  });

  it("swapExactTokensForTokens", async () => {
    await USDC.approve(swapRouter.address, swapUSDC);
    const receiver = ethers.Wallet.createRandom().address;
    await swapRouter.swapExactTokensForTokens(
      swapUSDC,
      0,
      [assets.usdc, assets.weth, assets.dai],
      receiver,
      Math.floor(Date.now() / 1000 + 100000000),
    );
    checkAlmostSame(await DAI.balanceOf(receiver), swapDAI);
  });

  it("handles multi swap", async () => {
    const wethAmount = units(1);
    await getAccountToken(wethAmount, logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
    await WETH.approve(swapRouter.address, wethAmount);

    await swapRouter.swapExactTokensForTokens(
      wethAmount,
      0,
      [assets.weth, assets.usdc, assets.agEur],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );
    const agEurBalance = await AGEUR.balanceOf(logicOwner.address);
    await AGEUR.approve(swapRouter.address, agEurBalance);
    await swapRouter.swapExactTokensForTokens(
      agEurBalance,
      0,
      [assets.agEur, assets.usdc, assets.weth],
      logicOwner.address,
      Math.floor(Date.now() / 1000 + 100000000),
    );

    expect(await WETH.balanceOf(logicOwner.address)).to.be.closeTo(wethAmount, wethAmount.div(100));
  });

  it("getAmountsIn", async () => {
    checkAlmostSame((await swapRouter.getAmountsIn(swapDAI, [assets.usdc, assets.weth, assets.dai]))[0], swapUSDC);
  });

  it("swapTokensForExactTokens", async () => {
    await USDC.approve(swapRouter.address, swapUSDC.mul(2));

    const usdcBalanceBefore = await USDC.balanceOf(logicOwner.address);

    const receiver = ethers.Wallet.createRandom().address;
    await swapRouter.swapTokensForExactTokens(
      swapDAI,
      swapUSDC.mul(2),
      [assets.usdc, assets.weth, assets.dai],
      receiver,
      Math.floor(Date.now() / 1000 + 100000000),
    );

    expect(await DAI.balanceOf(receiver)).to.equal(swapDAI);
    checkAlmostSame(usdcBalanceBefore.sub(await USDC.balanceOf(logicOwner.address)), swapUSDC);
  });
});
