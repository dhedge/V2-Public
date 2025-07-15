import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { IERC20, PoolLogic, PoolManagerLogic, EasySwapperV2 } from "../../../../types";
import { units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { ChainIds, utils } from "../../utils/utils";
import {
  deployBackboneContracts,
  IBackboneDeploymentsParams,
} from "../../utils/deployContracts/deployBackboneContracts";
import { getOneInchSwapTransaction } from "../../utils/oneInchHelpers";
import { deployEasySwapperV2 } from "./EasySwapperV2Test";
import { AssetType } from "../../../../deployment/upgrade/jobs/assetsJob";
import { SrcTokenSwapDetailsStruct } from "../../../../types/ISwapper";
import { ComplexAssetStruct } from "../../../../types/IPoolLogic";
import { getEmptyComplexAssetsData } from "../aaveV3/deployAaveV3TestInfrastructure";

interface IEasySwapperV2GuardsTestData {
  assetsBalanceOfSlot: {
    usdc: number;
    dai: number;
  };
  wrappedNativeToken: string;
  swapperAddress: string;
  chainId: ChainIds;
}

export const runEasySwapperV2GuardsTest = (chainData: IEasySwapperV2GuardsTestData & IBackboneDeploymentsParams) => {
  describe("EasySwapperV2GuardsTest", () => {
    let easySwapperV2: EasySwapperV2;
    let USDC: IERC20, DAI: IERC20;
    let manager: SignerWithAddress;
    let owner: SignerWithAddress;
    let poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
    let torosAsset: PoolLogic;
    let torosAssetAddress: string;

    utils.beforeAfterReset(beforeEach, afterEach);

    before(async () => {
      const deployments = await deployBackboneContracts(chainData);
      await deployments.assetHandler.setChainlinkTimeout(3600 * 24 * 7); // 1 week expiry

      USDC = deployments.assets.USDC;
      DAI = deployments.assets.DAI;
      manager = deployments.manager;
      owner = deployments.owner;
      easySwapperV2 = await deployEasySwapperV2(
        chainData.assets.weth,
        chainData.wrappedNativeToken,
        chainData.swapperAddress,
      );

      await easySwapperV2.setdHedgePoolFactory(deployments.poolFactory.address);

      const EasySwapperV2ContractGuard = await ethers.getContractFactory("EasySwapperV2ContractGuard");
      const easySwapperV2ContractGuard = await EasySwapperV2ContractGuard.deploy(
        deployments.slippageAccumulator.address,
        200, // 2% slippage max
        10_000,
      );
      await easySwapperV2ContractGuard.deployed();
      await deployments.governance.setContractGuard(easySwapperV2.address, easySwapperV2ContractGuard.address);

      const { poolLogicProxy: torosVault, poolManagerLogicProxy: torosVaultManagerLogic } = await createFund(
        deployments.poolFactory,
        deployments.owner,
        manager,
        [{ asset: USDC.address, isDeposit: true }],
      );
      torosAsset = torosVault;
      torosAssetAddress = torosVault.address;

      await getAccountToken(units(10_000), deployments.owner.address, DAI.address, chainData.assetsBalanceOfSlot.dai);

      await getAccountToken(
        units(10_000, 6),
        deployments.owner.address,
        USDC.address,
        chainData.assetsBalanceOfSlot.usdc,
      );
      await USDC.approve(torosAssetAddress, units(500, 6));
      await torosVault.deposit(USDC.address, units(500, 6));

      await deployments.poolFactory.setPerformanceFeeNumeratorChangeDelay(0);
      await torosVaultManagerLogic.connect(manager).announceFeeIncrease(0, 0, 10, 0); // increase entry fee to 0.1%
      await torosVaultManagerLogic.connect(manager).commitFeeIncrease();
      await deployments.poolFactory.addCustomCooldownWhitelist(easySwapperV2.address);
      await easySwapperV2.setCustomCooldownWhitelist([{ toWhitelist: torosAssetAddress, whitelisted: true }]);

      const EasySwapperV2UnrolledAssetsGuard = await ethers.getContractFactory("EasySwapperV2UnrolledAssetsGuard");
      const easySwapperV2UnrolledAssetsGuard = await EasySwapperV2UnrolledAssetsGuard.deploy();
      await easySwapperV2UnrolledAssetsGuard.deployed();

      await deployments.governance.setAssetGuard(
        AssetType["EasySwapperV2 Unrolled Assets"],
        easySwapperV2UnrolledAssetsGuard.address,
      );

      const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
      const dhedgePoolAggregator = await DHedgePoolAggregator.deploy(torosAssetAddress);
      await dhedgePoolAggregator.deployed();

      await deployments.assetHandler.addAsset(
        torosAssetAddress,
        AssetType["Chainlink direct USD price feed with 8 decimals"],
        dhedgePoolAggregator.address,
      );
      await deployments.assetHandler.addAsset(
        easySwapperV2.address,
        AssetType["EasySwapperV2 Unrolled Assets"],
        deployments.usdPriceAggregator.address,
      );

      // Create the vault we're going to use for testing
      ({ poolLogicProxy, poolManagerLogicProxy } = await createFund(
        deployments.poolFactory,
        deployments.owner,
        manager,
        [
          { asset: USDC.address, isDeposit: true },
          { asset: DAI.address, isDeposit: true },
          // Note: we're enabling the pool as an asset of this pool
          { asset: torosAssetAddress, isDeposit: true },
        ],
      ));
    });

    it("should revert when manager calls not allowed function", async () => {
      await poolManagerLogicProxy
        .connect(manager)
        .changeAssets([{ asset: easySwapperV2.address, isDeposit: false }], []);

      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(
            easySwapperV2.address,
            easySwapperV2.interface.encodeFunctionData("partialWithdraw", [units(1), manager.address]),
          ),
      ).to.be.revertedWith("invalid transaction");
    });

    describe("Deposit", () => {
      it("should allow manager to use depositWithCustomCooldown", async () => {
        await USDC.approve(poolLogicProxy.address, units(500, 6));
        await poolLogicProxy.deposit(USDC.address, units(500, 6));
        // Check token price is $1
        expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(units(1), units(1).div(1000));
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const approveTxData = USDC.interface.encodeFunctionData("approve", [easySwapperV2.address, units(500, 6)]);
        await poolLogicProxy.connect(manager).execTransaction(USDC.address, approveTxData);
        const expectedAmountReceived = await easySwapperV2.depositQuote(torosAssetAddress, USDC.address, units(500, 6));
        const depositWithCustomCooldownTxData = easySwapperV2.interface.encodeFunctionData(
          "depositWithCustomCooldown",
          [torosAssetAddress, USDC.address, units(500, 6), expectedAmountReceived],
        );

        await poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, depositWithCustomCooldownTxData);

        const torosAssetBalance = await poolManagerLogicProxy.assetBalance(torosAssetAddress);
        expect(torosAssetBalance).to.be.gte(expectedAmountReceived);

        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBefore,
          totalFundValueBefore.div(1000),
        );
        expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(units(1), units(1).div(1000));
      });

      it("should allow manager to use zapDepositWithCustomCooldown", async () => {
        const amount = units(500);
        await DAI.approve(poolLogicProxy.address, amount);
        await poolLogicProxy.deposit(DAI.address, amount);
        // Check token price is $1
        expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(units(1), units(1).div(1000));
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const approveTxData = DAI.interface.encodeFunctionData("approve", [easySwapperV2.address, amount]);
        await poolLogicProxy.connect(manager).execTransaction(DAI.address, approveTxData);

        const swapData = await getOneInchSwapTransaction({
          src: DAI.address,
          amount,
          dst: USDC.address,
          chainId: chainData.chainId,
          from: chainData.swapperAddress,
          receiver: chainData.swapperAddress,
          version: "6.0",
        });

        const minDestAmount = units(499, 6);

        const swapDataStruct = {
          srcData: {
            token: DAI.address,
            amount,
            aggregatorData: {
              routerKey: ethers.utils.formatBytes32String("ONE_INCH"),
              swapData,
            },
          },
          destData: {
            destToken: USDC.address,
            minDestAmount,
          },
        };

        const expectedAmountReceived = await easySwapperV2.depositQuote(torosAssetAddress, USDC.address, minDestAmount);

        const zapDepositWithCustomCooldownTxData = easySwapperV2.interface.encodeFunctionData(
          "zapDepositWithCustomCooldown",
          [torosAssetAddress, swapDataStruct, expectedAmountReceived],
        );

        await poolLogicProxy
          .connect(manager)
          .execTransaction(easySwapperV2.address, zapDepositWithCustomCooldownTxData);

        const torosAssetBalance = await poolManagerLogicProxy.assetBalance(torosAssetAddress);
        expect(torosAssetBalance).to.be.gte(expectedAmountReceived);

        expect(await poolManagerLogicProxy.totalFundValue()).to.be.closeTo(
          totalFundValueBefore,
          totalFundValueBefore.div(100),
        );
        expect(await poolLogicProxy.tokenPrice()).to.be.closeTo(units(1), units(1).div(100));
      });

      it("should revert during deposits if asset is not supported", async () => {
        // Remove toros vault from supported assets
        await poolManagerLogicProxy.connect(manager).changeAssets([], [torosAssetAddress]);

        const depositWithCustomCooldownTxData = easySwapperV2.interface.encodeFunctionData(
          "depositWithCustomCooldown",
          [torosAssetAddress, USDC.address, units(500, 6), 0],
        );

        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, depositWithCustomCooldownTxData),
        ).to.be.revertedWith("unsupported destination asset");

        const swapDataStructStub = {
          srcData: {
            token: DAI.address,
            amount: 0,
            aggregatorData: {
              routerKey: ethers.utils.formatBytes32String("ONE_INCH"),
              swapData: "0x",
            },
          },
          destData: {
            destToken: USDC.address,
            minDestAmount: 0,
          },
        };
        const zapDepositWithCustomCooldownTxData = easySwapperV2.interface.encodeFunctionData(
          "zapDepositWithCustomCooldown",
          [torosAssetAddress, swapDataStructStub, 0],
        );

        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, zapDepositWithCustomCooldownTxData),
        ).to.be.revertedWith("unsupported destination asset");
      });
    });

    describe("Withdraw", () => {
      before(async () => {
        await USDC.approve(poolLogicProxy.address, units(500, 6));
        await poolLogicProxy.deposit(USDC.address, units(500, 6));

        const approveTxData = USDC.interface.encodeFunctionData("approve", [easySwapperV2.address, units(500, 6)]);
        await poolLogicProxy.connect(manager).execTransaction(USDC.address, approveTxData);
        const expectedAmountReceived = await easySwapperV2.depositQuote(torosAssetAddress, USDC.address, units(500, 6));
        const depositWithCustomCooldownTxData = easySwapperV2.interface.encodeFunctionData(
          "depositWithCustomCooldown",
          [torosAssetAddress, USDC.address, units(500, 6), expectedAmountReceived],
        );

        await poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, depositWithCustomCooldownTxData);

        await utils.increaseTime(86400); // 24 hours

        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: easySwapperV2.address, isDeposit: false }], []);
      });

      const initWithdrawal = async () => {
        const torosAssetAmountToWithdraw = (await poolManagerLogicProxy.assetBalance(torosAssetAddress)).div(2);
        const approveTxData = poolLogicProxy.interface.encodeFunctionData("approve", [
          easySwapperV2.address,
          torosAssetAmountToWithdraw,
        ]);
        const initWithdrawTxData = easySwapperV2.interface.encodeFunctionData("initWithdrawal", [
          torosAssetAddress,
          torosAssetAmountToWithdraw,
          await getEmptyComplexAssetsData(torosAsset),
        ]);

        await poolLogicProxy.connect(manager).execTransaction(torosAssetAddress, approveTxData);
        await poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, initWithdrawTxData);
      };

      it("should revert if easyswapperv2 asset is not enabled", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([], [easySwapperV2.address]);

        const initWithdrawTxData = easySwapperV2.interface.encodeFunctionData("initWithdrawal", [
          torosAssetAddress,
          0,
          await getEmptyComplexAssetsData(torosAsset),
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, initWithdrawTxData),
        ).to.be.revertedWith("unsupported destination asset");
      });

      it("should revert during init withdrawal if slippage is too high", async () => {
        const complexAssetsData: ComplexAssetStruct[] = [
          { slippageTolerance: 2000, supportedAsset: USDC.address, withdrawData: [] },
        ];
        const initWithdrawTxData = easySwapperV2.interface.encodeFunctionData("initWithdrawal", [
          torosAssetAddress,
          0,
          complexAssetsData,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, initWithdrawTxData),
        ).to.be.revertedWith("beyond allowed slippage");
      });

      it("should revert during init withdrawal if slippage mismatch", async () => {
        const withdrawData = ethers.utils.defaultAbiCoder.encode(
          ["tuple(bytes, tuple(address, uint256), uint256)"],
          [[[], [USDC.address, 0], 100]],
        );
        const complexAssetsData: ComplexAssetStruct[] = [
          { slippageTolerance: 200, supportedAsset: USDC.address, withdrawData },
        ];
        const initWithdrawTxData = easySwapperV2.interface.encodeFunctionData("initWithdrawal", [
          torosAssetAddress,
          0,
          complexAssetsData,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, initWithdrawTxData),
        ).to.be.revertedWith("slippage tolerance mismatch");
      });

      it("should revert during init withdrawal if invalid dst address", async () => {
        const withdrawData = ethers.utils.defaultAbiCoder.encode(
          ["tuple(bytes, tuple(address, uint256), uint256)"],
          [[[], [poolLogicProxy.address, 0], 200]],
        );
        const complexAssetsData: ComplexAssetStruct[] = [
          { slippageTolerance: 200, supportedAsset: USDC.address, withdrawData },
        ];
        const initWithdrawTxData = easySwapperV2.interface.encodeFunctionData("initWithdrawal", [
          torosAssetAddress,
          0,
          complexAssetsData,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, initWithdrawTxData),
        ).to.be.revertedWith("invalid dst asset");
      });

      it("should revert during init withdrawal if invalid src address", async () => {
        const srcDataToEncode = [[manager.address, 0, [ethers.constants.HashZero, []]]];
        const encodedSrcData = ethers.utils.defaultAbiCoder.encode(
          ["tuple(address, uint256, tuple(bytes32, bytes))[]"],
          [srcDataToEncode],
        );
        const withdrawData = ethers.utils.defaultAbiCoder.encode(
          ["tuple(bytes, tuple(address, uint256), uint256)"],
          [[encodedSrcData, [USDC.address, 0], 200]],
        );
        const complexAssetsData: ComplexAssetStruct[] = [
          { slippageTolerance: 200, supportedAsset: USDC.address, withdrawData },
        ];
        const initWithdrawTxData = easySwapperV2.interface.encodeFunctionData("initWithdrawal", [
          torosAssetAddress,
          0,
          complexAssetsData,
        ]);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, initWithdrawTxData),
        ).to.be.revertedWith("invalid src asset");
      });

      it("should revert during init withdrawal if withdrawData is supplied to incorrect asset", async () => {
        const torosAssetAmountToWithdraw = (await poolManagerLogicProxy.assetBalance(torosAssetAddress)).div(2);
        const approveTxData = poolLogicProxy.interface.encodeFunctionData("approve", [
          easySwapperV2.address,
          torosAssetAmountToWithdraw,
        ]);

        const complexAssetsData = await getEmptyComplexAssetsData(poolLogicProxy);
        const srcDataToEncode = [[USDC.address, 0, [ethers.constants.HashZero, []]]];
        const encodedSrcData = ethers.utils.defaultAbiCoder.encode(
          ["tuple(address, uint256, tuple(bytes32, bytes))[]"],
          [srcDataToEncode],
        );
        const withdrawData = ethers.utils.defaultAbiCoder.encode(
          ["tuple(bytes, tuple(address, uint256), uint256)"],
          [[encodedSrcData, [USDC.address, 0], 0]],
        );
        complexAssetsData[0].withdrawData = withdrawData;
        const initWithdrawTxData = easySwapperV2.interface.encodeFunctionData("initWithdrawal", [
          torosAssetAddress,
          0,
          complexAssetsData,
        ]);

        await poolLogicProxy.connect(manager).execTransaction(torosAssetAddress, approveTxData);
        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, initWithdrawTxData),
        ).to.be.revertedWith("invalid asset data");
      });

      it("should allow manager to init withdrawal", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await initWithdrawal();

        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

        expect(totalFundValueBefore).to.be.equal(totalFundValueAfter);
      });

      it("should allow manager to init withdrawal with swap data", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        const torosAssetAmountToWithdraw = (await poolManagerLogicProxy.assetBalance(torosAssetAddress)).div(2);
        const approveTxData = poolLogicProxy.interface.encodeFunctionData("approve", [
          easySwapperV2.address,
          torosAssetAmountToWithdraw,
        ]);

        const initWithdrawTxData = easySwapperV2.interface.encodeFunctionData("initWithdrawal", [
          torosAssetAddress,
          0,
          await getEmptyComplexAssetsData(torosAsset),
        ]);

        await poolLogicProxy.connect(manager).execTransaction(torosAssetAddress, approveTxData);
        await poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, initWithdrawTxData);

        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

        expect(totalFundValueBefore).to.be.equal(totalFundValueAfter);
      });

      it("should allow manager to complete withdraw to single asset", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await initWithdrawal();

        const destToken = DAI.address;
        const trackedAssets = await easySwapperV2.getTrackedAssets(poolLogicProxy.address);
        const trackedAssetsExcludingDestToken = trackedAssets.filter(
          ({ token }) => token.toLowerCase() !== destToken.toLowerCase(),
        );

        const srcData: SrcTokenSwapDetailsStruct[] = [];
        for (const { token, balance } of trackedAssetsExcludingDestToken) {
          const swapData = await getOneInchSwapTransaction({
            src: token,
            amount: balance,
            dst: destToken,
            chainId: chainData.chainId,
            from: chainData.swapperAddress,
            receiver: chainData.swapperAddress,
            version: "6.0",
          });
          srcData.push({
            token,
            amount: balance,
            aggregatorData: {
              routerKey: ethers.utils.formatBytes32String("ONE_INCH"),
              swapData,
            },
          });
          await utils.delay(2);
        }

        const minDestAmount = units(248); // almost 250 DAI tokens, minus some slippage
        const completeWithdrawalTxData = easySwapperV2.interface.encodeFunctionData(
          // eslint-disable-next-line @typescript-eslint/ban-ts-comment
          // @ts-ignore
          "completeWithdrawal(((address,uint256,(bytes32,bytes))[],(address,uint256)),uint256)",
          [
            {
              srcData,
              destData: {
                destToken,
                minDestAmount,
              },
            },
            minDestAmount,
          ],
        );

        await poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, completeWithdrawalTxData);

        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

        expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueAfter.div(1000));
      });

      it("should revert during complete withdraw to single asset if swap slippage is too high", async () => {
        await initWithdrawal();

        const destToken = DAI.address;
        const trackedAssets = await easySwapperV2.getTrackedAssets(poolLogicProxy.address);
        const trackedAssetsExcludingDestToken = trackedAssets.filter(
          ({ token }) => token.toLowerCase() !== destToken.toLowerCase(),
        );

        const srcData: SrcTokenSwapDetailsStruct[] = [];
        for (const { token, balance } of trackedAssetsExcludingDestToken) {
          const swapData = await getOneInchSwapTransaction({
            src: token,
            amount: balance,
            dst: destToken,
            chainId: chainData.chainId,
            from: chainData.swapperAddress,
            receiver: chainData.swapperAddress,
            version: "6.0",
          });
          srcData.push({
            token,
            amount: balance,
            aggregatorData: {
              routerKey: ethers.utils.formatBytes32String("ONE_INCH"),
              swapData,
            },
          });
          await utils.delay(2);
        }

        const minDestAmount = units(200); // low destination amount
        const completeWithdrawalTxData = easySwapperV2.interface.encodeFunctionData(
          // eslint-disable-next-line @typescript-eslint/ban-ts-comment
          // @ts-ignore
          "completeWithdrawal(((address,uint256,(bytes32,bytes))[],(address,uint256)),uint256)",
          [
            {
              srcData,
              destData: {
                destToken,
                minDestAmount,
              },
            },
            minDestAmount,
          ],
        );

        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, completeWithdrawalTxData),
        ).to.be.revertedWith("swap slippage too high");
      });

      it("should revert during complete withdraw to single asset if asset is not enabled", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([], [DAI.address]);

        await initWithdrawal();

        const destToken = DAI.address;
        const completeWithdrawalTxData = easySwapperV2.interface.encodeFunctionData(
          // eslint-disable-next-line @typescript-eslint/ban-ts-comment
          // @ts-ignore
          "completeWithdrawal(((address,uint256,(bytes32,bytes))[],(address,uint256)),uint256)",
          [
            {
              srcData: [],
              destData: {
                destToken,
                minDestAmount: units(242),
              },
            },
            units(242),
          ],
        );

        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, completeWithdrawalTxData),
        ).to.be.revertedWith("unsupported destination asset");
      });

      it("should allow manager to complete withdraw to multiple assets", async () => {
        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

        await initWithdrawal();

        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
        // @ts-ignore
        const completeWithdrawalTxData = easySwapperV2.interface.encodeFunctionData("completeWithdrawal()", []);

        await poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, completeWithdrawalTxData);

        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

        expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueAfter.div(10000));
      });

      it("should revert during complete withdraw to multiple assets if at least one of these assets is not enabled", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([], [USDC.address]);

        await initWithdrawal();

        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
        // @ts-ignore
        const completeWithdrawalTxData = easySwapperV2.interface.encodeFunctionData("completeWithdrawal()", []);

        await expect(
          poolLogicProxy.connect(manager).execTransaction(easySwapperV2.address, completeWithdrawalTxData),
        ).to.be.revertedWith("unsupported destination asset");
      });

      it("should allow depositor to withdraw after initWithdrawal", async () => {
        // Tests EasySwapperV2UnrolledAssetsGuard's withdrawProcessing when easyswapperv2 asset has NON-ZERO balance
        // poolLogicProxy consists of:
        // - USDC: 0
        // - torosAsset: ~500 tokens

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const depositorUsdcBalanceBefore = await USDC.balanceOf(owner.address);
        const depositorTorosAssetBalanceBefore = await torosAsset.balanceOf(owner.address);
        const balanceToWithdraw = (await poolLogicProxy.balanceOf(owner.address)).div(2);

        await initWithdrawal();
        // poolLogicProxy consists of:
        // - USDC: 0
        // - torosAsset: ~250 tokens
        // - easyswapperv2 asset: ~250 USDC

        await poolLogicProxy.withdraw(balanceToWithdraw);

        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
        const depositorUsdcBalanceAfter = await USDC.balanceOf(owner.address);
        const depositorTorosAssetBalanceAfter = await torosAsset.balanceOf(owner.address);

        expect(totalFundValueAfter).to.be.closeTo(totalFundValueBefore.div(2), totalFundValueBefore.div(10000));
        expect(depositorUsdcBalanceBefore.add(units(125, 6))).to.be.closeTo(
          depositorUsdcBalanceAfter,
          depositorUsdcBalanceAfter.div(10000),
        );
        expect(depositorTorosAssetBalanceAfter).to.be.closeTo(
          depositorTorosAssetBalanceBefore.add(units(125)),
          depositorTorosAssetBalanceAfter.div(1000),
        );
      });

      it("should allow depositor to withdraw before initWithdrawal with easyswapperv2 asset enabled", async () => {
        // Tests EasySwapperV2UnrolledAssetsGuard's withdrawProcessing when easyswapperv2 asset has ZERO balance
        // poolLogicProxy consists of:
        // - USDC: 0
        // - torosAsset: ~500 tokens
        // - easyswapperv2 asset: 0

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const depositorUsdcBalanceBefore = await USDC.balanceOf(owner.address);
        const depositorTorosAssetBalanceBefore = await torosAsset.balanceOf(owner.address);
        const balanceToWithdraw = (await poolLogicProxy.balanceOf(owner.address)).div(2);

        await poolLogicProxy.withdraw(balanceToWithdraw);

        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
        const depositorUsdcBalanceAfter = await USDC.balanceOf(owner.address);
        const depositorTorosAssetBalanceAfter = await torosAsset.balanceOf(owner.address);

        expect(totalFundValueAfter).to.be.closeTo(totalFundValueBefore.div(2), totalFundValueBefore.div(10000));
        expect(depositorUsdcBalanceAfter).to.equal(depositorUsdcBalanceBefore);
        expect(depositorTorosAssetBalanceAfter).to.be.closeTo(
          depositorTorosAssetBalanceBefore.add(units(250)),
          depositorTorosAssetBalanceAfter.div(1000),
        );
      });

      it("should allow depositor to SAW after initWithdrawal", async () => {
        // Tests EasySwapperV2 _unrollAssets when easyswapperv2 asset has NON-ZERO balance
        // poolLogicProxy consists of:
        // - USDC: 0
        // - torosAsset: ~500 tokens

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const depositorUsdcBalanceBefore = await USDC.balanceOf(owner.address);
        const depositorTorosAssetBalanceBefore = await torosAsset.balanceOf(owner.address);
        const balanceToWithdraw = (await poolLogicProxy.balanceOf(owner.address)).div(2);

        await initWithdrawal();
        // poolLogicProxy consists of:
        // - USDC: 0
        // - torosAsset: ~250 tokens
        // - easyswapperv2 asset: ~250 USDC

        await poolLogicProxy.approve(easySwapperV2.address, balanceToWithdraw);
        await easySwapperV2.initWithdrawal(
          poolLogicProxy.address,
          balanceToWithdraw,
          await getEmptyComplexAssetsData(poolLogicProxy),
        );
        await easySwapperV2["completeWithdrawal()"]();

        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
        const depositorUsdcBalanceAfter = await USDC.balanceOf(owner.address);
        const depositorTorosAssetBalanceAfter = await torosAsset.balanceOf(owner.address);

        expect(totalFundValueAfter).to.be.closeTo(totalFundValueBefore.div(2), totalFundValueBefore.div(10000));
        expect(depositorUsdcBalanceBefore.add(units(250, 6))).to.be.closeTo(
          depositorUsdcBalanceAfter,
          depositorUsdcBalanceAfter.div(10000),
        );
        expect(depositorTorosAssetBalanceAfter).to.be.eq(depositorTorosAssetBalanceBefore);
      });

      it("should allow depositor to SAW before initWithdrawal with easyswapperv2 asset enabled", async () => {
        // Tests EasySwapperV2 _unrollAssets when easyswapperv2 asset has ZERO balance
        // poolLogicProxy consists of:
        // - USDC: 0
        // - torosAsset: ~500 tokens
        // - easyswapperv2 asset: 0

        const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
        const depositorUsdcBalanceBefore = await USDC.balanceOf(owner.address);
        const depositorTorosAssetBalanceBefore = await torosAsset.balanceOf(owner.address);
        const balanceToWithdraw = (await poolLogicProxy.balanceOf(owner.address)).div(2);

        await poolLogicProxy.approve(easySwapperV2.address, balanceToWithdraw);
        await easySwapperV2.initWithdrawal(
          poolLogicProxy.address,
          balanceToWithdraw,
          await getEmptyComplexAssetsData(poolLogicProxy),
        );
        await easySwapperV2["completeWithdrawal()"]();

        const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
        const depositorUsdcBalanceAfter = await USDC.balanceOf(owner.address);
        const depositorTorosAssetBalanceAfter = await torosAsset.balanceOf(owner.address);

        expect(totalFundValueAfter).to.be.closeTo(totalFundValueBefore.div(2), totalFundValueBefore.div(10000));
        expect(depositorUsdcBalanceBefore.add(units(250, 6))).to.be.closeTo(
          depositorUsdcBalanceAfter,
          depositorUsdcBalanceAfter.div(10000),
        );
        expect(depositorTorosAssetBalanceAfter).to.be.eq(depositorTorosAssetBalanceBefore);
      });
    });
  });
};
