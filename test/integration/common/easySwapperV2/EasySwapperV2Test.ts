import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { BigNumber } from "ethers";

import { EasySwapperV2, IERC20Extended, PoolLogic, PoolManagerLogic, WithdrawalVault } from "../../../../types";
import { Address } from "../../../../deployment/types";
import { units } from "../../../testHelpers";
import { getAccountToken } from "../../utils/getAccountTokens";
import { ChainIds, utils } from "../../utils/utils";
import { MultiInSingleOutDataStruct } from "../../../../types/EasySwapperV2";
import { SrcTokenSwapDetailsStruct } from "../../../../types/ISwapper";
import { getOneInchSwapTransaction } from "../../utils/oneInchHelpers";
import { createFund } from "../../utils/createFund";
import {
  deployBackboneContracts,
  IBackboneDeploymentsParams,
} from "../../utils/deployContracts/deployBackboneContracts";

const ZERO_ADDRESS = ethers.constants.AddressZero;

const emptySwapData: MultiInSingleOutDataStruct = {
  srcData: [],
  destData: {
    destToken: ZERO_ADDRESS,
    minDestAmount: 0,
  },
};

export interface EasySwapperV2TestCase {
  testPoolAddress: Address;
  poolDepositorAddress: Address;
  destToken: Address;
  slippageTolerance: number; // 1 - 0.1%; 10 - 1%; 100 - 10%
  name: Address;
}

interface EasySwapperV2TestsData {
  assetsBalanceOfSlot: {
    usdc: number;
  };
  wrappedNativeToken: Address;
  swapperAddress: Address;
  baseTestPoolAddress: EasySwapperV2TestCase;
  withdrawTestCases: EasySwapperV2TestCase[];
  chainId: ChainIds;
  depositsData: {
    poolDepositToken: {
      address: Address;
      slot: number;
      amount: BigNumber;
    };
    userDepositToken: {
      address: Address;
      slot: number;
      amount: BigNumber;
    };
    nativeTokenWrapper: {
      address: Address;
      slot: number;
      amount: BigNumber;
    };
  };
  poolFactory: Address;
}

export const deployEasySwapperV2 = async (weth: string, wrappedNativeToken: string, swapperAddress: string) => {
  const WithdrawalVault = await ethers.getContractFactory("WithdrawalVault");
  const withdrawalVaultProxy = await upgrades.deployProxy(WithdrawalVault, [], { initializer: false });
  await withdrawalVaultProxy.deployed();
  const withdrawalVaultImplementationAddress = await getImplementationAddress(
    ethers.provider,
    withdrawalVaultProxy.address,
  );

  const EasySwapperV2 = await ethers.getContractFactory("EasySwapperV2");
  const easySwapperV2 = <EasySwapperV2>await upgrades.deployProxy(EasySwapperV2, [
    withdrawalVaultImplementationAddress,
    weth,
    wrappedNativeToken,
    swapperAddress,
    60 * 60, // 60 minutes
  ]);
  await easySwapperV2.deployed();
  return easySwapperV2;
};

export const runEasySwapperV2Tests = (chainData: EasySwapperV2TestsData & IBackboneDeploymentsParams) => {
  const {
    assets,
    assetsBalanceOfSlot,
    baseTestPoolAddress,
    chainId,
    swapperAddress,
    withdrawTestCases,
    wrappedNativeToken,
    depositsData: { poolDepositToken, userDepositToken, nativeTokenWrapper },
  } = chainData;
  const { poolDepositorAddress, testPoolAddress } = baseTestPoolAddress;

  describe("EasySwapperV2Tests", () => {
    let user1: SignerWithAddress;
    let easySwapperV2: EasySwapperV2;

    utils.beforeAfterReset(beforeEach, afterEach);

    before(async () => {
      [, user1] = await ethers.getSigners();

      easySwapperV2 = await deployEasySwapperV2(assets.weth, wrappedNativeToken, swapperAddress);
      await easySwapperV2.setdHedgePoolFactory(chainData.poolFactory);
    });

    describe("EasySwapperV2 reverts as expected", () => {
      it("should revert when setting swapper as non owner", async () => {
        await expect(easySwapperV2.connect(user1).setSwapper(user1.address)).to.be.revertedWith(
          "Ownable: caller is not the owner",
        );
      });

      it("should revert when setting swapper as zero address", async () => {
        await expect(easySwapperV2.setSwapper(ZERO_ADDRESS)).to.be.revertedWith("invalid address");
      });
    });

    describe("Using EasySwapperV2 for withdraw", () => {
      const initWithdrawal = async (testCase = baseTestPoolAddress) => {
        const testPool = await ethers.getContractAt("PoolLogic", testCase.testPoolAddress);
        const poolDepositor = await utils.impersonateAccount(testCase.poolDepositorAddress);
        const poolDepositorBalance = await testPool.balanceOf(testCase.poolDepositorAddress);
        expect(poolDepositorBalance).to.be.gt(0);
        const tokenPrice = await testPool.tokenPrice();
        const poolDepositorValueD18 = tokenPrice.mul(poolDepositorBalance).div(units(1));

        await testPool.connect(poolDepositor).approve(easySwapperV2.address, poolDepositorBalance);

        await easySwapperV2.connect(poolDepositor).initWithdrawal(testPool.address, poolDepositorBalance, 100);

        return {
          testPool,
          poolDepositor,
          poolDepositorValueD18,
        };
      };

      it("can't withdraw locked tokens via EasySwapperV2", async () => {
        const DepositToken = <IERC20Extended>await ethers.getContractAt("IERC20Extended", assets.usdc);
        const depositTokenDecimals = await DepositToken.decimals();
        const depositAmount = units(6, depositTokenDecimals);
        await getAccountToken(depositAmount, user1.address, assets.usdc, assetsBalanceOfSlot.usdc);

        const testPool = await ethers.getContractAt("PoolLogic", testPoolAddress);
        await DepositToken.connect(user1).approve(testPool.address, depositAmount);

        await testPool.connect(user1).deposit(assets.usdc, depositAmount);
        const balance = await testPool.balanceOf(user1.address);

        await utils.increaseTime(3600);

        await testPool.connect(user1).approve(easySwapperV2.address, balance);
        await expect(easySwapperV2.connect(user1).initWithdrawal(testPool.address, balance, 100)).to.be.revertedWith(
          "cooldown active",
        );
      });

      it("ensures WithdrawalVault works as expected", async () => {
        expect(await easySwapperV2.withdrawalContracts(poolDepositorAddress)).to.eq(ZERO_ADDRESS);

        await initWithdrawal();

        const withdrawalVaultAddress = await easySwapperV2.withdrawalContracts(poolDepositorAddress);
        expect(withdrawalVaultAddress).not.to.eq(ZERO_ADDRESS);

        const withdrawalVault = <WithdrawalVault>await ethers.getContractAt("WithdrawalVault", withdrawalVaultAddress);
        expect((await withdrawalVault.depositor()).toLowerCase()).to.eq(poolDepositorAddress.toLowerCase());
        expect(await withdrawalVault.creator()).to.eq(easySwapperV2.address);

        const trackedAssets = await withdrawalVault.getTrackedAssets();
        expect(trackedAssets.length).to.be.gt(0);

        for (const { token, balance } of trackedAssets) {
          const asset = <IERC20Extended>await ethers.getContractAt("IERC20Extended", token);
          expect(await asset.balanceOf(withdrawalVaultAddress)).to.be.gt(0);
          expect(await asset.balanceOf(withdrawalVaultAddress)).to.be.eq(balance);
        }

        await expect(withdrawalVault.unrollAssets(testPoolAddress, 0)).to.be.revertedWith("only creator");
        await expect(withdrawalVault["recoverAssets()"]()).to.be.revertedWith("only creator");
        await expect(withdrawalVault["recoverAssets(uint256,address)"](0, testPoolAddress)).to.be.revertedWith(
          "only creator",
        );
        await expect(withdrawalVault.swapToSingleAsset(emptySwapData, 0)).to.be.revertedWith("only creator");
      });

      it("can't completeWithdrawal to single token if WithdrawalVault doesn't exist", async () => {
        await expect(easySwapperV2["completeWithdrawal()"]()).to.be.revertedWith("not exists");
      });

      it("can't completeWithdrawal to multiple tokens if WithdrawalVault doesn't exist", async () => {
        await expect(
          easySwapperV2["completeWithdrawal(((address,uint256,(bytes32,bytes))[],(address,uint256)),uint256)"](
            emptySwapData,
            0,
          ),
        ).to.be.revertedWith("not exists");
      });

      it("reverts during partialWithdraw if portion is invalid", async () => {
        const { poolDepositor } = await initWithdrawal();

        await expect(easySwapperV2.connect(poolDepositor).partialWithdraw(0, user1.address)).to.be.revertedWith(
          "invalid portion",
        );
        await expect(
          easySwapperV2.connect(poolDepositor).partialWithdraw(units(1, 19), user1.address),
        ).to.be.revertedWith("invalid portion");
      });

      for (const testCase of withdrawTestCases) {
        it(`${testCase.name} - can completeWithdrawal to single token if WithdrawalVault exists`, async () => {
          const { poolDepositor, poolDepositorValueD18, testPool } = await initWithdrawal(testCase);

          const withdrawalVaultAddress = await easySwapperV2.withdrawalContracts(testCase.poolDepositorAddress);

          const destTokenContract = <IERC20Extended>await ethers.getContractAt("IERC20Extended", testCase.destToken);

          const depositorDestTokenBalanceBefore = await destTokenContract.balanceOf(testCase.poolDepositorAddress);
          const withdrawalVaultDestTokenBalanceBefore = await destTokenContract.balanceOf(withdrawalVaultAddress);

          const decimals = await destTokenContract.decimals();
          const poolManagerLogicAddress = await testPool.poolManagerLogic();
          const poolManagerLogic = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicAddress);
          const destTokenPriceD18 = await poolManagerLogic["assetValue(address,uint256)"](
            testCase.destToken,
            units(1, decimals),
          );
          const factor = decimals < 18 ? units(1, 18 - decimals) : 1;
          const destAmount = poolDepositorValueD18.mul(units(1)).div(destTokenPriceD18).div(factor);
          const minDestAmount = destAmount.mul(1000 - testCase.slippageTolerance).div(1000); // account for slippage during 1inch swaps

          const trackedAssetsBefore = await easySwapperV2.getTrackedAssets(testCase.poolDepositorAddress);
          const trackedAssetsExcludingDestToken = trackedAssetsBefore.filter(
            ({ token }) => token.toLowerCase() !== testCase.destToken.toLowerCase(),
          );

          const srcData: SrcTokenSwapDetailsStruct[] = [];
          for (const { token, balance } of trackedAssetsExcludingDestToken) {
            const swapData = await getOneInchSwapTransaction({
              src: token,
              amount: balance,
              dst: testCase.destToken,
              chainId,
              from: swapperAddress,
              receiver: swapperAddress,
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

          await easySwapperV2
            .connect(poolDepositor)
            ["completeWithdrawal(((address,uint256,(bytes32,bytes))[],(address,uint256)),uint256)"](
              {
                srcData,
                destData: {
                  destToken: testCase.destToken,
                  minDestAmount: srcData.length > 0 ? minDestAmount.sub(withdrawalVaultDestTokenBalanceBefore) : 0,
                },
              },
              minDestAmount,
            );

          const trackedAssetsAfter = await easySwapperV2.getTrackedAssets(testCase.poolDepositorAddress);
          expect(trackedAssetsAfter.length).to.be.eq(0);

          const depositorDestTokenBalanceAfter = await destTokenContract.balanceOf(testCase.poolDepositorAddress);
          expect(depositorDestTokenBalanceAfter).to.be.gte(depositorDestTokenBalanceBefore.add(minDestAmount));

          expect(await destTokenContract.balanceOf(withdrawalVaultAddress)).to.equal(0);
        });

        it(`${testCase.name} - can completeWithdrawal to multiple tokens if WithdrawalVault exists`, async () => {
          const { poolDepositor } = await initWithdrawal();

          const withdrawalVaultAddress = await easySwapperV2.withdrawalContracts(testCase.poolDepositorAddress);
          const trackedAssetsBefore = await easySwapperV2.getTrackedAssets(testCase.poolDepositorAddress);
          const balancesBefore = await Promise.all(
            trackedAssetsBefore.map(async ({ token, balance }) => {
              const asset = <IERC20Extended>await ethers.getContractAt("IERC20Extended", token);
              const depositorBalance = await asset.balanceOf(testCase.poolDepositorAddress);
              return {
                asset,
                vaultBalance: balance,
                depositorBalance,
              };
            }),
          );

          await easySwapperV2.connect(poolDepositor)["completeWithdrawal()"]();

          const trackedAssetsAfter = await easySwapperV2.getTrackedAssets(testCase.poolDepositorAddress);
          expect(trackedAssetsAfter.length).to.be.eq(0);

          for (const { asset, vaultBalance, depositorBalance } of balancesBefore) {
            const vaultBalanceAfter = await asset.balanceOf(withdrawalVaultAddress);
            expect(vaultBalanceAfter).to.eq(0);

            const depositorBalanceAfter = await asset.balanceOf(testCase.poolDepositorAddress);
            expect(depositorBalanceAfter).to.eq(depositorBalance.add(vaultBalance));
          }
        });

        it(`${testCase.name} - can unrollAndClaim to multiple tokens if WithdrawalVault exists`, async () => {
          const testPool = await ethers.getContractAt("PoolLogic", testCase.testPoolAddress);
          const poolDepositor = await utils.impersonateAccount(testCase.poolDepositorAddress);
          const poolDepositorBalance = await testPool.balanceOf(testCase.poolDepositorAddress);
          expect(poolDepositorBalance).to.be.gt(0);

          await testPool.connect(poolDepositor).approve(easySwapperV2.address, poolDepositorBalance);

          const trackedAssetsBefore = await easySwapperV2
            .connect(poolDepositor)
            .callStatic.unrollAndClaim(testPool.address, poolDepositorBalance, 100);

          const balancesBefore = await Promise.all(
            trackedAssetsBefore.map(async ({ token, balance }) => {
              const asset = <IERC20Extended>await ethers.getContractAt("IERC20Extended", token);
              const depositorBalance = await asset.balanceOf(testCase.poolDepositorAddress);
              return {
                asset,
                vaultBalance: balance,
                depositorBalance,
              };
            }),
          );

          await easySwapperV2.connect(poolDepositor).unrollAndClaim(testPool.address, poolDepositorBalance, 100);

          const trackedAssetsAfter = await easySwapperV2.getTrackedAssets(testCase.poolDepositorAddress);
          expect(trackedAssetsAfter.length).to.be.eq(0);

          const withdrawalVaultAddress = await easySwapperV2.withdrawalContracts(testCase.poolDepositorAddress);
          for (const { asset, vaultBalance, depositorBalance } of balancesBefore) {
            const vaultBalanceAfter = await asset.balanceOf(withdrawalVaultAddress);
            expect(vaultBalanceAfter).to.eq(0);

            const depositorBalanceAfter = await asset.balanceOf(testCase.poolDepositorAddress);
            expect(depositorBalanceAfter).to.be.closeTo(
              depositorBalance.add(vaultBalance),
              depositorBalanceAfter.div(100_000), // 0.001%
            );
          }
        });
      }
    });

    describe("Using EasySwapperV2 for deposit", () => {
      let poolLogicProxy: PoolLogic;
      let poolManagerLogicProxy: PoolManagerLogic;
      let user: SignerWithAddress;
      let manager: SignerWithAddress;

      before(async () => {
        const deployments = await deployBackboneContracts(chainData);

        await easySwapperV2.setdHedgePoolFactory(deployments.poolFactory.address);

        const supportedAssets = [
          {
            asset: poolDepositToken.address,
            isDeposit: true,
          },
          {
            asset: assets.weth,
            isDeposit: true,
          },
        ];

        const poolProxies = await createFund(
          deployments.poolFactory,
          deployments.owner,
          deployments.manager,
          supportedAssets,
          {
            performance: ethers.constants.Zero,
            management: ethers.constants.Zero,
          },
        );
        poolLogicProxy = poolProxies.poolLogicProxy;
        poolManagerLogicProxy = poolProxies.poolManagerLogicProxy;
        user = deployments.user;
        manager = deployments.manager;

        await deployments.poolFactory.setPerformanceFeeNumeratorChangeDelay(0);

        await poolManagerLogicProxy.connect(manager).announceFeeIncrease(0, 0, 100, 0); // increase entry fee to 1%
        await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

        await deployments.poolFactory.addCustomCooldownWhitelist(easySwapperV2.address);
        await easySwapperV2.setCustomCooldownWhitelist([
          {
            dHedgeVault: poolLogicProxy.address,
            whitelisted: true,
          },
        ]);

        const UserDepositToken = <IERC20Extended>await ethers.getContractAt("IERC20Extended", userDepositToken.address);
        await getAccountToken(userDepositToken.amount, user.address, userDepositToken.address, userDepositToken.slot);
        await UserDepositToken.connect(user).approve(easySwapperV2.address, userDepositToken.amount);
      });

      const getSwapDataStruct = async () => {
        const amount = userDepositToken.amount;
        const swapData = await getOneInchSwapTransaction({
          src: userDepositToken.address,
          amount,
          dst: poolDepositToken.address,
          chainId,
          from: swapperAddress,
          receiver: swapperAddress,
          version: "6.0",
        });
        await utils.delay(2);

        const swapDataStruct = {
          srcData: {
            token: userDepositToken.address,
            amount,
            aggregatorData: {
              routerKey: ethers.utils.formatBytes32String("ONE_INCH"),
              swapData,
            },
          },
          destData: {
            destToken: poolDepositToken.address,
            minDestAmount: poolDepositToken.amount,
          },
        };
        return swapDataStruct;
      };

      it("can use zapDeposit", async () => {
        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          poolDepositToken.address,
          poolDepositToken.amount,
        );

        const swapDataStruct = await getSwapDataStruct();

        await easySwapperV2.connect(user).zapDeposit(poolLogicProxy.address, swapDataStruct, expectedAmountReceived);

        expect(await poolLogicProxy.getExitRemainingCooldown(user.address)).to.be.eq(86400);

        expect(await poolLogicProxy.balanceOf(user.address)).to.be.gte(expectedAmountReceived);
      });

      it("can use zapDepositWithCustomCooldown", async () => {
        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          poolDepositToken.address,
          poolDepositToken.amount,
        );

        const swapDataStruct = await getSwapDataStruct();

        await easySwapperV2
          .connect(user)
          .zapDepositWithCustomCooldown(poolLogicProxy.address, swapDataStruct, expectedAmountReceived);

        expect(await poolLogicProxy.getExitRemainingCooldown(user.address)).to.be.eq(3600);

        expect(await poolLogicProxy.balanceOf(user.address)).to.be.gte(expectedAmountReceived);
      });

      it("can use depositWithCustomCooldown", async () => {
        expect(await poolLogicProxy.balanceOf(user.address)).to.be.eq(0);

        const PoolDepositToken = <IERC20Extended>await ethers.getContractAt("IERC20Extended", poolDepositToken.address);
        await getAccountToken(poolDepositToken.amount, user.address, poolDepositToken.address, poolDepositToken.slot);
        await PoolDepositToken.connect(user).approve(easySwapperV2.address, poolDepositToken.amount);

        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          poolDepositToken.address,
          poolDepositToken.amount,
        );

        await easySwapperV2
          .connect(user)
          .depositWithCustomCooldown(
            poolLogicProxy.address,
            poolDepositToken.address,
            poolDepositToken.amount,
            expectedAmountReceived,
          );

        expect(await poolLogicProxy.getExitRemainingCooldown(user.address)).to.be.eq(3600);

        expect(await poolLogicProxy.balanceOf(user.address)).to.be.gt(0);
      });

      const getSwapDataNativeStruct = async () => {
        const amount = nativeTokenWrapper.amount;
        const swapData = await getOneInchSwapTransaction({
          src: nativeTokenWrapper.address,
          amount,
          dst: poolDepositToken.address,
          chainId,
          from: swapperAddress,
          receiver: swapperAddress,
          version: "6.0",
        });
        await utils.delay(2);

        const swapDataStruct = {
          srcData: {
            token: nativeTokenWrapper.address,
            amount,
            aggregatorData: {
              routerKey: ethers.utils.formatBytes32String("ONE_INCH"),
              swapData,
            },
          },
          destData: {
            destToken: poolDepositToken.address,
            minDestAmount: poolDepositToken.amount,
          },
        };
        return swapDataStruct;
      };

      it("can use zapNativeDeposit", async () => {
        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          poolDepositToken.address,
          poolDepositToken.amount,
        );

        const swapDataStruct = await getSwapDataNativeStruct();

        await easySwapperV2
          .connect(user)
          .zapNativeDeposit(poolLogicProxy.address, swapDataStruct, expectedAmountReceived, {
            value: nativeTokenWrapper.amount,
          });

        expect(await poolLogicProxy.getExitRemainingCooldown(user.address)).to.be.eq(86400);

        expect(await poolLogicProxy.balanceOf(user.address)).to.be.gte(expectedAmountReceived);
      });

      it("can use zapNativeDepositWithCustomCooldown", async () => {
        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          poolDepositToken.address,
          poolDepositToken.amount,
        );

        const swapDataStruct = await getSwapDataNativeStruct();

        await easySwapperV2
          .connect(user)
          .zapNativeDepositWithCustomCooldown(poolLogicProxy.address, swapDataStruct, expectedAmountReceived, {
            value: nativeTokenWrapper.amount,
          });

        expect(await poolLogicProxy.getExitRemainingCooldown(user.address)).to.be.eq(3600);

        expect(await poolLogicProxy.balanceOf(user.address)).to.be.gte(expectedAmountReceived);
      });

      it("can use nativeDeposit", async () => {
        expect(await poolLogicProxy.balanceOf(user.address)).to.be.eq(0);

        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          nativeTokenWrapper.address,
          nativeTokenWrapper.amount,
        );

        await easySwapperV2.connect(user).nativeDeposit(poolLogicProxy.address, expectedAmountReceived, {
          value: nativeTokenWrapper.amount,
        });

        expect(await poolLogicProxy.getExitRemainingCooldown(user.address)).to.be.eq(86400);
        expect(await poolLogicProxy.balanceOf(user.address)).to.be.gt(0);
      });

      it("can use nativeDepositWithCustomCooldown", async () => {
        expect(await poolLogicProxy.balanceOf(user.address)).to.be.eq(0);

        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          nativeTokenWrapper.address,
          nativeTokenWrapper.amount,
        );

        await easySwapperV2
          .connect(user)
          .nativeDepositWithCustomCooldown(poolLogicProxy.address, expectedAmountReceived, {
            value: nativeTokenWrapper.amount,
          });

        expect(await poolLogicProxy.getExitRemainingCooldown(user.address)).to.be.eq(3600);
        expect(await poolLogicProxy.balanceOf(user.address)).to.be.gt(0);
      });

      it("reverts during deposit with custom cooldow when pool is not in the whitelist", async () => {
        await easySwapperV2.setCustomCooldownWhitelist([
          {
            dHedgeVault: poolLogicProxy.address,
            whitelisted: false,
          },
        ]);

        const swapDataStruct = await getSwapDataNativeStruct();

        await expect(
          easySwapperV2.connect(user).zapDepositWithCustomCooldown(poolLogicProxy.address, swapDataStruct, 0),
        ).to.be.revertedWith("not whitelisted");
        await expect(
          easySwapperV2
            .connect(user)
            .depositWithCustomCooldown(poolLogicProxy.address, poolDepositToken.address, poolDepositToken.amount, 0),
        ).to.be.revertedWith("not whitelisted");
        await expect(
          easySwapperV2.connect(user).zapNativeDepositWithCustomCooldown(poolLogicProxy.address, swapDataStruct, 0, {
            value: nativeTokenWrapper.amount,
          }),
        ).to.be.revertedWith("not whitelisted");
        await expect(
          easySwapperV2.connect(user).nativeDepositWithCustomCooldown(poolLogicProxy.address, 0, {
            value: nativeTokenWrapper.amount,
          }),
        ).to.be.revertedWith("not whitelisted");
      });

      it("reverts during deposit with custom cooldown when no entry fee is set", async () => {
        await poolManagerLogicProxy.connect(manager).setFeeNumerator(0, 0, 0, 0);

        const swapDataStruct = await getSwapDataNativeStruct();

        await expect(
          easySwapperV2.connect(user).zapDepositWithCustomCooldown(poolLogicProxy.address, swapDataStruct, 0),
        ).to.be.revertedWith("entry fee not set");
        await expect(
          easySwapperV2
            .connect(user)
            .depositWithCustomCooldown(poolLogicProxy.address, poolDepositToken.address, poolDepositToken.amount, 0),
        ).to.be.revertedWith("entry fee not set");
        await expect(
          easySwapperV2.connect(user).zapNativeDepositWithCustomCooldown(poolLogicProxy.address, swapDataStruct, 0, {
            value: nativeTokenWrapper.amount,
          }),
        ).to.be.revertedWith("entry fee not set");
        await expect(
          easySwapperV2.connect(user).nativeDepositWithCustomCooldown(poolLogicProxy.address, 0, {
            value: nativeTokenWrapper.amount,
          }),
        ).to.be.revertedWith("entry fee not set");
      });

      it("reverts when swap data is wrong during native deposits", async () => {
        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          poolDepositToken.address,
          poolDepositToken.amount,
        );
        const swapDataStruct = await getSwapDataStruct();

        await expect(
          easySwapperV2.connect(user).zapNativeDeposit(poolLogicProxy.address, swapDataStruct, expectedAmountReceived, {
            value: nativeTokenWrapper.amount,
          }),
        ).to.be.revertedWith("invalid src token");

        await expect(
          easySwapperV2
            .connect(user)
            .zapNativeDepositWithCustomCooldown(poolLogicProxy.address, swapDataStruct, expectedAmountReceived, {
              value: nativeTokenWrapper.amount,
            }),
        ).to.be.revertedWith("invalid src token");
      });

      it("reverts when native token sent doesn't match swap data during native deposits", async () => {
        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          poolDepositToken.address,
          poolDepositToken.amount,
        );
        const swapDataStruct = await getSwapDataNativeStruct();
        swapDataStruct.srcData.amount = nativeTokenWrapper.amount.sub(1);

        await expect(
          easySwapperV2.connect(user).zapNativeDeposit(poolLogicProxy.address, swapDataStruct, expectedAmountReceived, {
            value: nativeTokenWrapper.amount,
          }),
        ).to.be.revertedWith("invalid src amount");

        await expect(
          easySwapperV2
            .connect(user)
            .zapNativeDepositWithCustomCooldown(poolLogicProxy.address, swapDataStruct, expectedAmountReceived, {
              value: nativeTokenWrapper.amount,
            }),
        ).to.be.revertedWith("invalid src amount");
      });

      it("reverts when dst token in swap data is not among deposit assets", async () => {
        await poolManagerLogicProxy.connect(manager).changeAssets([], [poolDepositToken.address]);

        const expectedAmountReceived = await easySwapperV2.depositQuote(
          poolLogicProxy.address,
          poolDepositToken.address,
          poolDepositToken.amount,
        );

        const swapDataStruct = await getSwapDataStruct();

        await expect(
          easySwapperV2.connect(user).zapDeposit(poolLogicProxy.address, swapDataStruct, expectedAmountReceived),
        ).to.be.revertedWith("invalid deposit asset");

        await expect(
          easySwapperV2
            .connect(user)
            .zapDepositWithCustomCooldown(poolLogicProxy.address, swapDataStruct, expectedAmountReceived),
        ).to.be.revertedWith("invalid deposit asset");

        const swapDataNativeStruct = await getSwapDataNativeStruct();

        await expect(
          easySwapperV2
            .connect(user)
            .zapNativeDeposit(poolLogicProxy.address, swapDataNativeStruct, expectedAmountReceived, {
              value: nativeTokenWrapper.amount,
            }),
        ).to.be.revertedWith("invalid deposit asset");

        await expect(
          easySwapperV2
            .connect(user)
            .zapNativeDepositWithCustomCooldown(poolLogicProxy.address, swapDataNativeStruct, expectedAmountReceived, {
              value: nativeTokenWrapper.amount,
            }),
        ).to.be.revertedWith("invalid deposit asset");

        await poolManagerLogicProxy
          .connect(manager)
          .changeAssets([{ asset: poolDepositToken.address, isDeposit: true }], [nativeTokenWrapper.address]);

        await expect(
          easySwapperV2.connect(user).nativeDeposit(poolLogicProxy.address, expectedAmountReceived, {
            value: nativeTokenWrapper.amount,
          }),
        ).to.be.revertedWith("invalid deposit asset");

        await expect(
          easySwapperV2.connect(user).nativeDepositWithCustomCooldown(poolLogicProxy.address, expectedAmountReceived, {
            value: nativeTokenWrapper.amount,
          }),
        ).to.be.revertedWith("invalid deposit asset");
      });
    });
  });
};
