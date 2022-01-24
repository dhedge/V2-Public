import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { checkAlmostSame, units } from "../../TestHelpers";
import {
  ZERO_ADDRESS,
  sushi,
  aave,
  assets,
  assetsBalanceOfSlot,
  uniswapV3,
} from "../../../config/chainData/polygon-data";
import {
  IAaveIncentivesController__factory,
  IERC20,
  IERC20__factory,
  ILendingPool__factory,
  IMulticall__factory,
  INonfungiblePositionManager,
  INonfungiblePositionManager__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { createFund } from "../utils/createFund";
import { getAccountToken } from "../utils/getAccountTokens";
import { BigNumber } from "ethers";

use(solidity);

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

describe("Uniswap V3 LP Test", function () {
  let USDC: IERC20, WETH: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress, user: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let nonfungiblePositionManager: INonfungiblePositionManager, tokenId: BigNumber;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager__factory.abi);
  const iMulticall = new ethers.utils.Interface(IMulticall__factory.abi);

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    nonfungiblePositionManager = await ethers.getContractAt(
      "INonfungiblePositionManager",
      uniswapV3.nonfungiblePositionManager,
    );

    const deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;
    WETH = deployments.assets.WETH;
    USDC = deployments.assets.USDC;
  });

  beforeEach(async function () {
    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    await getAccountToken(units(5), logicOwner.address, assets.weth, assetsBalanceOfSlot.weth);
    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    await USDC.approve(poolLogicProxy.address, units(10000, 6));
    await poolLogicProxy.deposit(assets.usdc, units(10000, 6));
    await WETH.approve(poolLogicProxy.address, units(5));
    await poolLogicProxy.deposit(assets.weth, units(5));

    // Approve to swap 100 USDC
    let approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(10000, 6)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);

    // Approve to swap 1 WETH
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(5)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.weth, approveABI);

    await poolFactory.setExitCooldown(0);
  });

  it("Should be able to add liquidity", async () => {
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

    await expect(
      poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, mintABI),
    ).to.revertedWith("asset not enabled in pool");

    // add supported assets
    await poolManagerLogicProxy
      .connect(manager)
      .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, mintABI);

    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

    expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(1);
  });

  describe("After position", () => {
    beforeEach(async () => {
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
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);
      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, mintABI);

      tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);
    });

    it("Should be able to increase liquidity", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);

      let increaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("increaseLiquidity", [
        [tokenId, units(2000, 6), units(1), 0, 0, deadLine],
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, increaseLiquidityABI);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      const positionAfter = await nonfungiblePositionManager.positions(tokenId);

      expect(positionBefore.liquidity).to.lt(positionAfter.liquidity);
    });

    it("Should be able to decrease liquidity", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);

      let decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      const positionAfter = await nonfungiblePositionManager.positions(tokenId);

      expect(positionAfter.liquidity).to.equal(0);
    });

    it("Should be able to collect", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      let decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

      let collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolLogicProxy.address, units(10000), units(10000)],
      ]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      const wethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      expect(usdcBalanceAfter.gt(usdcBalanceBefore) || wethBalanceAfter.gt(wethBalanceBefore)).to.true;
      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    });

    it("Should be able to burn", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
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

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(0);
    });

    it("Should be able to multicall", async () => {
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      let decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);

      let collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolLogicProxy.address, units(10000), units(10000)],
      ]);

      let burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);

      let multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, collectABI, burnABI]]);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, multicallABI);

      checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(0);
    });
  });
});
