import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumberish } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { IBackboneDeployments, deployBackboneContracts } from "../../utils/deployContracts/deployBackboneContracts";
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
  IMulticallModule__factory,
  PoolManagerLogic,
  PoolManagerLogic__factory,
  IIssueUSDModule__factory,
  SynthetixV3AssetGuard,
  SynthetixV3AssetGuard__factory,
} from "../../../../types";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { deploySynthethixV3Infrastructure } from "./synthetixV3TestDeploymentHelpers";

const IAccountModule = new ethers.utils.Interface(IAccountModule__factory.abi);
const ICollateralModule = new ethers.utils.Interface(ICollateralModule__factory.abi);
const IVaultModule = new ethers.utils.Interface(IVaultModule__factory.abi);
const IMulticallModule = new ethers.utils.Interface(IMulticallModule__factory.abi);
const IIssueUSDModule = new ethers.utils.Interface(IIssueUSDModule__factory.abi);

const chainData = {
  assets: ovmChainData.assets,
  usdPriceFeeds: ovmChainData.price_feeds,
};

const SYNTHETIX_ACCOUNT_NFT_TYPE = ethers.utils.solidityKeccak256(["address"], [ovmChainData.synthetix.accountNFT]);
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

  utils.beforeAfterReset(beforeEach, afterEach);
  utils.beforeAfterReset(before, after);

  before(async () => {
    deployments = await deployBackboneContracts(chainData);
    infrastructureData = await deploySynthethixV3Infrastructure(deployments);

    manager = deployments.manager;
    whitelistedPoolLogic = infrastructureData.whitelistedPool.poolLogicProxy;
    whitelistedManagerLogic = infrastructureData.whitelistedPool.poolManagerLogicProxy;
    poolAddress = whitelistedPoolLogic.address;
    synthetixV3CoreAddress = infrastructureData.synthetixV3CoreAddress;
    allowedPoolId = infrastructureData.allowedLiquidityPoolId;
    collateralType = infrastructureData.SNX.address;
    debtAsset = infrastructureData.snxUSD.address;
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
    leverage = units(1),
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
    const amount = units(1_000);
    await infrastructureData.SNX.approve(synthetixV3CoreAddress, amount);
    await synthetixV3CoreCollateralModule["deposit"](ID, collateralType, amount);
    await synthetixV3CoreVaultModule["delegateCollateral"](ID, allowedPoolId, collateralType, amount, units(1));
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

    it("should revert when trying to create Synthetix V3 NFT account if pool already has received one through airdrop", async () => {
      await ownerCreatesPositionAndTransfersItToPool();

      await expect(createAccount()).to.be.revertedWith("only one account allowed");
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
      const depositAmount = units(1_000);
      await depositCollateral(id, collateralType, depositAmount);
      await delegateCollateral(id, allowedPoolId, collateralType, depositAmount.div(2));
      const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

      const airdroppedId = await ownerCreatesPositionAndTransfersItToPool();

      const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
      expect(totalValueBefore).to.equal(totalValueAfter);

      await expect(depositCollateral(airdroppedId, collateralType, units(100))).to.be.revertedWith(
        "account not owned by pool",
      );
      await expect(delegateCollateral(airdroppedId, allowedPoolId, collateralType, units(100))).to.be.revertedWith(
        "account not owned by pool",
      );
      await expect(mintUSD(airdroppedId, allowedPoolId, collateralType, units(100))).to.be.revertedWith(
        "account not owned by pool",
      );
      await expect(burnUSD(airdroppedId, allowedPoolId, collateralType, units(100))).to.be.revertedWith(
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
      const depositAmount = units(10_000);
      await depositCollateral(ID, collateralType, depositAmount);

      await infrastructureData.whitelistedPool.poolManagerLogicProxy
        .connect(manager)
        .changeAssets([], [collateralType]);

      await expect(withdrawCollateral(ID, collateralType, depositAmount)).to.be.revertedWith(
        "collateral asset must be enabled",
      );
    });

    it("should revert if trying to borrow snxUSD against unsupported lp/using unsupported collateral", async () => {
      await createAccountWithId(ID);
      const depositAmount = units(5_000);
      await depositCollateral(ID, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);

      await expect(mintUSD(ID, 0, collateralType, depositAmount)).to.be.revertedWith("lp not allowed");
      await expect(mintUSD(ID, allowedPoolId, deployments.assets.USDC.address, depositAmount)).to.be.revertedWith(
        "unsupported collateral type",
      );
    });

    it("should revert when calling afterTxGuard on SynthetixV3ContractGuard not on behalf of the pool", async () => {
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
    });
  });

  describe("Outflow of funds", () => {
    it("shouldn't allow to deposit into any other account not owned by pool", async () => {
      await createAccount();
      await expect(depositCollateral(ID, collateralType, units(1_000))).to.be.revertedWith("account not owned by pool");
    });

    it("shouldn't allow to deposit with unsupported collateral type", async () => {
      await createAccountWithId(ID);
      await expect(depositCollateral(ID, deployments.assets.USDC.address, units(1_000, 6))).to.be.revertedWith(
        "unsupported collateral type",
      );
    });

    it("shouldn't allow to delegate collateral using unsupported leverage/into unknown lp/using unsupported collateral", async () => {
      await createAccountWithId(ID);
      const depositAmount = units(1_000);
      await depositCollateral(ID, collateralType, depositAmount);

      await expect(delegateCollateral(ID, allowedPoolId, collateralType, depositAmount, units(2))).to.be.revertedWith(
        "unsupported leverage",
      );
      await expect(delegateCollateral(ID, 0, collateralType, depositAmount)).to.be.revertedWith("lp not allowed");
      await expect(
        delegateCollateral(ID, allowedPoolId, deployments.assets.USDC.address, units(1_000, 6)),
      ).to.be.revertedWith("unsupported collateral type");
    });

    it("shouldn't allow to burn any other position's debt with its own snxUSD", async () => {
      await createAccountWithId(ID);
      const depositAmount = units(5_000);
      await depositCollateral(ID, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
      const desiredAmountToBorrow = units(2_000);
      await mintUSD(ID, allowedPoolId, collateralType, desiredAmountToBorrow);

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
      const collateralBalanceBefore = await infrastructureData.SNX.balanceOf(poolAddress);

      await createAccountWithId(ID);
      const depositAmount = units(1_000);
      await depositCollateral(ID, collateralType, depositAmount);

      const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
      const collateralBalanceAfter = await infrastructureData.SNX.balanceOf(poolAddress);

      expect(collateralBalanceBefore).to.equal(collateralBalanceAfter.add(depositAmount));
      expect(totalValueBefore).to.equal(totalValueAfter);
    });

    it("should be able to delegate collateral into supported liquidity pool", async () => {
      const totalValueBefore = await whitelistedManagerLogic.totalFundValue();
      const collateralBalanceBefore = await infrastructureData.SNX.balanceOf(poolAddress);

      await createAccountWithId(ID);
      const depositAmount = units(1_000);
      await depositCollateral(ID, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount.div(2));

      const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
      const collateralBalanceAfter = await infrastructureData.SNX.balanceOf(poolAddress);

      expect(collateralBalanceBefore).to.equal(collateralBalanceAfter.add(depositAmount));
      expect(totalValueBefore).to.equal(totalValueAfter);
    });

    it("should be able to borrow snxUSD against deposited collateral", async () => {
      const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

      await createAccountWithId(ID);
      const depositAmount = units(5_000);
      await depositCollateral(ID, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
      const desiredAmountToBorrow = units(2_000);
      await mintUSD(ID, allowedPoolId, collateralType, desiredAmountToBorrow);

      const synthetixV3CoreCollateralModule = <ICollateralModule>(
        await ethers.getContractAt(ICollateralModule__factory.abi, synthetixV3CoreAddress)
      );
      expect(
        await synthetixV3CoreCollateralModule.getAccountAvailableCollateral(ID, infrastructureData.snxUSD.address),
      ).to.equal(desiredAmountToBorrow);

      const totalValueAfter = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
      expect(totalValueAfter).to.be.closeTo(totalValueBefore, totalValueBefore.div(10000)); // 0.01%
    });

    it("should be able to repay snxUSD debt", async () => {
      await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry

      const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

      await createAccountWithId(ID);
      const depositAmount = units(5_000);
      await depositCollateral(ID, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
      const desiredAmountToBorrow = units(2_000);
      await mintUSD(ID, allowedPoolId, collateralType, desiredAmountToBorrow);

      await utils.increaseTime(86400); // 24 hours

      await burnUSD(ID, allowedPoolId, collateralType, desiredAmountToBorrow.div(2));

      const totalValueAfter = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
      expect(totalValueAfter).to.be.closeTo(totalValueBefore, totalValueBefore.div(10000)); // 0.01%
    });

    it("should be able to undelegate collateral from supported liquidity pool", async () => {
      const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

      await createAccountWithId(ID);
      const depositAmount = units(1_000);
      await depositCollateral(ID, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, 0);

      const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
      expect(totalValueBefore).to.equal(totalValueAfter);
    });

    it("should be able to withdraw undelegated collateral from owned Synthetix V3 NFT account", async () => {
      const totalValueBefore = await whitelistedManagerLogic.totalFundValue();
      const collateralBalanceBefore = await infrastructureData.SNX.balanceOf(poolAddress);

      await createAccountWithId(ID);
      const depositAmount = units(1_000);
      await depositCollateral(ID, collateralType, depositAmount);
      await withdrawCollateral(ID, collateralType, depositAmount);

      const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
      const collateralBalanceAfter = await infrastructureData.SNX.balanceOf(poolAddress);

      expect(collateralBalanceBefore).to.equal(collateralBalanceAfter);
      expect(totalValueBefore).to.equal(totalValueAfter);
    });

    it("should be able to withdraw once delegated collateral from owned Synthetix V3 NFT account", async () => {
      await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry

      const totalValueBefore = await whitelistedManagerLogic.totalFundValue();
      const collateralBalanceBefore = await infrastructureData.SNX.balanceOf(poolAddress);

      await createAccountWithId(ID);
      const depositAmount = units(1_000);
      await depositCollateral(ID, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, 0);

      await expect(withdrawCollateral(ID, collateralType, depositAmount)).to.be.reverted; // AccountActivityTimeoutPending
      await utils.increaseTime(86400); // 24 hours
      await withdrawCollateral(ID, collateralType, depositAmount);

      const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
      const collateralBalanceAfter = await infrastructureData.SNX.balanceOf(poolAddress);

      expect(collateralBalanceBefore).to.equal(collateralBalanceAfter);
      expect(totalValueBefore).to.equal(totalValueAfter);
    });

    it("should be able to withdraw/deposit debt asset from/to owned Synthetix V3 NFT account", async () => {
      await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry

      const totalValueBefore = await whitelistedManagerLogic.totalFundValue();

      await createAccountWithId(ID);
      const depositAmount = units(5_000);
      await depositCollateral(ID, collateralType, depositAmount);
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
      const desiredAmountToBorrow = units(2_000);
      await mintUSD(ID, allowedPoolId, collateralType, desiredAmountToBorrow);
      await utils.increaseTime(86400); // 24 hours
      await withdrawCollateral(ID, debtAsset, desiredAmountToBorrow);
      // Manager approves snxUSD to be spent by SynthetixV3Core
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

    it("should be able to create an account using multicall", async () => {
      const createAccountData = IAccountModule.encodeFunctionData("createAccount(uint128)", [ID]);
      const multicallData = IMulticallModule.encodeFunctionData("multicall", [[createAccountData]]);
      await whitelistedPoolLogic.connect(manager).execTransaction(synthetixV3CoreAddress, multicallData);
    });

    it("should revert when using multicall with account creation tx data due to how ITxTrackingGuard works", async () => {
      const amount = units(1_000);
      const leverage = units(1);
      const createAccountData = IAccountModule.encodeFunctionData("createAccount(uint128)", [ID]);
      const depositCollateralData = ICollateralModule.encodeFunctionData("deposit", [ID, collateralType, amount]);
      const delegateCollateralData = IVaultModule.encodeFunctionData("delegateCollateral", [
        ID,
        allowedPoolId,
        collateralType,
        amount,
        leverage,
      ]);
      const multicallData = IMulticallModule.encodeFunctionData("multicall", [
        [createAccountData, depositCollateralData, delegateCollateralData],
      ]);
      await expect(
        whitelistedPoolLogic.connect(manager).execTransaction(synthetixV3CoreAddress, multicallData),
      ).to.be.revertedWith("account not owned by pool");
    });
    it("should be able to use multicall when account is already created", async () => {
      await createAccountWithId(ID);
      const amount = units(1_000);
      const leverage = units(1);
      const depositCollateralData = ICollateralModule.encodeFunctionData("deposit", [ID, collateralType, amount]);
      const delegateCollateralData = IVaultModule.encodeFunctionData("delegateCollateral", [
        ID,
        allowedPoolId,
        collateralType,
        amount,
        leverage,
      ]);
      const mintUsdData = IIssueUSDModule.encodeFunctionData("mintUsd", [
        ID,
        allowedPoolId,
        collateralType,
        units(100),
      ]);
      const multicallData = IMulticallModule.encodeFunctionData("multicall", [
        [depositCollateralData, delegateCollateralData, mintUsdData],
      ]);
      await whitelistedPoolLogic.connect(manager).execTransaction(synthetixV3CoreAddress, multicallData);
    });
  });

  describe("Investor's perspective", () => {
    beforeEach(async () => {
      await deployments.assetHandler.setChainlinkTimeout(86400 * 7); // 7 days expiry
    });

    it("should receive zero portion of Synthetix V3 position during withdraw if position is enabled but has no value", async () => {
      const synthetixV3AssetGuard = <SynthetixV3AssetGuard>(
        await ethers.getContractAt(SynthetixV3AssetGuard__factory.abi, infrastructureData.synthetixV3AssetGuardAddress)
      );
      expect(await synthetixV3AssetGuard.getBalance(poolAddress, synthetixV3CoreAddress)).to.equal(0);

      const ownerSnxBalanceBefore = await infrastructureData.SNX.balanceOf(deployments.owner.address);
      await createAccount();

      expect(await synthetixV3AssetGuard.getBalance(poolAddress, synthetixV3CoreAddress)).to.equal(0);

      await utils.increaseTime(86400); // 24 hours

      // Owner is the only investor in the pool
      const amountToWithdraw = await whitelistedPoolLogic.balanceOf(deployments.owner.address);
      await whitelistedPoolLogic.withdraw(amountToWithdraw);
      const ownerSnxBalanceAfter = await infrastructureData.SNX.balanceOf(deployments.owner.address);
      expect(ownerSnxBalanceAfter).to.equal(ownerSnxBalanceBefore.add(infrastructureData.snxBalanceInPool));
    });

    it("should receive a portion of undelegated collateral during withdraw when snxUSD is minted", async () => {
      const ownerSnxBalanceBefore = await infrastructureData.SNX.balanceOf(deployments.owner.address);

      await createAccountWithId(ID);
      // Deposit all SNX in the pool into Synthetix V3 NFT Account
      const depositAmount = infrastructureData.snxBalanceInPool;
      await depositCollateral(ID, collateralType, depositAmount);
      // Delegate half of it to the pool
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount.div(2));
      const borrowAmount = units(1_000);
      await mintUSD(ID, allowedPoolId, collateralType, borrowAmount);

      await utils.increaseTime(86400); // 24 hours

      const totalValueBeforeWithdraw = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
      const ownerPoolTokenBalanceBefore = await whitelistedPoolLogic.balanceOf(deployments.owner.address);
      // Withdraw 50% of the pool tokens
      const tokensToWithdraw = ownerPoolTokenBalanceBefore.div(2);
      await whitelistedPoolLogic.withdraw(tokensToWithdraw);
      const totalValueAfterWithdraw = await whitelistedManagerLogic.callStatic.totalFundValueMutable();
      const ownerSnxBalanceAfter = await infrastructureData.SNX.balanceOf(deployments.owner.address);

      // Asserting that pool's TVL decreased by 50% after withdraw as pool has only one investor
      expect(totalValueAfterWithdraw).to.be.closeTo(
        totalValueBeforeWithdraw.div(2),
        totalValueBeforeWithdraw.div(100000), // 0.001%
      );

      // It's safe to get tokenPrice right after withdraw as AssetGuard has fresh debt value stored
      const tokenPrice = await whitelistedPoolLogic.tokenPrice();
      const snxWithdrawnValue = tokensToWithdraw.mul(tokenPrice).div(units(1));
      const snxPrice = await whitelistedManagerLogic["assetValue(address,uint256)"](collateralType, units(1));
      const estimatedSnxReceived = snxWithdrawnValue.mul(units(1)).div(snxPrice);

      // Asserting that investor received correct portion of SNX
      expect(ownerSnxBalanceAfter).to.equal(ownerSnxBalanceBefore.add(estimatedSnxReceived));
    });

    it("should receive a portion of undelegated collateral during withdraw when debt is zero", async () => {
      const ownerSnxBalanceBefore = await infrastructureData.SNX.balanceOf(deployments.owner.address);

      await createAccountWithId(ID);
      // Deposit all SNX in the pool into Synthetix V3 NFT Account
      const depositAmount = infrastructureData.snxBalanceInPool;
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
      const ownerSnxBalanceAfter = await infrastructureData.SNX.balanceOf(deployments.owner.address);

      // Asserting that pool's TVL decreased by 50% after withdraw as pool has only one investor
      expect(totalValueAfterWithdraw).to.be.closeTo(
        totalValueBeforeWithdraw.div(2),
        totalValueBeforeWithdraw.div(100000), // 0.001%
      );

      // It's safe to get tokenPrice right after withdraw as AssetGuard has fresh debt value stored
      const tokenPrice = await whitelistedPoolLogic.tokenPrice();
      const snxWithdrawnValue = tokensToWithdraw.mul(tokenPrice);
      const snxPrice = await whitelistedManagerLogic["assetValue(address,uint256)"](collateralType, units(1));
      const estimatedSnxReceived = snxWithdrawnValue.div(snxPrice);

      // Asserting that investor received correct portion of SNX
      expect(ownerSnxBalanceAfter).to.equal(ownerSnxBalanceBefore.add(estimatedSnxReceived));
    });

    it("should not be able to withdraw if available undelegated collateral is not enough to make a withdraw", async () => {
      await createAccountWithId(ID);
      // Deposit all SNX in the pool into Synthetix V3 NFT Account
      const depositAmount = infrastructureData.snxBalanceInPool;
      await depositCollateral(ID, collateralType, depositAmount);
      // Delegate all of it to the pool
      await delegateCollateral(ID, allowedPoolId, collateralType, depositAmount);
      const borrowAmount = units(1_000);
      await mintUSD(ID, allowedPoolId, collateralType, borrowAmount);

      await utils.increaseTime(86400); // 24 hours

      // Withdraw 50% of the pool tokens
      const tokensToWithdraw = (await whitelistedPoolLogic.balanceOf(deployments.owner.address)).div(2);
      await expect(whitelistedPoolLogic.withdraw(tokensToWithdraw)).to.be.revertedWith("not enough available balance");
    });
  });
});
