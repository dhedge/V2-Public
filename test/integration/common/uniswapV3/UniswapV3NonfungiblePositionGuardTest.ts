import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

import { checkAlmostSame, units } from "../../../testHelpers";
import {
  ERC20Asset,
  IERC20__factory,
  IMulticall__factory,
  INonfungiblePositionManager,
  INonfungiblePositionManager__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  UniswapV3NonfungiblePositionGuard,
} from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { getCurrentTick, mintLpAsPool, mintLpAsUser, UniV3LpMintSettings } from "../../utils/uniV3Utils";
import { deployContracts, IAssetSetting, IDeployments, NETWORK } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

interface IUniswapV3NonfungiblePositionGuardTestParameter {
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
    token0UnsupportedPair: {
      fee: number;
      token0: string;
      token1: string;
      amount0: BigNumber;
      amount1: BigNumber;
      token0Slot?: number;
      token1Slot?: number;
    };
    token1UnsupportedPair: {
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

export const uniswapV3NonfungiblePositionGuardTest = (params: IUniswapV3NonfungiblePositionGuardTestParameter) => {
  const { network, uniswapV3, pairs } = params;
  const { bothSupportedPair, token0UnsupportedPair, token1UnsupportedPair } = pairs;

  describe("Uniswap V3 LP Test", function () {
    let deployments: IDeployments;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let nonfungiblePositionManager: INonfungiblePositionManager, tokenId: BigNumber;
    let uniswapV3NonfungiblePositionGuard: UniswapV3NonfungiblePositionGuard;
    let testSupportedAsset: ERC20Asset;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iNonfungiblePositionManager = new ethers.utils.Interface(INonfungiblePositionManager__factory.abi);
    const iMulticall = new ethers.utils.Interface(IMulticall__factory.abi);

    before(async function () {
      [logicOwner, manager] = await ethers.getSigners();

      nonfungiblePositionManager = await ethers.getContractAt(
        "INonfungiblePositionManager",
        uniswapV3.nonfungiblePositionManager,
      );

      deployments = await deployContracts(network);
      poolFactory = deployments.poolFactory;

      const TestAsset = await ethers.getContractFactory("ERC20Asset");
      testSupportedAsset = await TestAsset.deploy("Test", "TST");
      await testSupportedAsset.deployed();

      const testAggregator: string = await deployments.assetHandler.priceAggregators(bothSupportedPair.token0);
      const testSupportedAssetSetting: IAssetSetting = {
        asset: testSupportedAsset.address,
        assetType: 0,
        aggregator: testAggregator, // any aggregator is ok for the test asset
      };
      await deployments.assetHandler.addAssets([testSupportedAssetSetting]);

      uniswapV3NonfungiblePositionGuard = await ethers.getContractAt(
        "UniswapV3NonfungiblePositionGuard",
        await poolFactory.getContractGuard(nonfungiblePositionManager.address),
      );
    });

    let snapId: string;

    afterEach(async () => {
      await utils.evmRestoreSnap(snapId);
    });
    beforeEach(async () => {
      snapId = await utils.evmTakeSnap();

      const funds = await createFund(
        poolFactory,
        logicOwner,
        manager,
        [
          { asset: bothSupportedPair.token0, isDeposit: true },
          { asset: bothSupportedPair.token1, isDeposit: true },
          { asset: testSupportedAsset.address, isDeposit: true },
        ],
        {
          performance: BigNumber.from("0"),
          management: BigNumber.from("0"),
        },
      );
      poolLogicProxy = funds.poolLogicProxy;
      poolManagerLogicProxy = funds.poolManagerLogicProxy;

      await getAccountToken(
        bothSupportedPair.amount0.mul(4),
        logicOwner.address,
        bothSupportedPair.token0,
        bothSupportedPair.token0Slot,
      );
      await getAccountToken(
        bothSupportedPair.amount1.mul(4),
        logicOwner.address,
        bothSupportedPair.token1,
        bothSupportedPair.token1Slot,
      );

      await getAccountToken(bothSupportedPair.amount0.mul(4), logicOwner.address, testSupportedAsset.address, 0);

      await (
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token0)
      ).approve(poolLogicProxy.address, bothSupportedPair.amount0.mul(4));
      await poolLogicProxy.deposit(bothSupportedPair.token0, bothSupportedPair.amount0.mul(4));
      await (
        await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token1)
      ).approve(poolLogicProxy.address, bothSupportedPair.amount1.mul(4));
      await poolLogicProxy.deposit(bothSupportedPair.token1, bothSupportedPair.amount1.mul(4));

      let approveABI = iERC20.encodeFunctionData("approve", [
        uniswapV3.nonfungiblePositionManager,
        bothSupportedPair.amount0.mul(4),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token0, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [
        uniswapV3.nonfungiblePositionManager,
        bothSupportedPair.amount1.mul(4),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token1, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, bothSupportedPair.amount0.mul(4)]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token0, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, bothSupportedPair.amount1.mul(4)]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token1, approveABI);
    });

    it("Can't mint position if nft position is not enabled", async () => {
      // try to mint before enabling nft position asset
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
      await expect(
        mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings),
      ).to.revertedWith("uniswap asset not enabled");
    });

    it("Can't mint position with unsupported assets", async () => {
      // try to mint before enabling nft position asset
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
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

      // try to mint with unsupported token0
      mintSettings.token0 = token0UnsupportedPair.token0;
      mintSettings.token1 = token0UnsupportedPair.token1;
      mintSettings.fee = token0UnsupportedPair.fee;
      mintSettings.amount0 = token0UnsupportedPair.amount0;
      mintSettings.amount1 = token0UnsupportedPair.amount1;
      await expect(
        mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings),
      ).to.revertedWith("unsupported asset: tokenA");

      // try to mint with unsupported token1
      mintSettings.token0 = token1UnsupportedPair.token0;
      mintSettings.token1 = token1UnsupportedPair.token1;
      mintSettings.fee = token1UnsupportedPair.fee;
      mintSettings.amount0 = token1UnsupportedPair.amount0;
      mintSettings.amount1 = token1UnsupportedPair.amount1;
      await expect(
        mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings),
      ).to.revertedWith("unsupported asset: tokenB");
    });

    it("Can't mint position with invalid receiver address", async () => {
      // try to mint before enabling nft position asset
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tick = await getCurrentTick(uniswapV3.factory, bothSupportedPair);
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
          bothSupportedPair.amount0,
          bothSupportedPair.amount1,
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

    it("Can't mint position in a pool with no liquidity", async () => {
      // try to mint before enabling nft position asset
      const token0 = testSupportedAsset.address; // supported asset with no liquidity
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tickSpacing = fee / 50;
      const mintSettings: UniV3LpMintSettings = {
        token0,
        token1,
        fee,
        amount0: bothSupportedPair.amount0,
        amount1: bothSupportedPair.amount1,
        tickLower: 0,
        tickUpper: tickSpacing,
      };
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

      await expect(mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings)).to
        .reverted;
    });

    it("Can't mint more than 3 positions (check position count limit)", async () => {
      // try to mint before enabling nft position asset
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
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

      // mint USDC-WETH LP position of 2000 USDC and 1 WETH
      await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings);

      mintSettings.tickLower = tick - tickSpacing * 2;
      mintSettings.tickUpper = tick + tickSpacing * 2;
      await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings);

      mintSettings.tickLower = tick - tickSpacing * 3;
      mintSettings.tickUpper = tick + tickSpacing * 3;
      await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings);

      mintSettings.tickLower = tick - tickSpacing * 4;
      mintSettings.tickUpper = tick + tickSpacing * 4;
      await expect(
        mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings),
      ).to.revertedWith("too many uniswap v3 positions");
    });

    it("Should mint a position", async () => {
      // try to mint before enabling nft position asset
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
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

      // mint USDC-WETH LP position of 2000 USDC and 1 WETH
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings);
      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

      checkAlmostSame(totalFundValueAfter, totalFundValueBefore, 0.000001);
      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(1);
    });

    describe("After position", () => {
      beforeEach(async () => {
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

        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);
        await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings);

        tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);
      });

      it("Should not be able to increase liquidity on other tokenId", async () => {
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
          tickUpper: tick + tickSpacing * 2,
        };

        // manager mints another position outside of the dhedge pool
        await mintLpAsUser(nonfungiblePositionManager, manager, mintSettings);
        const tokenIdByManager = await nonfungiblePositionManager.tokenOfOwnerByIndex(manager.address, 0);

        const positionBefore = await nonfungiblePositionManager.positions(tokenId);
        const managerPositionBefore = await nonfungiblePositionManager.positions(tokenIdByManager);

        // increase manager's own LP position
        const increaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("increaseLiquidity", [
          [tokenIdByManager, bothSupportedPair.amount0, bothSupportedPair.amount1, 0, 0, deadLine],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await expect(
          poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, increaseLiquidityABI),
        ).to.revertedWith("position is not in track");

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);
        const managerPositionAfter = await nonfungiblePositionManager.positions(tokenIdByManager);

        expect(managerPositionBefore.liquidity).to.eq(managerPositionAfter.liquidity);
        expect(positionBefore.liquidity).to.eq(positionAfter.liquidity);
        expect(await poolManagerLogicProxy.totalFundValue()).to.eq(totalFundValueBefore);
      });

      it("Should be able to increase liquidity", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        // increase USDC-WETH LP position by 2000 USDC and 1 WETH
        const increaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("increaseLiquidity", [
          [tokenId, bothSupportedPair.amount0, bothSupportedPair.amount1, 0, 0, deadLine],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await poolLogicProxy
          .connect(manager)
          .execTransaction(uniswapV3.nonfungiblePositionManager, increaseLiquidityABI);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);

        expect(positionBefore.liquidity).to.lt(positionAfter.liquidity);
      });

      it("Check price change after decreasing liquidity to zero (no collect)", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        // decrease USDC-WETH LP position by 100%
        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const tokenPriceBefore = await poolLogicProxy.tokenPrice();

        await poolLogicProxy
          .connect(manager)
          .execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);
        checkAlmostSame(await poolLogicProxy.tokenPrice(), tokenPriceBefore, 0.000001);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);

        expect(positionAfter.liquidity).to.equal(0);
      });

      it("Check withdraw after decreasing liquidity to zero (no collect)", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        // decrease USDC-WETH LP position by 100%
        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const tokenPriceBefore = await poolLogicProxy.tokenPrice();

        await poolLogicProxy
          .connect(manager)
          .execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);
        checkAlmostSame(await poolLogicProxy.tokenPrice(), tokenPriceBefore, 0.000001);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);
        expect(positionAfter.liquidity).to.equal(0);

        const usdcBalanceBefore = await (
          await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token0)
        ).balanceOf(logicOwner.address);
        const wethBalanceBefore = await (
          await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token1)
        ).balanceOf(logicOwner.address);

        await ethers.provider.send("evm_increaseTime", [86400]);

        // Full 100% withdrawal from pool
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        expect(await poolLogicProxy.balanceOf(logicOwner.address)).to.eq(0);
        expect(await poolManagerLogicProxy.totalFundValue()).to.eq(0);

        expect(
          await (
            await ethers.getContractAt(
              "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
              bothSupportedPair.token0,
            )
          ).balanceOf(logicOwner.address),
        ).closeTo(usdcBalanceBefore.add(bothSupportedPair.amount0.mul(4)), 1);
        expect(
          await (
            await ethers.getContractAt(
              "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
              bothSupportedPair.token1,
            )
          ).balanceOf(logicOwner.address),
        ).closeTo(wethBalanceBefore.add(bothSupportedPair.amount1.mul(4)), 1);
      });

      it("Fail to collect fees with wrong receiver", async () => {
        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolManagerLogicProxy.address, units(10000), units(10000)],
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI),
        ).to.revertedWith("recipient is not pool");
      });

      it("Should be able to collect", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);
        // decrease USDC-WETH LP position by 100%
        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);
        await poolLogicProxy
          .connect(manager)
          .execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolLogicProxy.address, units(10000), units(10000)],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const usdcBalanceBefore = await (
          await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token0)
        ).balanceOf(poolLogicProxy.address);
        const wethBalanceBefore = await (
          await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token1)
        ).balanceOf(poolLogicProxy.address);

        await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI);

        const usdcBalanceAfter = await (
          await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token0)
        ).balanceOf(poolLogicProxy.address);
        const wethBalanceAfter = await (
          await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token1)
        ).balanceOf(poolLogicProxy.address);
        expect(usdcBalanceAfter.gt(usdcBalanceBefore) || wethBalanceAfter.gt(wethBalanceBefore)).to.true;
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);
      });

      it("fail to collect fee after disabling assets", async () => {
        await getAccountToken(
          ethers.constants.Zero,
          poolLogicProxy.address,
          bothSupportedPair.token0,
          bothSupportedPair.token0Slot,
        );
        await getAccountToken(
          ethers.constants.Zero,
          poolLogicProxy.address,
          bothSupportedPair.token1,
          bothSupportedPair.token1Slot,
        );

        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: token0UnsupportedPair.token0,
              isDeposit: true,
            },
          ],
          [],
        );
        await poolManagerLogicProxy.connect(manager).changeAssets([], [bothSupportedPair.token1]);

        // try to collect fees with wrong receiver
        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolManagerLogicProxy.address, units(10000), units(10000)],
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI),
        ).to.revertedWith("unsupported asset: tokenB");

        await poolManagerLogicProxy.connect(manager).changeAssets([], [bothSupportedPair.token0]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI),
        ).to.revertedWith("unsupported asset: tokenA");
      });

      it("Should be able to burn", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);
        // decrease USDC-WETH LP position by 100%
        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);
        await poolLogicProxy
          .connect(manager)
          .execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityABI);

        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolLogicProxy.address, units(10000), units(10000)],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, collectABI);

        const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, burnABI);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.000001);

        expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(0);
      });

      it("Should be able to multicall", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);
        // decrease USDC-WETH LP position by 100%
        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);

        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolLogicProxy.address, units(10000), units(10000)],
        ]);
        const wrongABI = iERC20.encodeFunctionData("approve", [uniswapV3.nonfungiblePositionManager, units(10000, 6)]);

        const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);

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
        const usdcBalanceBefore = await (
          await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token0)
        ).balanceOf(logicOwner.address);
        const wethBalanceBefore = await (
          await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", bothSupportedPair.token1)
        ).balanceOf(logicOwner.address);

        // First decrease half the liquidity and move it to the fees to ensure both liquidity and fees get withdrawn correctly
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);
        // decrease USDC-WETH LP position by 50%
        const decreaseLiquidityCalldata = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, ethers.BigNumber.from(positionBefore.liquidity).div(2), 0, 0, deadLine],
        ]);
        await poolLogicProxy
          .connect(manager)
          .execTransaction(uniswapV3.nonfungiblePositionManager, decreaseLiquidityCalldata);
        const totalFundValueAfterDecreaseLiquidity = await poolManagerLogicProxy.totalFundValue();
        // Assert that fund value is unchanged
        checkAlmostSame(totalFundValueBefore, totalFundValueAfterDecreaseLiquidity, 0.000001);

        await ethers.provider.send("evm_increaseTime", [86400]);

        // Half 50% withdrawal from pool
        await poolLogicProxy.withdraw(sharesBefore.div(2));
        const sharesAfterHalfWithdrawal = await poolLogicProxy.balanceOf(logicOwner.address);
        const totalFundValueAfterHalfWithdrawal = await poolManagerLogicProxy.totalFundValue();

        checkAlmostSame(sharesAfterHalfWithdrawal, sharesBefore.div(2), 0.000001);
        checkAlmostSame(totalFundValueAfterHalfWithdrawal, totalFundValueBefore.div(2), 0.000001);
        expect(
          await (
            await ethers.getContractAt(
              "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
              bothSupportedPair.token0,
            )
          ).balanceOf(logicOwner.address),
        ).gt(usdcBalanceBefore);
        expect(
          await (
            await ethers.getContractAt(
              "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
              bothSupportedPair.token1,
            )
          ).balanceOf(logicOwner.address),
        ).gt(wethBalanceBefore);

        // Full 100% withdrawal from pool
        await poolLogicProxy.withdraw(sharesAfterHalfWithdrawal);
        const sharesAfterFullWithdrawal = await poolLogicProxy.balanceOf(logicOwner.address);
        const totalFundValueAfterFullWithdrawal = await poolManagerLogicProxy.totalFundValue();

        expect(sharesAfterFullWithdrawal).eq(0);
        expect(totalFundValueAfterFullWithdrawal).eq(0);
        expect(
          await (
            await ethers.getContractAt(
              "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
              bothSupportedPair.token0,
            )
          ).balanceOf(logicOwner.address),
        ).gt(usdcBalanceBefore);
        expect(
          await (
            await ethers.getContractAt(
              "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
              bothSupportedPair.token1,
            )
          ).balanceOf(logicOwner.address),
        ).gt(wethBalanceBefore);
      });
    });

    it("Mint a position & Check nft-tracker", async () => {
      // try to mint before enabling nft position asset
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
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

      // no tracked nft before mint
      expect(await uniswapV3NonfungiblePositionGuard.getOwnedTokenIds(poolLogicProxy.address)).to.deep.equal([]);

      await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings);
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

      // 1 tracked nft after mint
      expect(await uniswapV3NonfungiblePositionGuard.getOwnedTokenIds(poolLogicProxy.address)).to.deep.equal([tokenId]);
    });

    it("Burn a position & Check nft-tracker", async () => {
      // try to mint before enabling nft position asset
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
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

      await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings);
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

      // 1 tracked nft before burn
      expect(await uniswapV3NonfungiblePositionGuard.getOwnedTokenIds(poolLogicProxy.address)).to.deep.equal([tokenId]);

      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);
      const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolLogicProxy.address, units(10000), units(10000)],
      ]);
      const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);
      const multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, collectABI, burnABI]]);
      await poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, multicallABI);

      // no tracked nft after burn
      expect(await uniswapV3NonfungiblePositionGuard.getOwnedTokenIds(poolLogicProxy.address)).to.deep.equal([]);
    });

    it("Try mint & burn in one transaction", async () => {
      // try to mint before enabling nft position asset
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
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: false }], []);

      await mintLpAsPool(uniswapV3.nonfungiblePositionManager, poolLogicProxy, manager, mintSettings);
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

      // try to mint with wrong receiver
      const mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
        [
          token0,
          token1,
          fee,
          tick - tickSpacing,
          tick + tickSpacing,
          bothSupportedPair.amount0,
          bothSupportedPair.amount1,
          0,
          0,
          poolLogicProxy.address,
          deadLine,
        ],
      ]);
      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);
      const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolLogicProxy.address, units(10000), units(10000)],
      ]);
      const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);
      const multicallABI = iMulticall.encodeFunctionData("multicall", [
        [mintABI, decreaseLiquidityABI, collectABI, burnABI],
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(uniswapV3.nonfungiblePositionManager, multicallABI),
      ).to.revertedWith("invalid multicall");
    });

    it("shouldn't be able to deposit UniV3 position NFT to the pool", async () => {
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
      await mintLpAsUser(nonfungiblePositionManager, manager, mintSettings);

      // Make the NFT as a deposit asset.
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: uniswapV3.nonfungiblePositionManager, isDeposit: true }], []);

      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(manager.address, 0);
      await nonfungiblePositionManager.connect(manager).approve(poolLogicProxy.address, tokenId);

      // Deposit the NFT to the pool.
      await expect(
        poolLogicProxy.connect(manager).deposit(uniswapV3.nonfungiblePositionManager, tokenId),
      ).to.be.revertedWith("NFTs not supported");
    });
  });
};
