import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { BigNumber } from "ethers";

import { checkAlmostSame, units } from "../../TestHelpers";
import { assets, assetsBalanceOfSlot, uniswapV3 } from "../../../config/chainData/polygon-data";
import {
  IERC20,
  IERC20__factory,
  IMulticall__factory,
  INonfungiblePositionManager,
  INonfungiblePositionManager__factory,
  IV3SwapRouter__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { createFund } from "../utils/createFund";
import { getAccountToken } from "../utils/getAccountTokens";
import { getCurrentTick, mintLpAsPool, mintLpAsUser, UniV3LpMintSettings } from "../utils/uniswapv3Utils";
import { getMinAmountOut } from "../utils/getMinAmountOut";
import { IDeployments } from "../utils/deployContracts";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

describe("Uniswap V3 LP Test", function () {
  let deployments: IDeployments;
  let USDC: IERC20, USDT: IERC20, WETH: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let nonfungiblePositionManager: INonfungiblePositionManager, tokenId: BigNumber;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager__factory.abi);
  const iMulticall = new ethers.utils.Interface(IMulticall__factory.abi);
  const iV3SwapRouter = new ethers.utils.Interface(IV3SwapRouter__factory.abi);

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();

    nonfungiblePositionManager = await ethers.getContractAt(
      "INonfungiblePositionManager",
      uniswapV3.nonfungiblePositionManager,
    );

    deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;
    WETH = deployments.assets.WETH;
    USDC = deployments.assets.USDC;
    USDT = deployments.assets.USDT;
  });

  beforeEach(async function () {
    const funds = await createFund(
      poolFactory,
      logicOwner,
      manager,
      [
        { asset: assets.usdc, isDeposit: true },
        { asset: assets.weth, isDeposit: true },
        { asset: assets.usdt, isDeposit: true },
      ],
      0, // 0% performance fee
    );
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    await getAccountToken(units(5), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    await USDC.approve(poolLogicProxy.address, units(10000, 6));
    await poolLogicProxy.deposit(assets.usdc, units(10000, 6));
    await WETH.approve(poolLogicProxy.address, units(5));
    await poolLogicProxy.deposit(assets.weth, units(5));

    let approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(10000, 6)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(5)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(10000, 6)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(5)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

    await poolFactory.setExitCooldown(0);
  });

  it("Can't mint position if nft position is not enabled", async () => {
    // try to mint before enabling nft position asset
    const token0 = assets.usdc;
    const token1 = assets.weth;
    const fee = 500;
    const tick = await getCurrentTick(token0, token1, fee);
    const tickSpacing = fee / 50;
    let mintSettings: UniV3LpMintSettings = {
      token0,
      token1,
      fee,
      amount0: units(2000, 6),
      amount1: units(1),
      tickLower: tick - tickSpacing,
      tickUpper: tick + tickSpacing,
    };
    await expect(mintLpAsPool(poolLogicProxy, manager, mintSettings)).to.revertedWith("asset not enabled in pool");
  });

  it("Can't mint position with unsupported assets", async () => {
    // try to mint before enabling nft position asset
    const token0 = assets.usdc;
    const token1 = assets.weth;
    const fee = 500;
    const tick = await getCurrentTick(token0, token1, fee);
    const tickSpacing = fee / 50;
    let mintSettings: UniV3LpMintSettings = {
      token0,
      token1,
      fee,
      amount0: units(2000, 6),
      amount1: units(1),
      tickLower: tick - tickSpacing,
      tickUpper: tick + tickSpacing,
    };
    await poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

    // try to mint with unsupported token0
    mintSettings.token0 = assets.miMatic;
    mintSettings.token1 = assets.usdc;
    await expect(mintLpAsPool(poolLogicProxy, manager, mintSettings)).to.revertedWith("unsupported asset: tokenA");

    // try to mint with unsupported token1
    mintSettings.token0 = assets.usdc;
    mintSettings.token1 = assets.miMatic;
    await expect(mintLpAsPool(poolLogicProxy, manager, mintSettings)).to.revertedWith("unsupported asset: tokenB");
  });

  it("Can't mint position with invalid receiver address", async () => {
    // try to mint before enabling nft position asset
    const token0 = assets.usdc;
    const token1 = assets.weth;
    const fee = 500;
    const tick = await getCurrentTick(token0, token1, fee);
    const tickSpacing = fee / 50;
    await poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

    // try to mint with wrong receiver
    const mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
      [
        token0,
        token1,
        fee,
        tick - tickSpacing,
        tick + tickSpacing,
        units(2000, 6),
        units(1),
        0,
        0,
        poolManagerLogicProxy.address,
        deadLine,
      ],
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, mintABI),
    ).to.revertedWith("recipient is not pool");
  });

  it("Can't mint more than 3 positions (check position count limit)", async () => {
    // try to mint before enabling nft position asset
    const token0 = assets.usdc;
    const token1 = assets.weth;
    const fee = 500;
    const tick = await getCurrentTick(token0, token1, fee);
    const tickSpacing = fee / 50;
    let mintSettings: UniV3LpMintSettings = {
      token0,
      token1,
      fee,
      amount0: units(2000, 6),
      amount1: units(1),
      tickLower: tick - tickSpacing,
      tickUpper: tick + tickSpacing,
    };
    await poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

    // mint USDC-WETH LP position of 2000 USDC and 1 WETH
    await mintLpAsPool(poolLogicProxy, manager, mintSettings);

    mintSettings.tickLower = tick - tickSpacing * 2;
    mintSettings.tickUpper = tick + tickSpacing * 2;
    await mintLpAsPool(poolLogicProxy, manager, mintSettings);

    mintSettings.tickLower = tick - tickSpacing * 3;
    mintSettings.tickUpper = tick + tickSpacing * 3;
    await mintLpAsPool(poolLogicProxy, manager, mintSettings);

    mintSettings.tickLower = tick - tickSpacing * 4;
    mintSettings.tickUpper = tick + tickSpacing * 4;
    await expect(mintLpAsPool(poolLogicProxy, manager, mintSettings)).to.revertedWith("too many uniswap v3 positions");
  });

  it("Should mint a position", async () => {
    // try to mint before enabling nft position asset
    const token0 = assets.usdc;
    const token1 = assets.weth;
    const fee = 500;
    const tick = await getCurrentTick(token0, token1, fee);
    const tickSpacing = fee / 50;
    let mintSettings: UniV3LpMintSettings = {
      token0,
      token1,
      fee,
      amount0: units(2000, 6),
      amount1: units(1),
      tickLower: tick - tickSpacing,
      tickUpper: tick + tickSpacing,
    };
    await poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

    // mint USDC-WETH LP position of 2000 USDC and 1 WETH
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    await mintLpAsPool(poolLogicProxy, manager, mintSettings);
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

    checkAlmostSame(totalFundValueAfter, totalFundValueBefore, 0.000001);
    expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(1);
  });

  describe("After position", () => {
    beforeEach(async () => {
      const token0 = assets.usdc;
      const token1 = assets.weth;
      const fee = 500;
      const tick = await getCurrentTick(token0, token1, fee);
      const tickSpacing = fee / 50;
      let mintSettings: UniV3LpMintSettings = {
        token0,
        token1,
        fee,
        amount0: units(2000, 6),
        amount1: units(1),
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };

      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);
      await mintLpAsPool(poolLogicProxy, manager, mintSettings);

      tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);
    });

    it("Should be able to increase liquidity", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);

      // increase USDC-WETH LP position by 2000 USDC and 1 WETH
      let increaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("increaseLiquidity", [
        [tokenId, units(2000, 6), units(1), 0, 0, deadLine],
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, increaseLiquidityABI);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);

      const positionAfter = await nonfungiblePositionManager.positions(tokenId);

      expect(positionBefore.liquidity).to.lt(positionAfter.liquidity);
    });

    it("Should be able to decrease liquidity", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);

      // decrease USDC-WETH LP position by 100%
      let decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);

      const positionAfter = await nonfungiblePositionManager.positions(tokenId);

      expect(positionAfter.liquidity).to.equal(0);
    });

    it("Fail to collect fees with wrong receiver", async () => {
      let collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolManagerLogicProxy.address, units(10000), units(10000)],
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI),
      ).to.revertedWith("recipient is not pool");
    });

    it("Should be able to collect", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      // decrease USDC-WETH LP position by 100%
      let decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

      const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolLogicProxy.address, units(10000), units(10000)],
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter.gt(usdcBalanceBefore) || wethBalanceAfter.gt(wethBalanceBefore)).to.true;
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);
    });

    it("fail to collect fee after disabling assets", async () => {
      await getAccountToken(ethers.constants.Zero, poolLogicProxy.address, assets.usdc, assetsBalanceOfSlot.usdc);
      await getAccountToken(ethers.constants.Zero, poolLogicProxy.address, assets.weth, assetsBalanceOfSlot.weth);

      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      // decrease USDC-WETH LP position by 100%
      let decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

      await poolManagerLogicProxy.connect(manager).changeAssets([], [WETH.address]);

      // try to collect fees with wrong receiver
      let collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolManagerLogicProxy.address, units(10000), units(10000)],
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI),
      ).to.revertedWith("unsupported asset: tokenB");

      await poolManagerLogicProxy.connect(manager).changeAssets([], [USDC.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI),
      ).to.revertedWith("unsupported asset: tokenA");
    });

    it("Should be able to burn", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      // decrease USDC-WETH LP position by 100%
      let decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

      let collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolLogicProxy.address, units(10000), units(10000)],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI);

      let burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, burnABI);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);

      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(0);
    });

    it("Should be able to multicall", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      // decrease USDC-WETH LP position by 100%
      let decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);

      let collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolLogicProxy.address, units(10000), units(10000)],
      ]);
      let wrongABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(10000, 6)]);

      let burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);

      // try multicall with bad transaction
      let multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, wrongABI, burnABI]]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, multicallABI),
      ).to.revertedWith("invalid transaction");

      multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, collectABI, burnABI]]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, multicallABI);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);

      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(0);
    });

    it("Should be able to withdraw", async () => {
      const sharesBefore = await poolLogicProxy.balanceOf(logicOwner.address);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const usdcBalanceBefore = await USDC.balanceOf(logicOwner.address);
      const wethBalanceBefore = await WETH.balanceOf(logicOwner.address);

      // First decrease half the liquidity and move it to the fees to ensure both liquidity and fees get withdrawn correctly
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      // decrease USDC-WETH LP position by 50%
      let decreaseLiquidityCalldata = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, ethers.BigNumber.from(positionBefore.liquidity).div(2), 0, 0, deadLine],
      ]);
      await poolLogicProxy
        .connect(manager)
        .execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityCalldata);
      const totalFundValueAfterDecreaseLiquidity = await poolManagerLogicProxy.totalFundValue();
      // Assert that fund value is unchanged
      checkAlmostSame(totalFundValueBefore, totalFundValueAfterDecreaseLiquidity, 0.000001);

      // Half 50% withdrawal from pool
      await poolLogicProxy.withdraw(sharesBefore.div(2));
      const sharesAfterHalfWithdrawal = await poolLogicProxy.balanceOf(logicOwner.address);
      const totalFundValueAfterHalfWithdrawal = await poolManagerLogicProxy.totalFundValue();

      checkAlmostSame(sharesAfterHalfWithdrawal, sharesBefore.div(2), 0.000001);
      checkAlmostSame(totalFundValueAfterHalfWithdrawal, totalFundValueBefore.div(2), 0.000001);
      expect(await USDC.balanceOf(logicOwner.address)).gt(usdcBalanceBefore);
      expect(await WETH.balanceOf(logicOwner.address)).gt(wethBalanceBefore);

      // Full 100% withdrawal from pool
      await poolLogicProxy.withdraw(sharesAfterHalfWithdrawal);
      const sharesAfterFullWithdrawal = await poolLogicProxy.balanceOf(logicOwner.address);
      const totalFundValueAfterFullWithdrawal = await poolManagerLogicProxy.totalFundValue();

      expect(sharesAfterFullWithdrawal).eq(0);
      expect(totalFundValueAfterFullWithdrawal).eq(0);
      expect(await USDC.balanceOf(logicOwner.address)).gt(usdcBalanceBefore);
      expect(await WETH.balanceOf(logicOwner.address)).gt(wethBalanceBefore);
    });
  });
});
