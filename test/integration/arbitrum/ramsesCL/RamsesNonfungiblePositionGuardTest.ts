import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";

import { checkAlmostSame, units } from "../../../testHelpers";
import {
  ERC20Asset,
  IERC20,
  IERC20__factory,
  IMulticall__factory,
  IRamsesNonfungiblePositionManager__factory,
  IRamsesNonfungiblePositionManager,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  RamsesNonfungiblePositionGuard,
  IRamsesGaugeV2,
} from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { getCurrentTick } from "../../utils/uniV3Utils";
import { mintLpAsPool, mintLpAsUser, RamsesCLMintSettings } from "../../utils/ramsesCLUtils";
import { utils } from "../../utils/utils";
import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { IRamsesCLTestParams, deployRamsesCLInfrastructure } from "./deploymentTestHelpers";

const deadLine = Math.floor(Date.now() / 1000 + 100000000);

export const ramsesCLNonfungiblePositionGuardTest = (testParams: IRamsesCLTestParams) => {
  const { pairs, factory } = testParams;
  const { bothSupportedPair, token0UnsupportedPair, token1UnsupportedPair } = pairs;

  describe("Ramses CL Nonfungible Position Test", function () {
    let deployments: IBackboneDeployments;
    let logicOwner: SignerWithAddress, manager: SignerWithAddress;
    let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let tokenId: BigNumber;
    let ramsesNonfungiblePositionGuard: RamsesNonfungiblePositionGuard;
    let nonfungiblePositionManager: IRamsesNonfungiblePositionManager;
    let testSupportedAsset: ERC20Asset;
    let token0: IERC20;
    let token1: IERC20;
    let gauge: IRamsesGaugeV2;
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const iNonfungiblePositionManager = new ethers.utils.Interface(IRamsesNonfungiblePositionManager__factory.abi);
    const iMulticall = new ethers.utils.Interface(IMulticall__factory.abi);

    utils.beforeAfterReset(beforeEach, afterEach);

    before(async () => {
      deployments = await deployBackboneContracts(testParams);

      manager = deployments.manager;
      logicOwner = deployments.owner;
      poolFactory = deployments.poolFactory;

      ({ nonfungiblePositionManager, testSupportedAsset, ramsesNonfungiblePositionGuard, gauge } =
        await deployRamsesCLInfrastructure(deployments, testParams));
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

      await getAccountToken(bothSupportedPair.amount0, logicOwner.address, testSupportedAsset.address, 0);

      token0 = await ethers.getContractAt("IERC20", bothSupportedPair.token0);
      token1 = await ethers.getContractAt("IERC20", bothSupportedPair.token1);
      await token0.approve(poolLogicProxy.address, bothSupportedPair.amount0.mul(4));
      await poolLogicProxy.deposit(bothSupportedPair.token0, bothSupportedPair.amount0.mul(4));

      await token1.approve(poolLogicProxy.address, bothSupportedPair.amount1.mul(4));
      await poolLogicProxy.deposit(bothSupportedPair.token1, bothSupportedPair.amount1.mul(4));
      let approveABI = iERC20.encodeFunctionData("approve", [
        nonfungiblePositionManager.address,
        bothSupportedPair.amount0.mul(4),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token0, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [
        nonfungiblePositionManager.address,
        bothSupportedPair.amount1.mul(4),
      ]);
      await poolLogicProxy.connect(manager).execTransaction(bothSupportedPair.token1, approveABI);
    });

    it("Can't mint position if nft position is not enabled", async () => {
      // try to mint before enabling nft position asset
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);
      const mintSettings: RamsesCLMintSettings = {
        token0,
        token1,
        fee,
        amount0: bothSupportedPair.amount0,
        amount1: bothSupportedPair.amount1,
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await expect(
        mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings),
      ).to.revertedWith("ramses cl asset not enabled");
    });

    it("Can't mint position with unsupported assets", async function () {
      if (!token0UnsupportedPair || !token1UnsupportedPair) this.skip();
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);
      const mintSettings: RamsesCLMintSettings = {
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
        .changeAssets([{ asset: nonfungiblePositionManager.address, isDeposit: false }], []);

      // try to mint with unsupported token0
      mintSettings.token0 = token0UnsupportedPair.token0;
      mintSettings.token1 = token0UnsupportedPair.token1;
      mintSettings.fee = token0UnsupportedPair.fee;
      mintSettings.amount0 = token0UnsupportedPair.amount0;
      mintSettings.amount1 = token0UnsupportedPair.amount1;
      await expect(
        mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings),
      ).to.revertedWith("unsupported asset: tokenA");

      // try to mint with unsupported token1
      mintSettings.token0 = token1UnsupportedPair.token0;
      mintSettings.token1 = token1UnsupportedPair.token1;
      mintSettings.fee = token1UnsupportedPair.fee;
      mintSettings.amount0 = token1UnsupportedPair.amount0;
      mintSettings.amount1 = token1UnsupportedPair.amount1;
      await expect(
        mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings),
      ).to.revertedWith("unsupported asset: tokenB");
    });

    it("Can't mint position with invalid receiver address", async () => {
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: nonfungiblePositionManager.address, isDeposit: false }], []);

      // try to mint with wrong receiver
      const mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
        [
          token0,
          token1,
          tickSpacing,
          tick - tickSpacing,
          tick + tickSpacing,
          bothSupportedPair.amount0,
          bothSupportedPair.amount1,
          0,
          0,
          poolManagerLogicProxy.address,
          deadLine,
          0,
        ],
      ]);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, mintABI),
      ).to.revertedWith("recipient is not pool");
    });

    it("Can't mint position without enabling the vaild reward asset(s)", async () => {
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);

      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: nonfungiblePositionManager.address, isDeposit: false }], []);

      const mintSettings: RamsesCLMintSettings = {
        token0,
        token1,
        fee,
        amount0: bothSupportedPair.amount0,
        amount1: bothSupportedPair.amount1,
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await expect(
        mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings),
      ).to.revertedWith("reward asset not enabled");
    });

    it("Can't mint more than 3 positions (check position count limit)", async () => {
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);
      const mintSettings: RamsesCLMintSettings = {
        token0,
        token1,
        fee,
        amount0: bothSupportedPair.amount0,
        amount1: bothSupportedPair.amount1,
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: nonfungiblePositionManager.address, isDeposit: false }, //enable cl nft asset
          ...testParams.rewardTokenSettings.map(({ rewardToken }) => ({ asset: rewardToken, isDeposit: false })), // enable reward assets
        ],
        [],
      );

      await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);

      mintSettings.tickLower = tick - tickSpacing * 2;
      mintSettings.tickUpper = tick + tickSpacing * 2;
      await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);

      mintSettings.tickLower = tick - tickSpacing * 3;
      mintSettings.tickUpper = tick + tickSpacing * 3;
      await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);

      mintSettings.tickLower = tick - tickSpacing * 4;
      mintSettings.tickUpper = tick + tickSpacing * 4;
      await expect(
        mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings),
      ).to.revertedWith("max position reached");
    });

    it("Should mint a position", async () => {
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);
      const mintSettings: RamsesCLMintSettings = {
        token0,
        token1,
        fee,
        amount0: bothSupportedPair.amount0,
        amount1: bothSupportedPair.amount1,
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: nonfungiblePositionManager.address, isDeposit: false }, //enable cl nft asset
          ...testParams.rewardTokenSettings.map(({ rewardToken }) => ({ asset: rewardToken, isDeposit: false })), // enable reward assets
        ],
        [],
      );

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);
      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

      checkAlmostSame(totalFundValueAfter, totalFundValueBefore, 0.000001);
      expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(1);
    });

    it("Mint a position & Check nft-tracker", async () => {
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);
      const mintSettings: RamsesCLMintSettings = {
        token0,
        token1,
        fee,
        amount0: bothSupportedPair.amount0,
        amount1: bothSupportedPair.amount1,
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: nonfungiblePositionManager.address, isDeposit: false }, //enable cl nft asset
          ...testParams.rewardTokenSettings.map(({ rewardToken }) => ({ asset: rewardToken, isDeposit: false })), // enable reward assets
        ],
        [],
      );
      // no tracked nft before mint
      expect(await ramsesNonfungiblePositionGuard.getOwnedTokenIds(poolLogicProxy.address)).to.deep.equal([]);

      await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

      // 1 tracked nft after mint
      expect(await ramsesNonfungiblePositionGuard.getOwnedTokenIds(poolLogicProxy.address)).to.deep.equal([tokenId]);
    });

    it("Burn a position & Check nft-tracker", async () => {
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);
      const mintSettings: RamsesCLMintSettings = {
        token0,
        token1,
        fee,
        amount0: bothSupportedPair.amount0,
        amount1: bothSupportedPair.amount1,
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: nonfungiblePositionManager.address, isDeposit: false }, //enable cl nft asset
          ...testParams.rewardTokenSettings.map(({ rewardToken }) => ({ asset: rewardToken, isDeposit: false })), // enable reward assets
        ],
        [],
      );

      await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

      // 1 tracked nft before burn
      expect(await ramsesNonfungiblePositionGuard.getOwnedTokenIds(poolLogicProxy.address)).to.deep.equal([tokenId]);

      const positionBefore = await nonfungiblePositionManager.positions(tokenId);
      const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
        [tokenId, positionBefore.liquidity, 0, 0, deadLine],
      ]);
      const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
        [tokenId, poolLogicProxy.address, units(10000), units(10000)],
      ]);
      const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);
      const multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, collectABI, burnABI]]);
      await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, multicallABI);

      // no tracked nft after burn
      expect(await ramsesNonfungiblePositionGuard.getOwnedTokenIds(poolLogicProxy.address)).to.deep.equal([]);
    });

    it("Try mint & burn in one transaction", async () => {
      const token0 = bothSupportedPair.token0;
      const token1 = bothSupportedPair.token1;
      const fee = bothSupportedPair.fee;
      const tickSpacing = bothSupportedPair.tickSpacing;
      const tick = await getCurrentTick(factory, bothSupportedPair);

      const mintSettings: RamsesCLMintSettings = {
        token0,
        token1,
        fee,
        amount0: bothSupportedPair.amount0,
        amount1: bothSupportedPair.amount1,
        tickLower: tick - tickSpacing,
        tickUpper: tick + tickSpacing,
      };
      await poolManagerLogicProxy.connect(manager).changeAssets(
        [
          { asset: nonfungiblePositionManager.address, isDeposit: false }, //enable cl nft asset
          ...testParams.rewardTokenSettings.map(({ rewardToken }) => ({ asset: rewardToken, isDeposit: false })), // enable reward assets
        ],
        [],
      );

      await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);
      const tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

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
          0,
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
        poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, multicallABI),
      ).to.revertedWith("invalid multicall");
    });

    describe("After position", () => {
      before(async () => {
        const token0 = bothSupportedPair.token0;
        const token1 = bothSupportedPair.token1;
        const fee = bothSupportedPair.fee;
        const tickSpacing = bothSupportedPair.tickSpacing;
        const tick = await getCurrentTick(factory, bothSupportedPair);
        const mintSettings: RamsesCLMintSettings = {
          token0,
          token1,
          fee,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing,
          tickUpper: tick + tickSpacing,
        };

        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            { asset: nonfungiblePositionManager.address, isDeposit: false }, //enable cl nft asset
            ...testParams.rewardTokenSettings.map(({ rewardToken }) => ({ asset: rewardToken, isDeposit: false })), // enable reward assets
          ],
          [],
        );
        await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);

        tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);
      });

      it("Should not be able to increase liquidity on other tokenId", async () => {
        const token0 = bothSupportedPair.token0;
        const token1 = bothSupportedPair.token1;
        const fee = bothSupportedPair.fee;
        const tickSpacing = bothSupportedPair.tickSpacing;
        const tick = await getCurrentTick(factory, bothSupportedPair);
        const mintSettings: RamsesCLMintSettings = {
          token0,
          token1,
          fee,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing * 2,
          tickUpper: tick + tickSpacing * 2,
        };

        // manager mints another position outside of the dhedge pool
        await mintLpAsUser(nonfungiblePositionManager, manager, mintSettings, [
          bothSupportedPair.token0Slot,
          bothSupportedPair.token1Slot,
        ]);
        const tokenIdByManager = await nonfungiblePositionManager.tokenOfOwnerByIndex(manager.address, 0);

        const positionBefore = await nonfungiblePositionManager.positions(tokenId);
        const managerPositionBefore = await nonfungiblePositionManager.positions(tokenIdByManager);

        // increase manager's own LP position
        const increaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("increaseLiquidity", [
          [tokenIdByManager, bothSupportedPair.amount0, bothSupportedPair.amount1, 0, 0, deadLine],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await expect(
          poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, increaseLiquidityABI),
        ).to.revertedWith("position is not in track");

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);
        const managerPositionAfter = await nonfungiblePositionManager.positions(tokenIdByManager);

        expect(managerPositionBefore.liquidity).to.eq(managerPositionAfter.liquidity);
        expect(positionBefore.liquidity).to.eq(positionAfter.liquidity);
        expect(await poolManagerLogicProxy.totalFundValue()).to.eq(totalFundValueBefore);
      });

      it("Should be able to increase liquidity", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const increaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("increaseLiquidity", [
          [tokenId, bothSupportedPair.amount0, bothSupportedPair.amount1, 0, 0, deadLine],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, increaseLiquidityABI);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00005);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);

        expect(positionBefore.liquidity).to.lt(positionAfter.liquidity);
      });

      it("Check price change after decreasing liquidity to zero (no collect)", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const tokenPriceBefore = await poolLogicProxy.tokenPrice();

        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, decreaseLiquidityABI);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00005);
        checkAlmostSame(await poolLogicProxy.tokenPrice(), tokenPriceBefore, 0.000001);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);

        expect(positionAfter.liquidity).to.equal(0);
      });

      it("Check withdraw after decreasing liquidity to zero (no collect)", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const tokenPriceBefore = await poolLogicProxy.tokenPrice();

        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, decreaseLiquidityABI);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00005);
        checkAlmostSame(await poolLogicProxy.tokenPrice(), tokenPriceBefore, 0.000001);

        const positionAfter = await nonfungiblePositionManager.positions(tokenId);
        expect(positionAfter.liquidity).to.equal(0);

        const token0BalanceBefore = await token0.balanceOf(logicOwner.address);
        const token1BalanceBefore = await token1.balanceOf(logicOwner.address);

        await ethers.provider.send("evm_increaseTime", [86400]);

        // Full 100% withdrawal from pool
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        expect(await poolLogicProxy.balanceOf(logicOwner.address)).to.eq(0);
        expect(await poolManagerLogicProxy.totalFundValue()).to.eq(0);

        expect(await token0.balanceOf(logicOwner.address)).closeTo(
          token0BalanceBefore.add(bothSupportedPair.amount0.mul(4)),
          1,
        );
        expect(await token1.balanceOf(logicOwner.address)).closeTo(
          token1BalanceBefore.add(bothSupportedPair.amount1.mul(4)),
          1,
        );
      });

      it("Fail to collect fees with wrong receiver", async () => {
        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolManagerLogicProxy.address, units(10000), units(10000)],
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, collectABI),
        ).to.revertedWith("recipient is not pool");
      });

      it("Should be able to collect", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, decreaseLiquidityABI);

        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolLogicProxy.address, units(10000), units(10000)],
        ]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const token0BalanceBefore = await token0.balanceOf(poolLogicProxy.address);
        const token1BalanceBefore = await token1.balanceOf(poolLogicProxy.address);

        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, collectABI);

        const token0BalanceAfter = await token0.balanceOf(poolLogicProxy.address);
        const token1BalanceAfter = await token1.balanceOf(poolLogicProxy.address);
        expect(token0BalanceAfter.gt(token0BalanceBefore) || token1BalanceAfter.gt(token1BalanceBefore)).to.true;
        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00005);
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

        await poolManagerLogicProxy.connect(manager).changeAssets([], [bothSupportedPair.token1]);

        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolManagerLogicProxy.address, units(10000), units(10000)],
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, collectABI),
        ).to.revertedWith("unsupported asset: tokenB");

        await poolManagerLogicProxy.connect(manager).changeAssets([], [bothSupportedPair.token0]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, collectABI),
        ).to.revertedWith("unsupported asset: tokenA");
      });

      it("Should be able to burn", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, decreaseLiquidityABI);

        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolLogicProxy.address, units(10000), units(10000)],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, collectABI);

        const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, burnABI);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00005);

        expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(0);
      });

      it("Should be able to multicall", async () => {
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const decreaseLiquidityABI = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, positionBefore.liquidity, 0, 0, deadLine],
        ]);

        const collectABI = iNonfungiblePositionManager.encodeFunctionData("collect", [
          [tokenId, poolLogicProxy.address, units(10000), units(10000)],
        ]);
        const wrongABI = iERC20.encodeFunctionData("approve", [nonfungiblePositionManager.address, units(10000, 6)]);

        const burnABI = iNonfungiblePositionManager.encodeFunctionData("burn", [tokenId]);

        // try multicall with bad transaction
        let multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, wrongABI, burnABI]]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, multicallABI),
        ).to.revertedWith("invalid transaction");

        multicallABI = iMulticall.encodeFunctionData("multicall", [[decreaseLiquidityABI, collectABI, burnABI]]);

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, multicallABI);

        checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore, 0.00005);

        expect(await nonfungiblePositionManager.balanceOf(poolLogicProxy.address)).to.equal(0);
      });

      it("Should be able to withdraw", async () => {
        const sharesBefore = await poolLogicProxy.balanceOf(logicOwner.address);
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const token0BalanceBefore = await token0.balanceOf(logicOwner.address);
        const token1BalanceBefore = await token1.balanceOf(logicOwner.address);

        // First decrease half the liquidity and move it to the fees to ensure both liquidity and fees get withdrawn correctly
        const positionBefore = await nonfungiblePositionManager.positions(tokenId);

        const decreaseLiquidityCalldata = iNonfungiblePositionManager.encodeFunctionData("decreaseLiquidity", [
          [tokenId, ethers.BigNumber.from(positionBefore.liquidity).div(2), 0, 0, deadLine],
        ]);
        await poolLogicProxy
          .connect(manager)
          .execTransaction(nonfungiblePositionManager.address, decreaseLiquidityCalldata);
        const totalFundValueAfterDecreaseLiquidity = await poolManagerLogicProxy.totalFundValue();
        // Assert that fund value is unchanged
        checkAlmostSame(totalFundValueBefore, totalFundValueAfterDecreaseLiquidity, 0.00001);

        await ethers.provider.send("evm_increaseTime", [86400]);

        // Half 50% withdrawal from pool
        await poolLogicProxy.withdraw(sharesBefore.div(2));
        const sharesAfterHalfWithdrawal = await poolLogicProxy.balanceOf(logicOwner.address);
        const totalFundValueAfterHalfWithdrawal = await poolManagerLogicProxy.totalFundValue();

        console.log("totalFundValueAfterHalfWithdrawal", totalFundValueAfterHalfWithdrawal);
        console.log("totalFundValueBefore.div(2)", totalFundValueBefore.div(2));
        checkAlmostSame(sharesAfterHalfWithdrawal, sharesBefore.div(2), 0.000001);
        checkAlmostSame(totalFundValueAfterHalfWithdrawal, totalFundValueBefore.div(2), 0.005);

        expect(await token0.balanceOf(logicOwner.address)).gt(token0BalanceBefore);
        expect(await token1.balanceOf(logicOwner.address)).gt(token1BalanceBefore);

        // Full 100% withdrawal from pool
        await poolLogicProxy.withdraw(sharesAfterHalfWithdrawal);
        const sharesAfterFullWithdrawal = await poolLogicProxy.balanceOf(logicOwner.address);
        const totalFundValueAfterFullWithdrawal = await poolManagerLogicProxy.totalFundValue();

        expect(sharesAfterFullWithdrawal).eq(0);
        expect(totalFundValueAfterFullWithdrawal).eq(0);
        expect(await token0.balanceOf(logicOwner.address)).gt(token0BalanceBefore);
        expect(await token1.balanceOf(logicOwner.address)).gt(token1BalanceBefore);
      });
    });

    describe("getReward", () => {
      before(async () => {
        const token0 = bothSupportedPair.token0;
        const token1 = bothSupportedPair.token1;
        const fee = bothSupportedPair.fee;
        const tickSpacing = bothSupportedPair.tickSpacing;
        const tick = await getCurrentTick(factory, bothSupportedPair);
        const mintSettings: RamsesCLMintSettings = {
          token0,
          token1,
          fee,
          amount0: bothSupportedPair.amount0,
          amount1: bothSupportedPair.amount1,
          tickLower: tick - tickSpacing,
          tickUpper: tick + tickSpacing,
        };
        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            { asset: nonfungiblePositionManager.address, isDeposit: false }, //enable cl nft asset
            ...testParams.rewardTokenSettings.map(({ rewardToken }) => ({ asset: rewardToken, isDeposit: false })), // enable reward assets
          ],
          [],
        );

        await mintLpAsPool(nonfungiblePositionManager.address, poolLogicProxy, manager, mintSettings);
        tokenId = await nonfungiblePositionManager.tokenOfOwnerByIndex(poolLogicProxy.address, 0);

        // increase time by 1 day
        await ethers.provider.send("evm_increaseTime", [3600 * 24]);
        await ethers.provider.send("evm_mine", []);
      });

      it("Reverts if invalid token id", async () => {
        const rewardTokens = await gauge.getRewardTokens();
        const claimTx = iNonfungiblePositionManager.encodeFunctionData("getReward", [1234, rewardTokens]);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, claimTx),
        ).to.revertedWith("position is not in track");
      });

      it("Allow claim", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const rewardTokens = await gauge.getRewardTokens();

        const claimTx = iNonfungiblePositionManager.encodeFunctionData("getReward", [tokenId, rewardTokens]);
        poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager.address, claimTx);
        checkAlmostSame(totalFundValueBefore, await poolManagerLogicProxy.totalFundValue(), 0.0001);

        const rewardTokensInfo = await Promise.all(
          rewardTokens.map(async (rewardToken) => {
            const tokenContract = await ethers.getContractAt("ERC20", rewardToken);
            const balance = await tokenContract.balanceOf(poolLogicProxy.address);
            const symbol = await tokenContract.symbol();
            console.log(`Reward token ${symbol} balance: ${balance.toString()}`);
            return { balance, symbol, address: rewardToken };
          }),
        );
        // at least one reward token balance should be greater than 0
        expect(
          rewardTokensInfo
            // token0 and token1 are in the rewards list;
            // we remove them to check for other rewards
            .filter(
              (rewardToken) =>
                rewardToken.address.toLowerCase() != token0.address.toLowerCase() &&
                rewardToken.address.toLowerCase() != token1.address.toLowerCase(),
            )
            .map((item) => item.balance)
            .some((balance) => balance.gt(0)),
        ).to.be.true;
      });
    });
  });
};
