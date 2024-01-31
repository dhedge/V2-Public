import { expect } from "chai";
import { ethers, network } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  IBackboneDeployments,
  IBackboneDeploymentsParams,
  deployBackboneContracts,
  IERC20Path,
} from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";
import { units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import {
  PoolLogic,
  IAccountModule__factory,
  IAccountModule,
  ICollateralModule,
  ICollateralModule__factory,
  IVaultModule__factory,
  IVaultModule,
  PoolManagerLogic,
  PoolManagerLogic__factory,
  IIssueUSDModule__factory,
  SynthetixV3AssetGuard,
  SynthetixV3AssetGuard__factory,
  IAtomicOrderModule__factory,
  IWrapperModule__factory,
  IERC20,
  WeeklyWindowsHelperTest,
} from "../../../../types";
import { deploySynthethixV3Infrastructure } from "./synthetixV3TestDeploymentHelpers";
import { AllowedMarketStruct } from "../../../../types/SynthetixV3SpotMarketContractGuard";

const ONE_UNIT = units(1);

const REFERRER_ADDRESS = ethers.constants.AddressZero;

const IAccountModule = new ethers.utils.Interface(IAccountModule__factory.abi);
const ICollateralModule = new ethers.utils.Interface(ICollateralModule__factory.abi);
const IVaultModule = new ethers.utils.Interface(IVaultModule__factory.abi);
const IIssueUSDModule = new ethers.utils.Interface(IIssueUSDModule__factory.abi);
const IAtomicOrderModule = new ethers.utils.Interface(IAtomicOrderModule__factory.abi);
const IWrapperModule = new ethers.utils.Interface(IWrapperModule__factory.abi);

export type ISynthetixV3TestsParams = IBackboneDeploymentsParams & {
  systemAssets: {
    collateral: {
      address: string;
      usdPriceFeed: string;
      balanceOfSlot: number;
      proxyTargetTokenState: string;
      ownerBalanceTotal: BigNumber;
      balanceToThePool: BigNumber;
    };
    debt: {
      address: string;
      usdPriceFeed: string;
    };
    tokenToCollateral?: {
      address: string;
      usdPriceFeed: string;
      decimals: number;
    };
  };
  allowedLiquidityPoolId: number;
  synthetixV3Core: string;
  synthetixAccountNFT: string;
  synthetixV3SpotMarket: string;
  allowedMarketIds: AllowedMarketStruct[];
  collateralSource: "setBalance" | "transferFrom";
  transferCollateralFrom?: string;
  mintingPositiveDebtForbidden: boolean;
};

export const launchSynthetixV3Tests = (chainData: ISynthetixV3TestsParams) => {
  const SYNTHETIX_ACCOUNT_NFT_TYPE = ethers.utils.solidityKeccak256(["address"], [chainData.synthetixAccountNFT]);
  const ID = 1234567890;

  describe("SynthetixV3", () => {
    let deployments: IBackboneDeployments;
    let infrastructureData: Awaited<ReturnType<typeof deploySynthethixV3Infrastructure>>;

    let manager: SignerWithAddress;
    let whitelistedPoolLogic: PoolLogic;
    let whitelistedManagerLogic: PoolManagerLogic;
    let poolAddress: string;
    let synthetixV3CoreAddress: string;
    let allowedPoolId: number;
    let collateralType: string;
    let debtAsset: string;
    let depositAmount: BigNumber;

    utils.beforeAfterReset(beforeEach, afterEach);
    utils.beforeAfterReset(before, after);

    before(async () => {
      deployments = await deployBackboneContracts(chainData);
      infrastructureData = await deploySynthethixV3Infrastructure(deployments, chainData);

      manager = deployments.manager;
      whitelistedPoolLogic = infrastructureData.whitelistedPool.poolLogicProxy;
      whitelistedManagerLogic = infrastructureData.whitelistedPool.poolManagerLogicProxy;
      poolAddress = whitelistedPoolLogic.address;
      synthetixV3CoreAddress = infrastructureData.synthetixV3CoreAddress;
      allowedPoolId = infrastructureData.allowedLiquidityPoolId;
      collateralType = infrastructureData.COLLATERAL_ASSET.address;
      debtAsset = infrastructureData.DEBT_ASSET.address;
      depositAmount = infrastructureData.collateralBalanceInPool;
    });

    // Reusable functions
    const createAccount = async () =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(synthetixV3CoreAddress, IAccountModule.encodeFunctionData("createAccount()", []));

    const createAccountWithId = async (id: number) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(synthetixV3CoreAddress, IAccountModule.encodeFunctionData("createAccount(uint128)", [id]));

    const depositCollateral = async (accountId: number, collateralType: string, amount: BigNumberish) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          synthetixV3CoreAddress,
          ICollateralModule.encodeFunctionData("deposit", [accountId, collateralType, amount]),
        );

    const withdrawCollateral = async (accountId: number, collateralType: string, amount: BigNumberish) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          synthetixV3CoreAddress,
          ICollateralModule.encodeFunctionData("withdraw", [accountId, collateralType, amount]),
        );

    const delegateCollateral = async (
      accountId: number,
      poolId: number,
      collateralType: string,
      amount: BigNumberish,
      leverage = ONE_UNIT,
    ) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          synthetixV3CoreAddress,
          IVaultModule.encodeFunctionData("delegateCollateral", [accountId, poolId, collateralType, amount, leverage]),
        );

    const mintUSD = async (accountId: number, poolId: number, collateralType: string, amount: BigNumberish) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          synthetixV3CoreAddress,
          IIssueUSDModule.encodeFunctionData("mintUsd", [accountId, poolId, collateralType, amount]),
        );

    const burnUSD = async (accountId: number, poolId: number, collateralType: string, amount: BigNumberish) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          synthetixV3CoreAddress,
          IIssueUSDModule.encodeFunctionData("burnUsd", [accountId, poolId, collateralType, amount]),
        );

    const ownerCreatesPositionAndTransfersItToPool = async () => {
      const synthetixV3CoreAccountModule = <IAccountModule>(
        await ethers.getContractAt(IAccountModule__factory.abi, synthetixV3CoreAddress)
      );
      const synthetixV3CoreCollateralModule = <ICollateralModule>(
        await ethers.getContractAt(ICollateralModule__factory.abi, synthetixV3CoreAddress)
      );
      const synthetixV3CoreVaultModule = <IVaultModule>(
        await ethers.getContractAt(IVaultModule__factory.abi, synthetixV3CoreAddress)
      );
      // Owner creates Synthetix V3 Account and deposits collateral into it
      await synthetixV3CoreAccountModule["createAccount(uint128)"](ID);
      await infrastructureData.COLLATERAL_ASSET.approve(
        synthetixV3CoreAddress,
        infrastructureData.collateralBalanceInOwner,
      );
      await synthetixV3CoreCollateralModule["deposit"](ID, collateralType, infrastructureData.collateralBalanceInOwner);
      await synthetixV3CoreVaultModule["delegateCollateral"](
        ID,
        allowedPoolId,
        collateralType,
        infrastructureData.collateralBalanceInOwner,
        ONE_UNIT,
      );
      await infrastructureData.accountNFT["transferFrom(address,address,uint256)"](
        deployments.owner.address,
        poolAddress,
        ID,
      );
      return ID;
    };

    describe("NFT Account and its permissions", () => {
      it("should be able to create Synthetix V3 NFT account and store it in dHEDGE NFT tracker contract", async () => {
        await createAccount();
        expect(await infrastructureData.accountNFT.balanceOf(poolAddress)).to.equal(1);
        const id = await infrastructureData.accountNFT.tokenOfOwnerByIndex(poolAddress, 0);
        const ids = await infrastructureData.dhedgeNftTrackerStorage.getAllUintIds(
          SYNTHETIX_ACCOUNT_NFT_TYPE,
          poolAddress,
        );
        expect(ids.length).to.equal(1);
        expect(ids[0]).to.equal(id);
      });

      it("should be able to create Synthetix V3 NFT account with custom ID and store it in dHEDGE NFT tracker contract", async () => {
        await createAccountWithId(ID);
        expect(await infrastructureData.accountNFT.balanceOf(poolAddress)).to.equal(1);
        const idCreated = await infrastructureData.accountNFT.tokenOfOwnerByIndex(poolAddress, 0);
        expect(idCreated.toNumber()).to.equal(ID);
        const ids = await infrastructureData.dhedgeNftTrackerStorage.getAllUintIds(
          SYNTHETIX_ACCOUNT_NFT_TYPE,
          poolAddress,
        );
        expect(ids.length).to.equal(1);
        expect(ids[0]).to.equal(ID);
      });

      it("should forbid creating more than 1 Synthetix V3 NFT account in the pool", async () => {
        await createAccount();
        await expect(createAccount()).to.be.revertedWith("only one account allowed");
        await expect(createAccountWithId(ID)).to.be.revertedWith("only one account allowed");
      });

      it("should revert when foreign NFT is sent to the pool using safeTransferFrom", async () => {
        const synthetixV3Core = <IAccountModule>(
          await ethers.getContractAt(IAccountModule__factory.abi, synthetixV3CoreAddress)
        );
        await synthetixV3Core.connect(manager)["createAccount(uint128)"](ID);

        const errorInterface = new ethers.utils.Interface(["error InvalidTransferRecipient(address recipient)"]);
        await expect(
          infrastructureData.accountNFT
            .connect(manager)
            ["safeTransferFrom(address,address,uint256)"](manager.address, poolAddress, ID),
        ).to.be.revertedWith(errorInterface.encodeErrorResult("InvalidTransferRecipient", [poolAddress]));
      });

      it("should not revert when trying to create Synthetix V3 NFT account if pool already has received one through airdrop", async () => {
        await ownerCreatesPositionAndTransfersItToPool();

        await createAccount();
        expect(await infrastructureData.accountNFT.balanceOf(poolAddress)).to.equal(2);
        const idCreated = await infrastructureData.accountNFT.tokenOfOwnerByIndex(poolAddress, 1);
        expect(
          await infrastructureData.synthetixV3ContractGuard.getAccountNftTokenId(poolAddress, synthetixV3CoreAddress),
        ).to.equal(idCreated);
      });

      it("ensures pool manager can not transfer Synthetix V3 NFT account owned by pool", async () => {
        await createAccountWithId(ID);
        const errorInterface = new ethers.utils.Interface(["error Unauthorized(address caller)"]);
        await expect(
          infrastructureData.accountNFT
            .connect(manager)
            ["transferFrom(address,address,uint256)"](poolAddress, manager.address, ID),
        ).to.be.revertedWith(errorInterface.encodeErrorResult("Unauthorized", [manager.address]));
      });

      it("ensures manager can't change pool's permissions on Synthetix V3 NFT account owned by pool", async () => {
        await createAccount();
        const accountId = await infrastructureData.accountNFT.tokenOfOwnerByIndex(poolAddress, 0);
        const permission = ethers.utils.formatBytes32String("ADMIN");

        await expect(
          whitelistedPoolLogic
            .connect(manager)
            .execTransaction(
              synthetixV3CoreAddress,
              IAccountModule.encodeFunctionData("grantPermission(uint128, bytes32, address)", [
                accountId,
                permission,
                manager.address,
              ]),
            ),
        ).to.be.revertedWith("invalid transaction");

        await expect(
          whitelistedPoolLogic
            .connect(manager)
            .execTransaction(
              synthetixV3CoreAddress,
              IAccountModule.encodeFunctionData("revokePermission(uint128, bytes32, address)", [
                accountId,
                permission,
                poolAddress,
              ]),
            ),
        ).to.be.revertedWith("invalid transaction");

        await expect(
          whitelistedPoolLogic
            .connect(manager)
            .execTransaction(
              synthetixV3CoreAddress,
              IAccountModule.encodeFunctionData("renouncePermission(uint128, bytes32)", [accountId, permission]),
            ),
        ).to.be.revertedWith("invalid transaction");
      });

      it("should not allow to create Synthetix V3 NFT account if Synthetix V3 asset is not enabled in the pool", async () => {
        await infrastructureData.whitelistedPool.poolManagerLogicProxy
          .connect(manager)
          .changeAssets([], [synthetixV3CoreAddress]);

        await expect(createAccount()).to.be.revertedWith("enable synthetix v3 asset");
      });

      it("should not break/affect pool with open Synthetix V3 position when other Synthetix V3 NFT account was sent to the pool", async () => {
        const id = ID + 1;
        await createAccountWithId(id);
        await depositCollateral(id, collateralType, depositAmount);
        await delegateCollateral(id, allowedPoolId, collateralType, depositAmount.div(2));
        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

        const airdroppedId = await ownerCreatesPositionAndTransfersItToPool();

        const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
        expect(totalValueBefore).to.equal(totalValueAfter);

        await expect(depositCollateral(airdroppedId, collateralType, depositAmount)).to.be.revertedWith(
          "account not owned by pool",
        );
        await expect(delegateCollateral(airdroppedId, allowedPoolId, collateralType, depositAmount)).to.be.revertedWith(
          "account not owned by pool",
        );
        await expect(mintUSD(airdroppedId, allowedPoolId, collateralType, depositAmount)).to.be.revertedWith(
          "account not owned by pool",
        );
        await expect(burnUSD(airdroppedId, allowedPoolId, collateralType, depositAmount)).to.be.revertedWith(
          "account not owned by pool",
        );
      });
    });

    describe("Incomplete conditions", () => {
      it("should not allow to open Synthetix V3 position on a non-whitelisted pool", async () => {
        const newPool = await createFund(
          deployments.poolFactory,
          deployments.owner,
          manager,
          [
            {
              asset: synthetixV3CoreAddress,
              isDeposit: false,
            },
            {
              asset: collateralType,
              isDeposit: true,
            },
          ],
          {
            performance: ethers.constants.Zero,
            management: ethers.constants.Zero,
          },
        );
        await expect(
          newPool.poolLogicProxy
            .connect(manager)
            .execTransaction(synthetixV3CoreAddress, IAccountModule.encodeFunctionData("createAccount()", [])),
        ).to.be.revertedWith("dhedge vault not whitelisted");
      });

      it("should revert if trying to withdraw collateral and collateral asset is not enabled in the pool", async () => {
        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);

        await infrastructureData.whitelistedPool.poolManagerLogicProxy
          .connect(manager)
          .changeAssets([], [collateralType]);

        await expect(withdrawCollateral(ID, collateralType, depositAmount)).to.be.revertedWith(
          "collateral asset must be enabled",
        );
      });

      it("should revert if trying to borrow debt asset against unsupported lp/using unsupported collateral", async () => {
        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);

        await expect(mintUSD(ID, 0, collateralType, depositAmount)).to.be.revertedWith("lp not allowed");
        await expect(mintUSD(ID, allowedPoolId, deployments.assets.USDC.address, depositAmount)).to.be.revertedWith(
          "unsupported collateral type",
        );
      });

      it("should revert when calling txGuard and afterTxGuard on SynthetixV3ContractGuard not on behalf of the pool", async () => {
        const mockFactory = await ethers.getContractFactory("MockContract");
        const fakePoolManagerLogic = await mockFactory.deploy();
        await fakePoolManagerLogic.deployed();
        await fakePoolManagerLogic.givenCalldataReturnAddress(
          new ethers.utils.Interface(PoolManagerLogic__factory.abi).encodeFunctionData("poolLogic", []),
          poolAddress,
        );
        await expect(
          infrastructureData.synthetixV3ContractGuard
            .connect(manager)
            .afterTxGuard(
              fakePoolManagerLogic.address,
              synthetixV3CoreAddress,
              IAccountModule.encodeFunctionData("createAccount(uint128)", [ID]),
            ),
        ).to.be.revertedWith("not pool logic");
        await expect(
          infrastructureData.synthetixV3ContractGuard
            .connect(manager)
            .txGuard(
              whitelistedManagerLogic.address,
              synthetixV3CoreAddress,
              IAccountModule.encodeFunctionData("createAccount()", []),
            ),
        ).to.be.revertedWith("not pool logic");
      });
    });

    describe("Outflow of funds", () => {
      it("shouldn't allow to deposit into any other account not owned by pool", async () => {
        await createAccount();
        await expect(depositCollateral(ID, collateralType, depositAmount)).to.be.revertedWith(
          "account not owned by pool",
        );
      });

      it("shouldn't allow to deposit with unsupported collateral type", async () => {
        await createAccountWithId(ID);
        await expect(depositCollateral(ID, deployments.assets.USDC.address, depositAmount)).to.be.revertedWith(
          "unsupported collateral type",
        );
      });

      it("shouldn't allow to delegate collateral using unsupported leverage/into unknown lp/using unsupported collateral", async () => {
        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);

        await expect(delegateCollateral(ID, allowedPoolId, collateralType, depositAmount, units(2))).to.be.revertedWith(
          "unsupported leverage",
        );
        await expect(delegateCollateral(ID, 0, collateralType, depositAmount)).to.be.revertedWith("lp not allowed");
        await expect(
          delegateCollateral(ID, allowedPoolId, deployments.assets.USDC.address, depositAmount),
        ).to.be.revertedWith("unsupported collateral type");
      });

      it("shouldn't allow to burn any other position's debt with its own debt asset", async () => {
        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
        const desiredAmountToBorrow = depositAmount.div(2);

        await expect(burnUSD(ID + 1, allowedPoolId, collateralType, desiredAmountToBorrow)).to.be.revertedWith(
          "account not owned by pool",
        );
        await expect(burnUSD(ID, 0, collateralType, desiredAmountToBorrow)).to.be.revertedWith("lp not allowed");
        await expect(
          burnUSD(ID, allowedPoolId, deployments.assets.USDC.address, desiredAmountToBorrow),
        ).to.be.revertedWith("unsupported collateral type");
      });
    });

    describe("Core pool manager functionality and pricing", () => {
      it("should be able to deposit collateral into owned Synthetix V3 account", async () => {
        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();
        const collateralBalanceBefore = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);

        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);

        const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
        const collateralBalanceAfter = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);

        expect(collateralBalanceBefore).to.equal(collateralBalanceAfter.add(depositAmount));
        expect(totalValueBefore).to.equal(totalValueAfter);
      });

      it("should be able to delegate collateral into supported liquidity pool", async () => {
        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();
        const collateralBalanceBefore = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);

        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount.div(2));

        const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
        const collateralBalanceAfter = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);

        expect(collateralBalanceBefore).to.equal(collateralBalanceAfter.add(depositAmount));
        expect(totalValueBefore).to.equal(totalValueAfter);
      });

      it("should be able to borrow debt asset against deposited collateral", async function () {
        if (chainData.mintingPositiveDebtForbidden) this.skip();

        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
        const desiredAmountToBorrow = depositAmount.div(2);
        await mintUSD(ID, allowedPoolId, collateralType, desiredAmountToBorrow);

        const synthetixV3CoreCollateralModule = <ICollateralModule>(
          await ethers.getContractAt(ICollateralModule__factory.abi, synthetixV3CoreAddress)
        );
        expect(
          await synthetixV3CoreCollateralModule.getAccountAvailableCollateral(
            ID,
            infrastructureData.DEBT_ASSET.address,
          ),
        ).to.equal(desiredAmountToBorrow);

        const totalValueAfter = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
        expect(totalValueAfter).to.be.closeTo(totalValueBefore, totalValueBefore.div(10000)); // 0.01%
      });

      it("should be able to repay debt asset debt", async function () {
        if (chainData.mintingPositiveDebtForbidden) this.skip();

        await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry

        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
        const desiredAmountToBorrow = depositAmount.div(2);
        await mintUSD(ID, allowedPoolId, collateralType, desiredAmountToBorrow);

        await utils.increaseTime(86400); // 24 hours

        await burnUSD(ID, allowedPoolId, collateralType, desiredAmountToBorrow.div(2));

        const totalValueAfter = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
        expect(totalValueAfter).to.be.closeTo(totalValueBefore, totalValueBefore.div(10000)); // 0.01%
      });

      it("should be able to undelegate collateral from supported liquidity pool", async function () {
        if (chainData.mintingPositiveDebtForbidden) this.skip();

        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, 0);

        const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
        expect(totalValueBefore).to.equal(totalValueAfter);
      });

      it("should be able to undelegate collateral from supported liquidity pool (Base Andromeda)", async function () {
        if (!chainData.mintingPositiveDebtForbidden) this.skip();

        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();
        const amount = depositAmount.sub(ONE_UNIT);
        await createAccountWithId(ID);
        // Deposit almost everything into Synthetix V3 NFT Account, some dust remains sitting in the pool to burn debt if any
        await depositCollateral(ID, collateralType, amount);
        // Delegate everything what's inside Synthetix V3 NFT Account
        await delegateCollateral(ID, allowedPoolId, collateralType, amount);

        const snxV3Core = await ethers.getContractAt(
          IVaultModule__factory.abi,
          infrastructureData.synthetixV3CoreAddress,
        );
        const debt = await snxV3Core.callStatic.getPositionDebt(ID, allowedPoolId, collateralType);

        // If there is any positive debt, it must be burned to be able to undelegate at least something
        if (debt.gt(0)) {
          // Take remaining dust from the pool (sUSDC) and sell it to get sUSD
          await whitelistedPoolLogic
            .connect(manager)
            .execTransaction(
              chainData.synthetixV3SpotMarket,
              IAtomicOrderModule.encodeFunctionData("sell", [
                chainData.allowedMarketIds[0].marketId,
                debt,
                debt,
                REFERRER_ADDRESS,
              ]),
            );
          // To deposit sUSD into account we need to approve it first
          await whitelistedPoolLogic
            .connect(deployments.manager)
            .execTransaction(
              debtAsset,
              infrastructureData.iERC20.encodeFunctionData("approve", [synthetixV3CoreAddress, debt]),
            );

          // Deposit received sUSD into Synthetix V3 NFT Account
          await depositCollateral(ID, debtAsset, debt);
          // Use this sUSD to burn positive debt
          await burnUSD(ID, allowedPoolId, collateralType, debt);
        }

        // Undelegate everything
        await delegateCollateral(ID, allowedPoolId, collateralType, 0);

        const totalValueAfter = await whitelistedManagerLogic.totalFundValue();

        // If there was some positive debt, total value should be less than before
        if (debt.gt(0)) {
          expect(totalValueBefore).to.equal(totalValueAfter.add(debt));
          // otherwise it should remain the same
        } else {
          expect(totalValueBefore).to.equal(totalValueAfter);
        }
      });

      it("should be able to withdraw undelegated collateral from owned Synthetix V3 NFT account", async () => {
        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();
        const collateralBalanceBefore = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);

        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await withdrawCollateral(ID, collateralType, depositAmount);

        const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
        const collateralBalanceAfter = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);

        expect(collateralBalanceBefore).to.equal(collateralBalanceAfter);
        expect(totalValueBefore).to.equal(totalValueAfter);
      });

      it("should be able to withdraw once delegated collateral from owned Synthetix V3 NFT account", async function () {
        await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry

        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();
        const collateralBalanceBefore = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);

        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);

        const snxV3Core = await ethers.getContractAt(
          IVaultModule__factory.abi,
          infrastructureData.synthetixV3CoreAddress,
        );
        const debt = await snxV3Core.callStatic.getPositionDebt(ID, allowedPoolId, collateralType);
        // In case of positive debt, undelegating shouldn't be possible. Generally speaking, withdraw flow is tested in previous suite
        if (debt.gt(0)) this.skip();

        await delegateCollateral(ID, allowedPoolId, collateralType, 0);

        await expect(withdrawCollateral(ID, collateralType, depositAmount)).to.be.reverted; // AccountActivityTimeoutPending
        await utils.increaseTime(86400); // 24 hours
        await withdrawCollateral(ID, collateralType, depositAmount);

        const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
        const collateralBalanceAfter = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);

        expect(collateralBalanceBefore).to.equal(collateralBalanceAfter);
        expect(totalValueBefore).to.equal(totalValueAfter);
      });

      it("should be able to withdraw/deposit debt asset from/to owned Synthetix V3 NFT account", async function () {
        if (chainData.mintingPositiveDebtForbidden) this.skip();

        await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry

        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
        const desiredAmountToBorrow = depositAmount.div(2);
        await mintUSD(ID, allowedPoolId, collateralType, desiredAmountToBorrow);
        await utils.increaseTime(86400); // 24 hours
        await withdrawCollateral(ID, debtAsset, desiredAmountToBorrow);
        // Manager approves DEBT_ASSET to be spent by SynthetixV3Core
        await whitelistedPoolLogic
          .connect(deployments.manager)
          .execTransaction(
            debtAsset,
            infrastructureData.iERC20.encodeFunctionData("approve", [synthetixV3CoreAddress, desiredAmountToBorrow]),
          );
        await depositCollateral(ID, debtAsset, desiredAmountToBorrow);

        const totalValueAfter = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
        expect(totalValueAfter).to.be.closeTo(totalValueBefore, totalValueBefore.div(10000)); // 0.01%
      });

      it("should be able to mint negative debt and re-deposit it (Base Andromeda)", async function () {
        if (!chainData.mintingPositiveDebtForbidden) this.skip();

        await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry

        await createAccountWithId(ID);
        await depositCollateral(ID, collateralType, depositAmount);
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);

        await utils.increaseTime(60); // Add 1 min to make markets move

        const snxV3Core = await ethers.getContractAt(
          IVaultModule__factory.abi,
          infrastructureData.synthetixV3CoreAddress,
        );
        const debt = await snxV3Core.callStatic.getPositionDebt(ID, allowedPoolId, collateralType);

        // Test only makes sense when debt is negative
        if (debt.lt(0)) {
          const amountToMint = debt.mul(-1);

          await mintUSD(ID, allowedPoolId, collateralType, amountToMint);

          // We need 24 hours to pass to be able to withdraw it from the account
          await utils.increaseTime(86400); // 24 hours

          await withdrawCollateral(ID, debtAsset, amountToMint);

          // Need to approve spot market before buying
          await whitelistedPoolLogic
            .connect(deployments.manager)
            .execTransaction(
              debtAsset,
              infrastructureData.iERC20.encodeFunctionData("approve", [chainData.synthetixV3SpotMarket, amountToMint]),
            );
          // Take withdrawn debt in sUSD and use it to buy sUSDC
          await whitelistedPoolLogic
            .connect(manager)
            .execTransaction(
              chainData.synthetixV3SpotMarket,
              IAtomicOrderModule.encodeFunctionData("buy", [
                chainData.allowedMarketIds[0].marketId,
                amountToMint,
                amountToMint,
                REFERRER_ADDRESS,
              ]),
            );
          // To deposit sUSDC into account we need to approve it first
          await whitelistedPoolLogic
            .connect(deployments.manager)
            .execTransaction(
              collateralType,
              infrastructureData.iERC20.encodeFunctionData("approve", [synthetixV3CoreAddress, amountToMint]),
            );
          const synthetixV3CoreCollateralModule = <ICollateralModule>(
            await ethers.getContractAt(ICollateralModule__factory.abi, synthetixV3CoreAddress)
          );
          const depositedBefore = await synthetixV3CoreCollateralModule.getAccountAvailableCollateral(
            ID,
            collateralType,
          );
          // Re-deposit sUSDC into Synthetix V3 NFT Account
          await depositCollateral(ID, collateralType, amountToMint);
          const depositedAfter = await synthetixV3CoreCollateralModule.getAccountAvailableCollateral(
            ID,
            collateralType,
          );
          expect(depositedAfter).to.be.equal(depositedBefore.add(amountToMint));
        }
      });
    });

    describe("Investor's perspective", () => {
      beforeEach(async () => {
        await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry
      });

      it("should receive zero portion of Synthetix V3 position during withdraw if position is enabled but has no value", async () => {
        const synthetixV3AssetGuard = <SynthetixV3AssetGuard>(
          await ethers.getContractAt(
            SynthetixV3AssetGuard__factory.abi,
            infrastructureData.synthetixV3AssetGuardAddress,
          )
        );
        expect(await synthetixV3AssetGuard.getBalance(poolAddress, synthetixV3CoreAddress)).to.equal(0);

        const ownerCollateralBalanceBefore = await infrastructureData.COLLATERAL_ASSET.balanceOf(
          deployments.owner.address,
        );
        await createAccount();

        expect(await synthetixV3AssetGuard.getBalance(poolAddress, synthetixV3CoreAddress)).to.equal(0);

        // Owner is the only investor in the pool
        const amountToWithdraw = await whitelistedPoolLogic.balanceOf(deployments.owner.address);
        await whitelistedPoolLogic.withdraw(amountToWithdraw);
        const ownerCollateralBalanceAfter = await infrastructureData.COLLATERAL_ASSET.balanceOf(
          deployments.owner.address,
        );
        expect(ownerCollateralBalanceAfter).to.equal(ownerCollateralBalanceBefore.add(depositAmount));
      });

      it("should receive a portion of undelegated collateral during withdraw when debt asset is minted", async function () {
        // Skipping this because in Base Andromeda unwrapped collateral is being withdrawn (tested separately)
        if (chainData.mintingPositiveDebtForbidden) this.skip();

        const ownerCollateralBalanceBefore = await infrastructureData.COLLATERAL_ASSET.balanceOf(
          deployments.owner.address,
        );

        await createAccountWithId(ID);
        // Deposit all COLLATERAL_ASSET in the pool into Synthetix V3 NFT Account
        await depositCollateral(ID, collateralType, depositAmount);
        // Delegate half of it to the pool
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount.div(2));
        const borrowAmount = depositAmount.div(4);
        await mintUSD(ID, allowedPoolId, collateralType, borrowAmount);

        await utils.increaseTime(86400); // 24 hours

        const totalValueBeforeWithdraw = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
        const ownerPoolTokenBalanceBefore = await whitelistedPoolLogic.balanceOf(deployments.owner.address);
        // Withdraw 50% of the pool tokens
        const tokensToWithdraw = ownerPoolTokenBalanceBefore.div(2);
        await whitelistedPoolLogic.withdraw(tokensToWithdraw);
        const totalValueAfterWithdraw = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
        const ownerCollateralBalanceAfter = await infrastructureData.COLLATERAL_ASSET.balanceOf(
          deployments.owner.address,
        );

        // Asserting that pool's TVL decreased by 50% after withdraw as pool has only one investor
        expect(totalValueAfterWithdraw).to.be.closeTo(
          totalValueBeforeWithdraw.div(2),
          totalValueBeforeWithdraw.div(100000), // 0.001%
        );

        // It's safe to get tokenPrice right after withdraw as AssetGuard has fresh debt value stored
        const tokenPrice = await whitelistedPoolLogic.tokenPrice();
        const collateralWithdrawnValue = tokensToWithdraw.mul(tokenPrice).div(ONE_UNIT);
        const collateralPrice = await whitelistedManagerLogic["assetValue(address,uint256)"](collateralType, ONE_UNIT);
        const estimatedCollateralReceived = collateralWithdrawnValue.mul(ONE_UNIT).div(collateralPrice);

        // Asserting that investor received correct portion of COLLATERAL_ASSET
        expect(ownerCollateralBalanceAfter).to.equal(ownerCollateralBalanceBefore.add(estimatedCollateralReceived));
      });

      it("should receive a portion of undelegated collateral during withdraw when debt is zero", async function () {
        // Skipping this because in Base Andromeda unwrapped collateral is being withdrawn (tested separately)
        if (chainData.mintingPositiveDebtForbidden) this.skip();

        const ownerCollateralBalanceBefore = await infrastructureData.COLLATERAL_ASSET.balanceOf(
          deployments.owner.address,
        );

        await createAccountWithId(ID);
        // Deposit all COLLATERAL_ASSET in the pool into Synthetix V3 NFT Account
        await depositCollateral(ID, collateralType, depositAmount);
        // Delegate half of it to the pool
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount.div(2));

        await utils.increaseTime(86400); // 24 hours

        const totalValueBeforeWithdraw = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
        const ownerPoolTokenBalanceBefore = await whitelistedPoolLogic.balanceOf(deployments.owner.address);
        // Withdraw 50% of the pool tokens
        const tokensToWithdraw = ownerPoolTokenBalanceBefore.div(2);
        await whitelistedPoolLogic.withdraw(tokensToWithdraw);
        const totalValueAfterWithdraw = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
        const ownerCollateralBalanceAfter = await infrastructureData.COLLATERAL_ASSET.balanceOf(
          deployments.owner.address,
        );

        // Asserting that pool's TVL decreased by 50% after withdraw as pool has only one investor
        expect(totalValueAfterWithdraw).to.be.closeTo(
          totalValueBeforeWithdraw.div(2),
          totalValueBeforeWithdraw.div(100000), // 0.001%
        );

        // It's safe to get tokenPrice right after withdraw as AssetGuard has fresh debt value stored
        const tokenPrice = await whitelistedPoolLogic.tokenPrice();
        const collateralWithdrawnValue = tokensToWithdraw.mul(tokenPrice);
        const collateralPrice = await whitelistedManagerLogic["assetValue(address,uint256)"](collateralType, ONE_UNIT);
        const estimatedCollateralReceived = collateralWithdrawnValue.div(collateralPrice);

        // Asserting that investor received correct portion of COLLATERAL_ASSET
        expect(ownerCollateralBalanceAfter).to.equal(ownerCollateralBalanceBefore.add(estimatedCollateralReceived));
      });

      it("should not be able to withdraw if available undelegated collateral is not enough to make a withdraw", async () => {
        await createAccountWithId(ID);
        // Deposit all COLLATERAL_ASSET in the pool into Synthetix V3 NFT Account
        await depositCollateral(ID, collateralType, depositAmount);
        // Delegate all of it to the pool
        await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);

        // Withdraw 50% of the pool tokens
        const tokensToWithdraw = (await whitelistedPoolLogic.balanceOf(deployments.owner.address)).div(2);
        await expect(whitelistedPoolLogic.withdraw(tokensToWithdraw)).to.be.revertedWith(
          "not enough available balance",
        );
      });
    });

    describe("SpotMarket enabled", () => {
      let TOKEN_TO_COLLATERAL_ASSET: IERC20;

      beforeEach(async function () {
        if (!chainData.systemAssets.tokenToCollateral) this.skip();

        await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry

        TOKEN_TO_COLLATERAL_ASSET = <IERC20>(
          await ethers.getContractAt(IERC20Path, chainData.systemAssets.tokenToCollateral.address)
        );
      });

      it("should return unwrapped collateral token during withdraw", async () => {
        const ownerTokenToCollateralBalanceBefore = await TOKEN_TO_COLLATERAL_ASSET.balanceOf(
          deployments.owner.address,
        );

        await createAccountWithId(ID);
        // Deposit all COLLATERAL_ASSET in the pool into Synthetix V3 NFT Account
        // Tests assumes there is no other positions in the portfolio except Synthetix V3
        await depositCollateral(ID, collateralType, depositAmount);

        const ownerPoolTokenBalanceBefore = await whitelistedPoolLogic.balanceOf(deployments.owner.address);
        // Withdraw 50% of the pool tokens
        const tokensToWithdraw = ownerPoolTokenBalanceBefore.div(2);
        await whitelistedPoolLogic.withdraw(tokensToWithdraw);
        const ownerTokenToCollateralBalanceAfter = await TOKEN_TO_COLLATERAL_ASSET.balanceOf(deployments.owner.address);

        // It's safe to get tokenPrice right after withdraw as AssetGuard has fresh debt value stored
        const tokenPrice = await whitelistedPoolLogic.tokenPrice();
        const collateralWithdrawnValue = tokensToWithdraw.mul(tokenPrice);
        const collateralPrice = await whitelistedManagerLogic["assetValue(address,uint256)"](collateralType, ONE_UNIT);
        const tokenToCollateralDecimals = chainData.systemAssets.tokenToCollateral?.decimals ?? 18;
        const estimatedTokenToCollateralReceived = collateralWithdrawnValue
          .div(collateralPrice)
          .div(10 ** (18 - tokenToCollateralDecimals));

        // Asserting that investor received correct portion of TOKEN_TO_COLLATERAL_ASSET
        expect(ownerTokenToCollateralBalanceAfter).to.equal(
          ownerTokenToCollateralBalanceBefore.add(estimatedTokenToCollateralReceived),
        );
      });

      it("should not allow to trade Synthetix V3 spot market on a non-whitelisted pool", async () => {
        const newPool = await createFund(
          deployments.poolFactory,
          deployments.owner,
          manager,
          [
            {
              asset: synthetixV3CoreAddress,
              isDeposit: false,
            },
            {
              asset: collateralType,
              isDeposit: true,
            },
          ],
          {
            performance: ethers.constants.Zero,
            management: ethers.constants.Zero,
          },
        );
        await expect(
          newPool.poolLogicProxy
            .connect(manager)
            .execTransaction(
              chainData.synthetixV3SpotMarket,
              IAtomicOrderModule.encodeFunctionData("buy", [
                chainData.allowedMarketIds[0].marketId,
                ONE_UNIT,
                ONE_UNIT,
                REFERRER_ADDRESS,
              ]),
            ),
        ).to.be.revertedWith("dhedge vault not whitelisted");
      });

      it("shoule be able to wrap and unwrap allowed collateral type", async () => {
        expect(await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress)).to.equal(depositAmount);

        const tokenToCollateralDecimals = chainData.systemAssets.tokenToCollateral?.decimals ?? 18;
        const precisionForConvertion = 10 ** (18 - tokenToCollateralDecimals);
        const minAmountReceived = depositAmount.div(precisionForConvertion);

        // Approve is not required for unwrapping
        await whitelistedPoolLogic
          .connect(manager)
          .execTransaction(
            chainData.synthetixV3SpotMarket,
            IWrapperModule.encodeFunctionData("unwrap", [
              chainData.allowedMarketIds[0].marketId,
              depositAmount,
              minAmountReceived,
            ]),
          );

        expect(await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress)).to.equal(0);
        expect(await TOKEN_TO_COLLATERAL_ASSET.balanceOf(poolAddress)).to.equal(minAmountReceived);

        const wrapAmount = minAmountReceived;

        // Manager approves TOKEN_TO_COLLATERAL_ASSET to be spent by SpotMarket to wrap
        await whitelistedPoolLogic
          .connect(deployments.manager)
          .execTransaction(
            TOKEN_TO_COLLATERAL_ASSET.address,
            infrastructureData.iERC20.encodeFunctionData("approve", [chainData.synthetixV3SpotMarket, wrapAmount]),
          );

        await whitelistedPoolLogic
          .connect(manager)
          .execTransaction(
            chainData.synthetixV3SpotMarket,
            IWrapperModule.encodeFunctionData("wrap", [
              chainData.allowedMarketIds[0].marketId,
              wrapAmount,
              wrapAmount.mul(precisionForConvertion),
            ]),
          );

        expect(await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress)).to.equal(depositAmount);
        expect(await TOKEN_TO_COLLATERAL_ASSET.balanceOf(poolAddress)).to.equal(0);
      });

      it("should not be able to interact on spot market if collateral type is not allowed", async () => {
        const wrapArgs = [42, 42, 42];
        const tradeArgs = [...wrapArgs, REFERRER_ADDRESS];
        const availableMethods = [
          { method: "unwrap", contractInterface: IWrapperModule, args: wrapArgs },
          { method: "wrap", contractInterface: IWrapperModule, args: wrapArgs },
          { method: "buy", contractInterface: IAtomicOrderModule, args: tradeArgs },
          { method: "sell", contractInterface: IAtomicOrderModule, args: tradeArgs },
          { method: "buyExactIn", contractInterface: IAtomicOrderModule, args: tradeArgs },
          { method: "sellExactIn", contractInterface: IAtomicOrderModule, args: tradeArgs },
        ];

        for (const { method, contractInterface, args } of availableMethods) {
          await expect(
            whitelistedPoolLogic
              .connect(manager)
              .execTransaction(chainData.synthetixV3SpotMarket, contractInterface.encodeFunctionData(method, args)),
          ).to.be.revertedWith("market not allowed");
        }
      });

      it("should be able to buy and sell on spot market", async () => {
        expect(await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress)).to.equal(depositAmount);

        // Approve is not required for selling
        // Sells sUSDC in pool and gets sUSD
        await whitelistedPoolLogic
          .connect(manager)
          .execTransaction(
            chainData.synthetixV3SpotMarket,
            IAtomicOrderModule.encodeFunctionData("sell", [
              chainData.allowedMarketIds[0].marketId,
              depositAmount,
              depositAmount,
              REFERRER_ADDRESS,
            ]),
          );

        expect(await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress)).to.equal(0);
        expect(await infrastructureData.DEBT_ASSET.balanceOf(poolAddress)).to.equal(depositAmount);

        // Manager approves DEBT_ASSET to be spent by SpotMarket to buy
        await whitelistedPoolLogic
          .connect(deployments.manager)
          .execTransaction(
            infrastructureData.DEBT_ASSET.address,
            infrastructureData.iERC20.encodeFunctionData("approve", [chainData.synthetixV3SpotMarket, depositAmount]),
          );

        // Buys sUSDC in pool for sUSD
        await whitelistedPoolLogic
          .connect(manager)
          .execTransaction(
            chainData.synthetixV3SpotMarket,
            IAtomicOrderModule.encodeFunctionData("buy", [
              chainData.allowedMarketIds[0].marketId,
              depositAmount,
              depositAmount,
              REFERRER_ADDRESS,
            ]),
          );

        expect(await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress)).to.equal(depositAmount);
        expect(await infrastructureData.DEBT_ASSET.balanceOf(poolAddress)).to.equal(0);
      });
    });

    describe("Weekly Windows", () => {
      let weeklyWindowsHelperTest: WeeklyWindowsHelperTest;

      before(async () => {
        await deployments.governance.setContractGuard(
          synthetixV3CoreAddress,
          infrastructureData.synthetixV3ContractGuardWithRealWindows.address,
        );
        const WeeklyWindowsHelperTest = await ethers.getContractFactory("WeeklyWindowsHelperTest", {
          libraries: {
            WeeklyWindowsHelper: infrastructureData.weeklyWindowsHelper.address,
          },
        });
        weeklyWindowsHelperTest = await WeeklyWindowsHelperTest.deploy();
        weeklyWindowsHelperTest.deployed();
      });

      describe("Withdraw limit calculated correctly", () => {
        it("should return $50k as withdraw limit if 10% of collateral is less value", async () => {
          const limit = await infrastructureData.synthetixV3ContractGuardWithRealWindows.calculateWithdrawalLimit(
            units(100),
            collateralType,
            whitelistedManagerLogic.address,
          );
          const collateralValue = await whitelistedManagerLogic["assetValue(address,uint256)"](collateralType, limit);
          expect(collateralValue).to.be.closeTo(units(50_000), units(50_000).div(1_000_000)); // 0.0001%;
        });

        it("should return 10% of collateral if its value is more than $50k", async () => {
          const limit = await infrastructureData.synthetixV3ContractGuardWithRealWindows.calculateWithdrawalLimit(
            units(1_000_000),
            collateralType,
            whitelistedManagerLogic.address,
          );
          expect(limit).to.equal(units(100_000));
        });
      });

      describe("Time validation", () => {
        it("should validate time period correctly", async () => {
          await expect(weeklyWindowsHelperTest.validateTimePeriod({ dayOfWeek: 0, hour: 0 })).to.be.revertedWith(
            "invalid day of week",
          );
          await expect(weeklyWindowsHelperTest.validateTimePeriod({ dayOfWeek: -0, hour: 0 })).to.be.revertedWith(
            "invalid day of week",
          );
          await expect(
            weeklyWindowsHelperTest.validateTimePeriod({ dayOfWeek: ethers.constants.Zero, hour: 0 }),
          ).to.be.revertedWith("invalid day of week");
          await expect(weeklyWindowsHelperTest.validateTimePeriod({ dayOfWeek: 8, hour: 0 })).to.be.revertedWith(
            "invalid day of week",
          );
          await expect(weeklyWindowsHelperTest.validateTimePeriod({ dayOfWeek: 7, hour: 24 })).to.be.revertedWith(
            "invalid hour",
          );
          await expect(weeklyWindowsHelperTest.validateTimePeriod({ dayOfWeek: 7, hour: 100 })).to.be.revertedWith(
            "invalid hour",
          );
          await expect(weeklyWindowsHelperTest.validateTimePeriod({ dayOfWeek: 7, hour: ethers.constants.Zero })).not.to
            .be.reverted;
          await expect(weeklyWindowsHelperTest.validateTimePeriod({ dayOfWeek: 1, hour: 23 })).not.to.be.reverted;
        });

        it("should correctly define if timestamp is within allowed window", async () => {
          // From Tuesday to half of Thursday
          const delegationWindow = {
            start: {
              dayOfWeek: 2,
              hour: 0,
            },
            end: {
              dayOfWeek: 4,
              hour: 12,
            },
          };
          // From half of Thursday till Friday
          const undelegationWindow = {
            start: {
              dayOfWeek: 4,
              hour: 12,
            },
            end: {
              dayOfWeek: 5,
              hour: 0,
            },
          };
          for (let i = 1; i <= 28; i += 7) {
            expect(
              await weeklyWindowsHelperTest.isWithinAllowedWindow(
                delegationWindow,
                await weeklyWindowsHelperTest.timestampFromDate(2024, 1, i), // Monday
              ),
            ).to.be.false;
            expect(
              await weeklyWindowsHelperTest.isWithinAllowedWindow(
                undelegationWindow,
                await weeklyWindowsHelperTest.timestampFromDate(2024, 1, i), // Monday
              ),
            ).to.be.false;
            expect(
              await weeklyWindowsHelperTest.isWithinAllowedWindow(
                delegationWindow,
                await weeklyWindowsHelperTest.timestampFromDate(2024, 1, i + 1), // Tuesday
              ),
            ).to.be.true;
            expect(
              await weeklyWindowsHelperTest.isWithinAllowedWindow(
                undelegationWindow,
                await weeklyWindowsHelperTest.timestampFromDate(2024, 1, i + 1), // Tuesday
              ),
            ).to.be.false;
            expect(
              await weeklyWindowsHelperTest.isWithinAllowedWindow(
                delegationWindow,
                await weeklyWindowsHelperTest.timestampFromDate(2024, 1, i + 3), // Thursday
              ),
            ).to.be.true;
            expect(
              await weeklyWindowsHelperTest.isWithinAllowedWindow(
                undelegationWindow,
                await weeklyWindowsHelperTest.timestampFromDate(2024, 1, i + 3), // Thursday
              ),
            ).to.be.false;
            expect(
              await weeklyWindowsHelperTest.isWithinAllowedWindow(
                delegationWindow,
                await weeklyWindowsHelperTest.timestampFromDate(2024, 1, i + 6), // Sunday
              ),
            ).to.be.false;
            expect(
              await weeklyWindowsHelperTest.isWithinAllowedWindow(
                undelegationWindow,
                await weeklyWindowsHelperTest.timestampFromDate(2024, 1, i + 6), // Sunday
              ),
            ).to.be.false;
          }
        });
      });

      describe("Time windows limitations", () => {
        before(async () => {
          await createAccountWithId(ID);
        });

        it("should revert if calling mintUsd not during delegation window", async () => {
          const monday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 6)).toNumber();
          await network.provider.send("evm_setNextBlockTimestamp", [monday]);

          await expect(mintUSD(ID, allowedPoolId, collateralType, depositAmount)).to.be.revertedWith(
            "outside delegation window",
          );
        });

        it("should revert if calling burnUsd outside of delegation and undelegation windows", async () => {
          const saturday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 11)).toNumber();
          await network.provider.send("evm_setNextBlockTimestamp", [saturday]);

          await expect(burnUSD(ID, allowedPoolId, collateralType, depositAmount)).to.be.revertedWith(
            "outside allowed windows",
          );
        });

        it("should revert if calling delegateCollateral outside of delegation and undelegation windows", async () => {
          const sunday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 12)).toNumber();
          await network.provider.send("evm_setNextBlockTimestamp", [sunday]);

          await expect(delegateCollateral(ID, allowedPoolId, collateralType, depositAmount)).to.be.revertedWith(
            "outside allowed windows",
          );
        });

        it("should revert if calling delegateCollateral not on behalf of manager during delegation window", async () => {
          const wednesday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 8)).toNumber();
          await network.provider.send("evm_setNextBlockTimestamp", [wednesday]);

          await expect(
            whitelistedPoolLogic
              .connect(deployments.owner)
              .execTransaction(
                synthetixV3CoreAddress,
                IVaultModule.encodeFunctionData("delegateCollateral", [
                  ID,
                  allowedPoolId,
                  collateralType,
                  depositAmount,
                  ONE_UNIT,
                ]),
              ),
          ).to.be.revertedWith("only manager or trader or public function");
        });

        it("should be able to delegate more collateral on behalf of manager during delegation window", async () => {
          const wednesday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 8)).toNumber();
          await network.provider.send("evm_setNextBlockTimestamp", [wednesday]);

          await depositCollateral(ID, collateralType, depositAmount);
          await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount.div(2));
        });

        it("should be able to undelegate collateral on behalf of manager during delegation window", async () => {
          const wednesday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 8)).toNumber();
          await network.provider.send("evm_setNextBlockTimestamp", [wednesday]);

          await depositCollateral(ID, collateralType, depositAmount);
          await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
          await delegateCollateral(ID, allowedPoolId, collateralType, 0);
        });

        it("should revert if delegating more collateral during undelegation window", async () => {
          const thursday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 10)).toNumber() - 3600;
          await network.provider.send("evm_setNextBlockTimestamp", [thursday]);

          await depositCollateral(ID, collateralType, depositAmount);
          await expect(delegateCollateral(ID, allowedPoolId, collateralType, depositAmount)).to.be.revertedWith(
            "only undelegation allowed",
          );
        });

        it("should revert if undelegating leads to more available collateral than withdrawal limit during undelegation window", async () => {
          await deployments.assetHandler.setChainlinkTimeout(86400 * 400); // 400 days expiry

          const wednesday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 8)).toNumber();
          await network.provider.send("evm_setNextBlockTimestamp", [wednesday]);

          await depositCollateral(ID, collateralType, depositAmount);
          await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);

          const thursday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 10)).toNumber() - 3600;
          await network.provider.send("evm_setNextBlockTimestamp", [thursday]);

          await expect(delegateCollateral(ID, allowedPoolId, collateralType, 0)).to.be.revertedWith(
            "undelegation limit breached",
          );
        });

        it("should be able to undelegate collateral on behalf of anyone during undelegation window", async () => {
          await deployments.assetHandler.setChainlinkTimeout(86400 * 400); // 400 days expiry

          const wednesday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 8)).toNumber();
          await network.provider.send("evm_setNextBlockTimestamp", [wednesday]);

          await depositCollateral(ID, collateralType, depositAmount);
          await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);

          const thursday = (await weeklyWindowsHelperTest.timestampFromDate(2025, 1, 10)).toNumber() - 3600;
          await network.provider.send("evm_setNextBlockTimestamp", [thursday]);

          await whitelistedPoolLogic
            .connect(deployments.owner)
            .execTransaction(
              synthetixV3CoreAddress,
              IVaultModule.encodeFunctionData("delegateCollateral", [
                ID,
                allowedPoolId,
                collateralType,
                depositAmount.sub(ONE_UNIT),
                ONE_UNIT,
              ]),
            );
        });
      });
    });
  });
};
