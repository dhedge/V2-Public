import { assert, expect } from "chai";
import { ethers, network } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";
import { checkAlmostSame, units } from "../../../testHelpers";
import {
  PoolLogic,
  IAccountModule__factory,
  IAccountModule,
  ICollateralModule,
  ICollateralModule__factory,
  PoolManagerLogic,
  IAtomicOrderModule__factory,
  IWrapperModule__factory,
  IRewardsManagerModule__factory,
  IRewardsManagerModule,
} from "../../../../types";
import {
  deploySynthethixV3Infrastructure,
  FAKE_WINDOWS,
  PROD_WITHDRAWAL_LIMIT,
} from "./synthetixV3TestDeploymentHelpers";
import { AllowedMarketStruct } from "../../../../types/SynthetixV3SpotMarketContractGuard";
import NodeModuleModified from "./NodeModuleModified.json";
import { getAccountToken, getBalance, toBytes32 } from "../../utils/getAccountTokens";
import { ISynthetixV3TestsParams } from "./SynthetixV3Test";
import { VaultSettingStruct } from "../../../../types/SynthetixV3ContractGuard";

const REFERRER_ADDRESS = ethers.constants.AddressZero;

// https://github.com/Synthetixio/synthetix-v3/blob/main/utils/core-contracts/contracts/token/ERC20Storage.sol
const SYNTH__ERC20_STORAGE_SLOT = ethers.utils.keccak256(
  ethers.utils.defaultAbiCoder.encode(["string"], ["io.synthetix.core-contracts.ERC20"]),
);
// The initial storage slot + 3, and then covert back to hex
const SYNTH_TOKEN_BALANCE_SLOT = toBytes32(ethers.BigNumber.from(SYNTH__ERC20_STORAGE_SLOT).add(3));

const IAccountModule = new ethers.utils.Interface(IAccountModule__factory.abi);
const ICollateralModule = new ethers.utils.Interface(ICollateralModule__factory.abi);

const IAtomicOrderModule = new ethers.utils.Interface(IAtomicOrderModule__factory.abi);
const IWrapperModule = new ethers.utils.Interface(IWrapperModule__factory.abi);
const IRewardsManagerModule = new ethers.utils.Interface(IRewardsManagerModule__factory.abi);

const getPrecisionForConversion = (decimals: number): number => 10 ** (18 - decimals);

export type ISynthetixV3SpotTestsParams = ISynthetixV3TestsParams & {
  rewardsDistributorLiquidation?: {
    distributor: string;
    rewardToken: string;
    unwrapToAsset: string;
    requiredMarketId: number;
  }[];
  allowedMarketCollateralAssetBalanceSlot: Record<string, number>;
  poolToTestLiquidationRewardClaim?: string;
};

export const launchSynthetixSpotMarketsV3Tests = (chainData: ISynthetixV3SpotTestsParams) => {
  const ID = 1234567890;

  describe("SynthetixV3 Spot Markets", () => {
    let deployments: IBackboneDeployments;
    let infrastructureData: Awaited<ReturnType<typeof deploySynthethixV3Infrastructure>>;

    let manager: SignerWithAddress;
    let whitelistedPoolLogic: PoolLogic;
    let whitelistedManagerLogic: PoolManagerLogic;
    let synthetixV3CoreAddress: string;
    let allowedPoolId: number;
    let collateralType: string;
    let debtAsset: string;
    let depositAmount: BigNumber;

    utils.beforeAfterReset(beforeEach, afterEach);
    utils.beforeAfterReset(before, after);

    before(async function () {
      if (chainData.deployedNodeModule) {
        const modifiedBytecode = NodeModuleModified.deployedBytecode;
        await network.provider.send("hardhat_setCode", [chainData.deployedNodeModule, modifiedBytecode]);
      }

      deployments = await deployBackboneContracts(chainData);
      infrastructureData = await deploySynthethixV3Infrastructure(deployments, chainData);

      manager = deployments.manager;
      whitelistedPoolLogic = infrastructureData.whitelistedPool.poolLogicProxy;
      whitelistedManagerLogic = infrastructureData.whitelistedPool.poolManagerLogicProxy;
      synthetixV3CoreAddress = infrastructureData.synthetixV3CoreAddress;
      allowedPoolId = infrastructureData.allowedLiquidityPoolId;
      collateralType = infrastructureData.COLLATERAL_ASSET.address;
      debtAsset = infrastructureData.DEBT_ASSET.address;
      depositAmount = infrastructureData.collateralBalanceInPool;

      await createAccountWithId(ID);
      await depositCollateral(ID, collateralType, depositAmount);
      if (!chainData.allowedMarketIds) {
        return this.skip();
      }
      const BAL_TO_SET_SYNTH = units(5, 16); // 0.0005, test value should be smaller than amount in snxV3CoreProxy

      await Promise.all(
        chainData.allowedMarketIds.map(async ({ collateralSynth }) => {
          // set balance in the dhedge pool
          await getAccountToken(
            BAL_TO_SET_SYNTH,
            whitelistedPoolLogic.address,
            collateralSynth,
            SYNTH_TOKEN_BALANCE_SLOT,
          );
        }),
      );
    });

    const createAccountWithId = async (id: number) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(synthetixV3CoreAddress, IAccountModule.encodeFunctionData("createAccount(uint128)", [id]));

    const depositCollateral = async (accountId: number, collateralType: string, amount: BigNumber) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          synthetixV3CoreAddress,
          ICollateralModule.encodeFunctionData("deposit", [accountId, collateralType, amount]),
        );

    const unwrap = async (marketId: BigNumberish, unwrapAmount: BigNumber, minAmountReceived: BigNumber) =>
      whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          chainData.synthetixV3SpotMarket,
          IWrapperModule.encodeFunctionData("unwrap", [marketId, unwrapAmount, minAmountReceived]),
        );

    const wrap = async (marketId: BigNumberish, wrapAmount: BigNumber, minAmountReceived: BigNumber) =>
      whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          chainData.synthetixV3SpotMarket,
          IWrapperModule.encodeFunctionData("wrap", [marketId, wrapAmount, minAmountReceived]),
        );

    const buy = async (marketId: BigNumberish, amount: BigNumberish, minAmountReceived: BigNumberish) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          chainData.synthetixV3SpotMarket,
          IAtomicOrderModule.encodeFunctionData("buy", [marketId, amount, minAmountReceived, REFERRER_ADDRESS]),
        );

    const sell = async (marketId: BigNumberish, amount: BigNumberish, minAmountReceived: BigNumberish) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          chainData.synthetixV3SpotMarket,
          IAtomicOrderModule.encodeFunctionData("sell", [marketId, amount, minAmountReceived, REFERRER_ADDRESS]),
        );

    const wrapTestPrepare = async () => {
      for (const { collateralAsset, collateralSynth } of chainData.allowedMarketIds || []) {
        const isSupportCollateralAsset = await whitelistedManagerLogic.isSupportedAsset(collateralAsset);
        await getAccountToken(
          units(0, 18),
          whitelistedPoolLogic.address,
          collateralAsset,
          chainData.allowedMarketCollateralAssetBalanceSlot[collateralAsset],
        );
        await infrastructureData.whitelistedPool.poolManagerLogicProxy
          .connect(manager)
          .changeAssets([], isSupportCollateralAsset ? [collateralAsset] : []);
        const collateralAssetDecimals = await (await ethers.getContractAt("ERC20Asset", collateralAsset)).decimals();
        await getAccountToken(
          units(1, collateralAssetDecimals),
          whitelistedPoolLogic.address,
          collateralAsset,
          chainData.allowedMarketCollateralAssetBalanceSlot[collateralAsset],
        );
        await getAccountToken(units(0, 18), whitelistedPoolLogic.address, collateralSynth, SYNTH_TOKEN_BALANCE_SLOT);
      }
    };
    const isDhedgeVaildAsset = async (token: string) => {
      return await whitelistedManagerLogic.validateAsset(token);
    };

    describe("Wrap/Unwrap", () => {
      before(function () {
        if (!chainData.allowedMarketIds) {
          return this.skip();
        }
      });

      it("1. disallow to unwrap ", async function () {
        // a. both valid, sAsset [not supported] => asset [any]
        // b. both valid, sAsset [supported] => asset [ unsupproted]
        // c. both valid, sAsset [supported] => asset [ invalid]

        const filterMarkets: AllowedMarketStruct[] = [];
        for (const { collateralAsset, collateralSynth, marketId, atomicSwapSettings } of chainData.allowedMarketIds ||
          []) {
          const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);

          if (isVaildCollateralSynth) {
            filterMarkets.push({ collateralAsset, collateralSynth, marketId, atomicSwapSettings });
          }
        }
        if (filterMarkets && filterMarkets.length === 0) {
          // only test, if there is a case to test
          return this.skip();
        }

        for (const { marketId, collateralSynth, collateralAsset } of filterMarkets) {
          const collateralAssetDecimals = await (await ethers.getContractAt("ERC20Asset", collateralAsset)).decimals();
          const balacneOfSynth = await getBalance(whitelistedPoolLogic.address, collateralSynth);
          // a. both valid, sAsset [not supported] => asset [any]
          if (!(await whitelistedManagerLogic.isSupportedAsset(collateralSynth))) {
            await expect(
              unwrap(marketId, balacneOfSynth, balacneOfSynth.div(collateralAssetDecimals).add(1)),
            ).to.be.revertedWith("unsupported asset");
            await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
              [
                {
                  asset: collateralSynth,
                  isDeposit: false,
                },
              ],
              [],
            );
          }
          const isVaildCollateralAsset = await isDhedgeVaildAsset(collateralAsset);
          if (isVaildCollateralAsset) {
            // b. both valid, sAsset [supported] => asset [ unsupproted]
            await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
              [
                {
                  asset: collateralSynth,
                  isDeposit: false,
                },
              ],
              [collateralAsset],
            );
            await expect(
              unwrap(marketId, balacneOfSynth, balacneOfSynth.div(collateralAssetDecimals).add(1)),
            ).to.be.revertedWith("unsupported asset");
          } else {
            // c. sAsset [supported] => asset [invalid]
            await expect(
              unwrap(marketId, balacneOfSynth, balacneOfSynth.div(collateralAssetDecimals).add(1)),
            ).to.be.revertedWith("unsupported asset");
          }
        }
      });

      it("2. allow to unwrap (sAsset => asset), for other cases", async function () {
        // a. both valid, both supported
        // b. sAsset [not valid] => asset [any]
        const filterMarkets: AllowedMarketStruct[] = [];
        for (const { collateralAsset, collateralSynth, marketId, atomicSwapSettings } of chainData.allowedMarketIds ||
          []) {
          const isVaildCollateralAsset = await isDhedgeVaildAsset(collateralAsset);
          const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);
          if (isVaildCollateralSynth && isVaildCollateralAsset) {
            await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
              [
                {
                  asset: collateralSynth,
                  isDeposit: false,
                },
                {
                  asset: collateralAsset,
                  isDeposit: false,
                },
              ],
              [],
            );
            filterMarkets.push({ collateralAsset, collateralSynth, marketId, atomicSwapSettings });
          } else if (!isVaildCollateralSynth) {
            filterMarkets.push({ collateralAsset, collateralSynth, marketId, atomicSwapSettings });
          }
        }
        if (filterMarkets && filterMarkets.length === 0) {
          // only test, if there is a case to test
          return this.skip();
        }

        for (const { marketId, collateralAsset, collateralSynth } of filterMarkets) {
          const isValidSynthAsset = await isDhedgeVaildAsset(collateralSynth);
          const isVaildCollateralAsset = await isDhedgeVaildAsset(collateralAsset);
          // need to enable input asset for, a. both valid, both supported
          if (isValidSynthAsset) {
            assert.isTrue(isVaildCollateralAsset);
            await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
              [
                {
                  asset: collateralSynth,
                  isDeposit: false,
                },
                {
                  asset: collateralAsset,
                  isDeposit: false,
                },
              ],
              [],
            );
          }
          const balacneOfSynth = await getBalance(whitelistedPoolLogic.address, collateralSynth);
          // get decimals of collateralAsset
          const collateralAssetDecimals = await (await ethers.getContractAt("ERC20Asset", collateralAsset)).decimals();
          const exactCollateralAmountOut = balacneOfSynth.div(getPrecisionForConversion(collateralAssetDecimals));
          const collateralInV3Core = await getBalance(synthetixV3CoreAddress, collateralAsset);
          if (collateralInV3Core.lt(exactCollateralAmountOut)) {
            // not enough in snxV3 to unwrap; skip, e.g. wsol on arbitrum at the beginning
            continue;
          }

          await whitelistedPoolLogic
            .connect(deployments.manager)
            .execTransaction(
              collateralSynth,
              infrastructureData.iERC20.encodeFunctionData("approve", [
                chainData.synthetixV3SpotMarket,
                balacneOfSynth,
              ]),
            );

          await expect(unwrap(marketId, balacneOfSynth, exactCollateralAmountOut.sub(2))).to.be.revertedWith(
            "amounts don't match",
          );

          const isSupportedOutputAsset = [false, true];
          const snap = await utils.evmTakeSnap();
          for (let i = 0; i < isSupportedOutputAsset.length; i++) {
            const isSupportedOutput = isSupportedOutputAsset[i];

            const balanceOfSynthBefore = await getBalance(whitelistedPoolLogic.address, collateralSynth);
            const balanceOfCollateralBefore = await getBalance(whitelistedPoolLogic.address, collateralAsset);

            if (isSupportedOutput) {
              const isVaildCollateralAsset = await isDhedgeVaildAsset(collateralAsset);
              if (isVaildCollateralAsset) {
                await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
                  [
                    {
                      asset: collateralAsset,
                      isDeposit: false,
                    },
                  ],
                  [],
                );
              }
            }

            await unwrap(marketId, balacneOfSynth, exactCollateralAmountOut.sub(1));

            const balanceOfSynthAfter = await getBalance(whitelistedPoolLogic.address, collateralSynth);
            const balanceOfCollateralAfter = await getBalance(whitelistedPoolLogic.address, collateralAsset);
            const synthAmountChange = balanceOfSynthBefore
              .sub(balanceOfSynthAfter)
              .div(getPrecisionForConversion(collateralAssetDecimals));

            const collatralAmountChange = balanceOfCollateralAfter.sub(balanceOfCollateralBefore);

            expect(synthAmountChange.eq(collatralAmountChange) || synthAmountChange.eq(collatralAmountChange.add(1))).to
              .be.true;

            await utils.evmRestoreSnap(snap);
          }
        }
      });

      describe("3. disallow to wrap (asset => sAsset)", async function () {
        // a. asset[supported] && sAsset[not valid]
        // b. asset[supported] && sAsset[not supported]
        // c. asset[valid but not supported] && sAsset[supported]
        utils.beforeAfterReset(beforeEach, afterEach);
        this.beforeEach(async () => {
          await wrapTestPrepare();
        });

        const testDisallowWrapFunc = async (filterMarkets: AllowedMarketStruct[]) => {
          for (const { marketId, collateralAsset } of filterMarkets) {
            const balacneOfCollateralAsset = await getBalance(whitelistedPoolLogic.address, collateralAsset);
            if (balacneOfCollateralAsset.eq(0)) {
              continue;
            }
            // get decimals of collateralAsset
            const collateralAssetDecimals = await (
              await ethers.getContractAt("ERC20Asset", collateralAsset)
            ).decimals();
            const exactSynthAmountOut = balacneOfCollateralAsset.mul(
              getPrecisionForConversion(collateralAssetDecimals),
            );
            await whitelistedPoolLogic
              .connect(deployments.manager)
              .execTransaction(
                collateralAsset,
                infrastructureData.iERC20.encodeFunctionData("approve", [
                  chainData.synthetixV3SpotMarket,
                  balacneOfCollateralAsset,
                ]),
              );

            await expect(wrap(marketId, balacneOfCollateralAsset, exactSynthAmountOut.sub(1))).to.be.revertedWith(
              "unsupported asset",
            );
          }
        };
        it("a. asset[supported] && sAsset[not valid]", async function () {
          const filterMarkets: AllowedMarketStruct[] = [];
          for (const { collateralAsset, collateralSynth, marketId, atomicSwapSettings } of chainData.allowedMarketIds ||
            []) {
            const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);
            const isVaildCollateralAsset = await isDhedgeVaildAsset(collateralAsset);
            if (isVaildCollateralAsset && !isVaildCollateralSynth) {
              await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
                [
                  {
                    asset: collateralAsset,
                    isDeposit: false,
                  },
                ],
                [],
              );
              filterMarkets.push({ collateralAsset, collateralSynth, marketId, atomicSwapSettings });
            }
          }
          if (filterMarkets.length === 0) return this.skip();
          await testDisallowWrapFunc(filterMarkets);
        });
        it(" b. asset[supported] && sAsset[not supported]", async function () {
          const filterMarkets: AllowedMarketStruct[] = [];
          for (const { collateralAsset, collateralSynth, marketId, atomicSwapSettings } of chainData.allowedMarketIds ||
            []) {
            const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);
            const isVaildCollateralAsset = await isDhedgeVaildAsset(collateralAsset);
            const isSynthSupported = await whitelistedManagerLogic.isSupportedAsset(collateralSynth);

            if (isVaildCollateralAsset && isVaildCollateralSynth) {
              const balacneOfSynth = await getBalance(whitelistedPoolLogic.address, collateralSynth);
              if (!balacneOfSynth.eq(0)) {
                continue;
              }

              await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
                [
                  {
                    asset: collateralAsset,
                    isDeposit: false,
                  },
                ],
                isSynthSupported ? [collateralSynth] : [],
              );
              filterMarkets.push({ collateralAsset, collateralSynth, marketId, atomicSwapSettings });
            }
          }
          if (filterMarkets.length === 0) return this.skip();
          await testDisallowWrapFunc(filterMarkets);
        });
        it("c. asset[valid but not supported] && sAsset[supported]", async function () {
          const filterMarkets: AllowedMarketStruct[] = [];
          for (const { collateralAsset, collateralSynth, marketId, atomicSwapSettings } of chainData.allowedMarketIds ||
            []) {
            const isUpdatedSupportCollateralAsset = await whitelistedManagerLogic.isSupportedAsset(collateralAsset);
            const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);
            const isVaildCollateralAsset = await isDhedgeVaildAsset(collateralAsset);

            if (isVaildCollateralSynth && isVaildCollateralAsset && !isUpdatedSupportCollateralAsset) {
              filterMarkets.push({ collateralAsset, collateralSynth, marketId, atomicSwapSettings });
            }
          }

          if (filterMarkets.length === 0) return this.skip();

          try {
            await testDisallowWrapFunc(filterMarkets);
            expect.fail("Transaction did not revert as expected");
          } catch (error) {
            // actually valid-but-not-supported asset throw this error
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            expect((error as any).reason).to.include("asset disabled");
          }
        });
      });

      it("4. allow to wrap (asset => sAsset), for other cases", async function () {
        await wrapTestPrepare();
        // a. both valid, both supported
        // b. asset [not valid] => sAsset [any]
        const filterMarkets: AllowedMarketStruct[] = [];
        for (const { collateralAsset, collateralSynth, marketId, atomicSwapSettings } of chainData.allowedMarketIds ||
          []) {
          const isVaildCollateralAsset = await isDhedgeVaildAsset(collateralAsset);
          const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);
          if (isVaildCollateralSynth && isVaildCollateralAsset) {
            await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
              [
                {
                  asset: collateralSynth,
                  isDeposit: false,
                },
                {
                  asset: collateralAsset,
                  isDeposit: false,
                },
              ],
              [],
            );
            filterMarkets.push({ collateralAsset, collateralSynth, marketId, atomicSwapSettings });
          } else if (!isVaildCollateralAsset) {
            filterMarkets.push({ collateralAsset, collateralSynth, marketId, atomicSwapSettings });
          }
        }
        if (filterMarkets && filterMarkets.length === 0) {
          // only test, if there is a case to test
          return this.skip();
        }

        for (const { marketId, collateralAsset, collateralSynth } of filterMarkets) {
          const balanceOfSynthBefore = await getBalance(whitelistedPoolLogic.address, collateralSynth);
          const balanceOfCollateralBefore = await getBalance(whitelistedPoolLogic.address, collateralAsset);
          const collateralAssetDecimals = await (await ethers.getContractAt("ERC20Asset", collateralAsset)).decimals();
          const exactSynthAmountOut = balanceOfCollateralBefore.mul(getPrecisionForConversion(collateralAssetDecimals));
          await whitelistedPoolLogic
            .connect(deployments.manager)
            .execTransaction(
              collateralAsset,
              infrastructureData.iERC20.encodeFunctionData("approve", [
                chainData.synthetixV3SpotMarket,
                balanceOfCollateralBefore,
              ]),
            );

          await whitelistedPoolLogic
            .connect(deployments.manager)
            .execTransaction(
              collateralAsset,
              infrastructureData.iERC20.encodeFunctionData("approve", [
                chainData.synthetixV3SpotMarket,
                balanceOfCollateralBefore,
              ]),
            );

          await expect(wrap(marketId, balanceOfCollateralBefore, exactSynthAmountOut.sub(2))).to.be.revertedWith(
            "amounts don't match",
          );

          const isSupportedOutputAsset = [false, true];
          const snap = await utils.evmTakeSnap();
          for (let i = 0; i < isSupportedOutputAsset.length; i++) {
            const isSupportedOutput = isSupportedOutputAsset[i];
            if (isSupportedOutput) {
              const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);
              if (isVaildCollateralSynth) {
                await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
                  [
                    {
                      asset: collateralSynth,
                      isDeposit: false,
                    },
                  ],
                  [],
                );
              }
            }

            await wrap(marketId, balanceOfCollateralBefore, exactSynthAmountOut.sub(1));
            const balanceOfSynthAfter = await getBalance(whitelistedPoolLogic.address, collateralSynth);
            const balanceOfCollateralAfter = await getBalance(whitelistedPoolLogic.address, collateralAsset);
            const synthAmountChange = balanceOfSynthAfter
              .sub(balanceOfSynthBefore)
              .div(getPrecisionForConversion(collateralAssetDecimals));

            const collatralAmountChange = balanceOfCollateralBefore.sub(balanceOfCollateralAfter);
            expect(collatralAmountChange.eq(synthAmountChange) || collatralAmountChange.eq(synthAmountChange.add(1))).to
              .be.true;
            await utils.evmRestoreSnap(snap);
          }
        }
      });
    });

    describe("Atomic Swaps", () => {
      const buyPrepare = async () => {
        await getAccountToken(
          units(1, 18),
          whitelistedPoolLogic.address,
          infrastructureData.DEBT_ASSET.address,
          SYNTH_TOKEN_BALANCE_SLOT,
        );
      };
      const sellPrepare = async () => {
        for (const { collateralSynth } of chainData.allowedMarketIds || []) {
          await getAccountToken(
            units(1, 18),
            whitelistedPoolLogic.address,
            collateralSynth,
            SYNTH_TOKEN_BALANCE_SLOT,
            5,
          );
        }
      };
      it("5. disallow to atomic swap if isAtomicSwapAllowed is false", async function () {
        let counter = 0;
        for (const { marketId, atomicSwapSettings } of chainData.allowedMarketIds || []) {
          if (!atomicSwapSettings.isAtomicSwapAllowed) {
            counter++;
            await buyPrepare();
            await expect(buy(marketId, units(1, 18), units(1, 18))).to.be.revertedWith("atomic swap not allowed");
            await sellPrepare();
            await expect(sell(marketId, units(1, 18), units(1, 18))).to.be.revertedWith("atomic swap not allowed");
          }
        }
        if (counter === 0) {
          this.skip();
        }
      });
      it("6. disallow non-1-to-1 atomic swap, if isOneToOneSwap is true; (sUSDC <=> snxUSD, Base)", async function () {
        let counter = 0;
        for (const { collateralAsset, collateralSynth, marketId, atomicSwapSettings } of chainData.allowedMarketIds ||
          []) {
          if (atomicSwapSettings.isAtomicSwapAllowed && atomicSwapSettings.isOneToOneSwap) {
            counter++;
            const isVaildCollateralAsset = await isDhedgeVaildAsset(collateralAsset);
            const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);
            await buyPrepare();
            if (isVaildCollateralSynth) {
              await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
                [
                  {
                    asset: collateralSynth,
                    isDeposit: false,
                  },
                ],
                [],
              );
              await expect(buy(marketId, units(1, 18), units(1, 18).sub(2))).to.be.revertedWith("amounts don't match");
            } else {
              await expect(buy(marketId, units(1, 18), units(1, 18).sub(2))).to.be.revertedWith("unsupported asset");
            }

            await sellPrepare();
            if (isVaildCollateralAsset) {
              await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
                [
                  {
                    asset: collateralAsset,
                    isDeposit: false,
                  },
                ],
                [],
              );
              await expect(sell(marketId, units(1, 18), units(1, 18).sub(2))).to.be.revertedWith("amounts don't match");
            } else {
              await expect(sell(marketId, units(1, 18), units(1, 18).sub(2))).to.be.revertedWith("unsupported asset");
            }
          }
        }
        if (counter === 0) {
          this.skip();
        }
      });
      it("7. allow 1-to-1 atomic swap, if isOneToOneSwap is true (sUSDC <=> snxUSD, Base)", async function () {
        let counter = 0;
        for (const { collateralAsset, collateralSynth, marketId, atomicSwapSettings } of chainData.allowedMarketIds ||
          []) {
          if (atomicSwapSettings.isAtomicSwapAllowed && atomicSwapSettings.isOneToOneSwap) {
            counter++;
            const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);
            await buyPrepare();

            await whitelistedPoolLogic
              .connect(deployments.manager)
              .execTransaction(
                infrastructureData.DEBT_ASSET.address,
                infrastructureData.iERC20.encodeFunctionData("approve", [
                  chainData.synthetixV3SpotMarket,
                  ethers.constants.MaxUint256,
                ]),
              );

            if (isVaildCollateralSynth) {
              await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
                [
                  {
                    asset: collateralSynth,
                    isDeposit: false,
                  },
                  {
                    asset: collateralAsset,
                    isDeposit: false,
                  },
                ],
                [],
              );
              await expect(buy(marketId, units(1, 18), units(1, 18).sub(2))).to.be.revertedWith("amounts don't match");
            }
            const balanceOfSynthBefore = await getBalance(whitelistedPoolLogic.address, collateralSynth);
            const balanceOfDebtAssetBefore = await getBalance(
              whitelistedPoolLogic.address,
              infrastructureData.DEBT_ASSET.address,
            );
            await buy(marketId, units(1, 18), units(1, 18).sub(1));
            const balanceOfSynthAfter = await getBalance(whitelistedPoolLogic.address, collateralSynth);
            const balanceOfDebtAssetAfter = await getBalance(
              whitelistedPoolLogic.address,
              infrastructureData.DEBT_ASSET.address,
            );
            const synthAmountChange = balanceOfSynthBefore.sub(balanceOfSynthAfter);
            const debtAssetAmountChange = balanceOfDebtAssetAfter.sub(balanceOfDebtAssetBefore);
            expect(debtAssetAmountChange.sub(synthAmountChange)).to.be.lte(1);

            await sellPrepare();
            const balanceOfSynthBeforeSell = await getBalance(whitelistedPoolLogic.address, collateralSynth);
            const balanceOfDebtAssetBeforeSell = await getBalance(
              whitelistedPoolLogic.address,
              infrastructureData.DEBT_ASSET.address,
            );
            await sell(marketId, units(1, 18), units(1, 18).sub(1));
            const balanceOfSynthAfterSell = await getBalance(whitelistedPoolLogic.address, collateralSynth);
            const balanceOfDebtAssetAfterSell = await getBalance(
              whitelistedPoolLogic.address,
              infrastructureData.DEBT_ASSET.address,
            );
            const synthAmountChangeSell = balanceOfSynthBeforeSell.sub(balanceOfSynthAfterSell);
            const debtAssetAmountChangeSell = balanceOfDebtAssetAfterSell.sub(balanceOfDebtAssetBeforeSell);
            expect(synthAmountChangeSell.sub(debtAssetAmountChangeSell)).to.be.lte(1);
          }
        }
        if (counter === 0) {
          this.skip();
        }
      });
      it("8. allow atomic swap and account slippage, if isAtomicSwapAllowed is true and isOneToOneSwap is false( USDx <=> sUSDC )", async function () {
        let counter = 0;
        for (const { collateralSynth, marketId, atomicSwapSettings } of chainData.allowedMarketIds || []) {
          if (atomicSwapSettings.isAtomicSwapAllowed && !atomicSwapSettings.isOneToOneSwap) {
            counter++;
            const spotMarket = await ethers.getContractAt(
              "ISpotMarketConfigurationModule",
              chainData.synthetixV3SpotMarket,
            );
            const spotMarketFee = await spotMarket.callStatic.getMarketFees(marketId);
            if (spotMarketFee.atomicFixedFee.eq(0)) {
              await buyPrepare();
              const isVaildCollateralSynth = await isDhedgeVaildAsset(collateralSynth);
              if (isVaildCollateralSynth) {
                await infrastructureData.whitelistedPool.poolManagerLogicProxy.connect(manager).changeAssets(
                  [
                    {
                      asset: collateralSynth,
                      isDeposit: false,
                    },
                  ],
                  [],
                );
              }
              const balanceOfSynthBefore = await getBalance(whitelistedPoolLogic.address, collateralSynth);
              const balanceOfDebtAssetBefore = await getBalance(
                whitelistedPoolLogic.address,
                infrastructureData.DEBT_ASSET.address,
              );
              await whitelistedPoolLogic
                .connect(deployments.manager)
                .execTransaction(
                  debtAsset,
                  infrastructureData.iERC20.encodeFunctionData("approve", [
                    chainData.synthetixV3SpotMarket,
                    units(1, 18),
                  ]),
                );
              await buy(marketId, units(1, 18), units(1, 18).mul(99).div(100));
              const balanceOfSynthAfter = await getBalance(whitelistedPoolLogic.address, collateralSynth);
              const balanceOfDebtAssetAfter = await getBalance(
                whitelistedPoolLogic.address,
                infrastructureData.DEBT_ASSET.address,
              );
              const synthAmountChange = balanceOfSynthAfter.sub(balanceOfSynthBefore);
              const debtAssetAmountChange = balanceOfDebtAssetBefore.sub(balanceOfDebtAssetAfter);
              checkAlmostSame(synthAmountChange, debtAssetAmountChange, 0.5);

              // sell
              await sellPrepare();
              const balanceOfSynthBeforeSell = await getBalance(whitelistedPoolLogic.address, collateralSynth);
              const balanceOfDebtAssetBeforeSell = await getBalance(
                whitelistedPoolLogic.address,
                infrastructureData.DEBT_ASSET.address,
              );
              await whitelistedPoolLogic
                .connect(deployments.manager)
                .execTransaction(
                  collateralSynth,
                  infrastructureData.iERC20.encodeFunctionData("approve", [
                    chainData.synthetixV3SpotMarket,
                    units(1, 18),
                  ]),
                );

              await sell(marketId, units(1, 18), units(1, 18).div(100).mul(99));
              const balanceOfSynthAfterSell = await getBalance(whitelistedPoolLogic.address, collateralSynth);
              const balanceOfDebtAssetAfterSell = await getBalance(
                whitelistedPoolLogic.address,
                infrastructureData.DEBT_ASSET.address,
              );
              const synthAmountChangeSell = balanceOfSynthBeforeSell.sub(balanceOfSynthAfterSell);
              const debtAssetAmountChangeSell = balanceOfDebtAssetAfterSell.sub(balanceOfDebtAssetBeforeSell);
              checkAlmostSame(synthAmountChangeSell, debtAssetAmountChangeSell, 0.5);
            }
          }
        }
        if (counter === 0) {
          this.skip();
        }
      });
    });

    describe("can claim liquidation reward, and unwrap", () => {
      it("claim reward", async function () {
        // onchain prod pools tested in the test environment
        const poolToTest = chainData.poolToTestLiquidationRewardClaim;
        const hasDistributor = chainData.rewardsDistributorLiquidation?.length != 0;
        if (!poolToTest || !hasDistributor) {
          return this.skip();
        }
        const poolLogic = await ethers.getContractAt("PoolLogic", poolToTest);
        const poolManagerLogicAddress = await poolLogic.poolManagerLogic();
        const poolManagerLogic = await ethers.getContractAt("PoolManagerLogic", poolManagerLogicAddress);
        const factoryAddress = await poolManagerLogic.factory();
        const factory = await ethers.getContractAt("PoolFactory", factoryAddress);
        const governance = await ethers.getContractAt("Governance", await factory.governanceAddress());
        const governaceOwner = await governance.owner();

        // set up synthetixV3Core guard for claimReward
        const currentGuard = await governance.contractGuards(chainData.synthetixV3Core);
        const realWhiteListParams = await (
          await ethers.getContractAt("SynthetixV3ContractGuard", currentGuard)
        ).dHedgeVaultsWhitelist(poolLogic.address);
        const realNftracker = await (await ethers.getContractAt("SynthetixV3ContractGuard", currentGuard)).nftTracker();
        const WeeklyWindowsHelper = await ethers.getContractFactory("WeeklyWindowsHelper");
        const weeklyWindowsHelper = await WeeklyWindowsHelper.deploy();
        await weeklyWindowsHelper.deployed();
        const SynthetixV3ContractGuard = await ethers.getContractFactory("SynthetixV3ContractGuard", {
          libraries: {
            WeeklyWindowsHelper: weeklyWindowsHelper.address,
          },
        });
        const coreContractGuardParams: [string, VaultSettingStruct[], string] = [
          realNftracker,
          [
            {
              poolLogic: realWhiteListParams.poolLogic,
              collateralAsset: realWhiteListParams.collateralAsset,
              debtAsset: realWhiteListParams.debtAsset,
              snxLiquidityPoolId: realWhiteListParams.snxLiquidityPoolId,
            },
          ],
          chainData.synthetixV3Core,
        ];
        const synthetixV3ContractGuard = await SynthetixV3ContractGuard.deploy(
          ...coreContractGuardParams,
          FAKE_WINDOWS,
          PROD_WITHDRAWAL_LIMIT,
        );
        await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [governaceOwner],
        });
        const ownerSigner = await ethers.getSigner(governaceOwner);
        await network.provider.send("hardhat_setBalance", [ownerSigner.address, "0x100000000000000"]);

        // set up spot market guard for unwrap
        const SynthetixV3SpotMarketContractGuard = await ethers.getContractFactory(
          "SynthetixV3SpotMarketContractGuard",
        );
        const synthetixV3SpotMarketContractGuard = await SynthetixV3SpotMarketContractGuard.deploy(
          chainData.synthetixV3Core,
          chainData.synthetixV3SpotMarket,
          deployments.slippageAccumulator.address,
          chainData.allowedMarketIds,
        );
        await synthetixV3SpotMarketContractGuard.deployed();

        // set 2 contract guards
        await governance
          .connect(ownerSigner)
          .setContractGuard(chainData.synthetixV3Core, synthetixV3ContractGuard.address);

        await governance
          .connect(ownerSigner)
          .setContractGuard(chainData.synthetixV3SpotMarket, synthetixV3SpotMarketContractGuard.address);

        const managerAddress = await poolManagerLogic.manager();

        await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [managerAddress],
        });
        const poolManagerSigner = await ethers.getSigner(managerAddress);
        await network.provider.send("hardhat_setBalance", [poolManagerSigner.address, "0x100000000000000"]);
        await network.provider.send("evm_mine", []); // Just mines to the next block
        const accountId = await infrastructureData.accountNFT.tokenOfOwnerByIndex(poolLogic.address, 0);

        const snxV3Core = <IRewardsManagerModule>(
          await ethers.getContractAt(IRewardsManagerModule__factory.abi, infrastructureData.synthetixV3CoreAddress)
        );
        for (const {
          distributor,
          rewardToken,
          requiredMarketId,
          unwrapToAsset,
        } of chainData.rewardsDistributorLiquidation || []) {
          const rewardAmount = await snxV3Core.getAvailableRewards(
            accountId,
            allowedPoolId,
            collateralType,
            distributor,
          );

          if (rewardAmount.lte(1)) {
            continue;
          }
          const balanceOfRewardTokenBefore = await getBalance(poolLogic.address, rewardToken);
          // claim reward
          await poolLogic
            .connect(poolManagerSigner)
            .execTransaction(
              synthetixV3CoreAddress,
              IRewardsManagerModule.encodeFunctionData("claimRewards", [
                accountId,
                chainData.allowedLiquidityPoolId,
                collateralType,
                distributor,
              ]),
            );
          const balanceOfRewardTokenAfter = await getBalance(poolLogic.address, rewardToken);
          expect(balanceOfRewardTokenAfter).to.be.gt(balanceOfRewardTokenBefore);
          const balanceOfUnwrappedTokenBefore = await getBalance(poolLogic.address, unwrapToAsset);
          await whitelistedPoolLogic
            .connect(deployments.manager)
            .execTransaction(
              rewardToken,
              infrastructureData.iERC20.encodeFunctionData("approve", [
                chainData.synthetixV3SpotMarket,
                ethers.constants.MaxUint256,
              ]),
            );
          // unwrap
          await poolLogic
            .connect(poolManagerSigner)
            .execTransaction(
              chainData.synthetixV3SpotMarket,
              IWrapperModule.encodeFunctionData("unwrap", [
                requiredMarketId,
                balanceOfRewardTokenAfter,
                balanceOfRewardTokenAfter.sub(1),
              ]),
            );
          const balanceOfUnwrappedTokenAfter = await getBalance(poolLogic.address, unwrapToAsset);
          expect(balanceOfUnwrappedTokenAfter).to.be.gt(balanceOfUnwrappedTokenBefore);
        }
      });
    });
  });
};
