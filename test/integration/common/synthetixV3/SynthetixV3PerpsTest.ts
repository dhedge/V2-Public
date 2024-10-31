import { expect } from "chai";
import { ethers, network } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  IBackboneDeployments,
  IERC20Path,
  deployBackboneContracts,
} from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";

import {
  PoolLogic,
  IAccountModule__factory,
  IAccountModule,
  IPerpsAccountModule,
  IPerpsAccountModule__factory,
  PoolManagerLogic,
  IERC721Enumerable,
  IAtomicOrderModule,
  IAsyncOrderModule,
  IAsyncOrderModule__factory,
  IAtomicOrderModule__factory,
  IAsyncOrderSettlementPythModule,
  IAsyncOrderSettlementPythModule__factory,
  IWrapperModule,
  IWrapperModule__factory,
  IERC20,
} from "../../../../types";
import { deploySynthethixV3Infrastructure } from "./synthetixV3TestDeploymentHelpers";

import NodeModuleModified from "./NodeModuleModified.json";
import { units } from "../../../testHelpers";
import { updatePythPriceFeed } from "../../utils/pyth";
import { ISynthetixV3TestsParams } from "./SynthetixV3Test";

const IAccountModule = new ethers.utils.Interface(IAccountModule__factory.abi);
const IPerpsAccountModule = new ethers.utils.Interface(IPerpsAccountModule__factory.abi);
const IAtomicOrderModule = new ethers.utils.Interface(IAtomicOrderModule__factory.abi);
const IAsyncOrderModule = new ethers.utils.Interface(IAsyncOrderModule__factory.abi);
const IAsyncOrderSettlementPythModule = new ethers.utils.Interface(IAsyncOrderSettlementPythModule__factory.abi);
const IWrapperModule = new ethers.utils.Interface(IWrapperModule__factory.abi);

const REFERRER_ADDRESS = ethers.constants.AddressZero;

export type ISynthetixV3PerpsTestsParams = ISynthetixV3TestsParams & {
  synthMarketId: number;
  perpMarketId: number;
  synthetixPerpsAccountNFT: string;
  synthetixV3PerpsMarket: string;
  asyncSettlementModule: string;
  systemAssets: {
    withdrawalAsset: {
      address: string;
      usdPriceFeed: string;
      decimals: number;
    };
  };
  pyth: { contract: string; priceFeedId: string };
};

export const launchSynthetixV3PerpsTests = (chainData: ISynthetixV3PerpsTestsParams) => {
  const SYNTHETIX_PERPS_ACCOUNT_NFT_TYPE = ethers.utils.solidityKeccak256(
    ["address"],
    [chainData.synthetixPerpsAccountNFT],
  );
  const ID = 1234567890;

  describe("SynthetixV3Perps", () => {
    let deployments: IBackboneDeployments;
    let infrastructureData: Awaited<ReturnType<typeof deploySynthethixV3Infrastructure>>;

    let manager: SignerWithAddress;
    let whitelistedPoolLogic: PoolLogic;
    let whitelistedManagerLogic: PoolManagerLogic;
    let poolAddress: string;
    let synthetixV3PerpsAddress: string;
    let accountNFT: IERC721Enumerable;
    let depositAmount: BigNumber;

    utils.beforeAfterReset(beforeEach, afterEach);
    utils.beforeAfterReset(before, after);

    before(async () => {
      if (chainData.deployedNodeModule) {
        const modifiedBytecode = NodeModuleModified.deployedBytecode;
        await network.provider.send("hardhat_setCode", [chainData.deployedNodeModule, modifiedBytecode]);
      }
      deployments = await deployBackboneContracts(chainData);
      infrastructureData = await deploySynthethixV3Infrastructure(deployments, chainData);
      accountNFT = <IERC721Enumerable>(
        await ethers.getContractAt(
          "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol:IERC721Enumerable",
          chainData.synthetixPerpsAccountNFT,
        )
      );
      manager = deployments.manager;
      whitelistedPoolLogic = infrastructureData.whitelistedPool.poolLogicProxy;
      whitelistedManagerLogic = infrastructureData.whitelistedPool.poolManagerLogicProxy;
      poolAddress = whitelistedPoolLogic.address;
      synthetixV3PerpsAddress = infrastructureData.synthetixV3PerpsAddress ?? "";
      depositAmount = infrastructureData.collateralBalanceInPool;
      await whitelistedPoolLogic
        .connect(deployments.manager)
        .execTransaction(
          infrastructureData.DEBT_ASSET.address,
          infrastructureData.iERC20.encodeFunctionData("approve", [
            synthetixV3PerpsAddress,
            ethers.constants.MaxUint256,
          ]),
        );
    });

    // Reusable functions
    const createAccount = async () =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(synthetixV3PerpsAddress, IAccountModule.encodeFunctionData("createAccount()", []));

    const createAccountWithId = async (id: number) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(synthetixV3PerpsAddress, IAccountModule.encodeFunctionData("createAccount(uint128)", [id]));

    const modifyCollateral = async (id: number, amount: BigNumberish, synthMarketId?: number) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          synthetixV3PerpsAddress,
          IPerpsAccountModule.encodeFunctionData("modifyCollateral", [
            id,
            synthMarketId ?? chainData.synthMarketId,
            amount,
          ]),
        );

    const getSUSD = async (amount: BigNumberish) =>
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          chainData.synthetixV3SpotMarket,
          IAtomicOrderModule.encodeFunctionData("sell", [
            chainData.allowedMarketIds[0].marketId,
            amount,
            amount,
            REFERRER_ADDRESS,
          ]),
        );

    const getUSDC = async (amount: BigNumber) => {
      const tokenToCollateralDecimals = chainData.systemAssets.tokenToCollateral?.decimals ?? 18;
      const precisionForConvertion = 10 ** (18 - tokenToCollateralDecimals);
      const minAmountReceived = amount.div(precisionForConvertion);
      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          chainData.synthetixV3SpotMarket,
          IWrapperModule.encodeFunctionData("unwrap", [
            chainData.allowedMarketIds[0].marketId,
            amount,
            minAmountReceived,
          ]),
        );
    };

    const commitOrder = async (id: number, amount: BigNumberish, leverage: number) => {
      const synthetixV3PerpsAsyncOrderModule = <IAsyncOrderModule>(
        await ethers.getContractAt(IAsyncOrderModule__factory.abi, synthetixV3PerpsAddress)
      );

      let { fillPrice } = await synthetixV3PerpsAsyncOrderModule.callStatic.computeOrderFees(
        chainData.perpMarketId,
        units(1),
      );

      const size = BigNumber.from(amount).mul(units(leverage)).div(fillPrice);

      ({ fillPrice } = await synthetixV3PerpsAsyncOrderModule.callStatic.computeOrderFees(
        chainData.perpMarketId,
        size,
      ));

      await whitelistedPoolLogic
        .connect(manager)
        .execTransaction(
          chainData.synthetixV3PerpsMarket,
          IAsyncOrderModule.encodeFunctionData("commitOrder", [
            [
              chainData.perpMarketId,
              id,
              size,
              0,
              fillPrice,
              ethers.utils.formatBytes32String("tracking"),
              REFERRER_ADDRESS,
            ],
          ]),
        );
    };

    const settleOrder = async (id: number) => {
      //This function doesn't throw an error, but doesn't settle an order
      const iAsyncOrderSettlementPythModule = <IAsyncOrderSettlementPythModule>(
        await ethers.getContractAt(IAsyncOrderSettlementPythModule__factory.abi, chainData.asyncSettlementModule)
      );

      await iAsyncOrderSettlementPythModule.connect(manager).settleOrder(id);
    };

    const getOrder = async (id: number) => {
      const synthetixV3PerpsAsyncOrderModule = <IAsyncOrderModule>(
        await ethers.getContractAt(IAsyncOrderModule__factory.abi, synthetixV3PerpsAddress)
      );

      return await synthetixV3PerpsAsyncOrderModule.callStatic.getOrder(id);
    };

    const getOpenPosition = async (id: number) => {
      const iPerpsAccountModule = <IPerpsAccountModule>(
        await ethers.getContractAt(IPerpsAccountModule__factory.abi, synthetixV3PerpsAddress)
      );

      return await iPerpsAccountModule.callStatic.getOpenPosition(id, chainData.perpMarketId);
    };

    describe("NFT Account and its permissions", () => {
      it("should be able to create Synthetix V3 Perps account and store it in dHEDGE NFT tracker contract", async () => {
        await createAccount();
        expect(await accountNFT.balanceOf(poolAddress)).to.equal(1);
        const id = await accountNFT.tokenOfOwnerByIndex(poolAddress, 0);
        const ids = await infrastructureData.dhedgeNftTrackerStorage.getAllUintIds(
          SYNTHETIX_PERPS_ACCOUNT_NFT_TYPE,
          poolAddress,
        );
        expect(ids.length).to.equal(1);
        expect(ids[0]).to.equal(id);
      });

      it("should be able to create Synthetix V3 Perps account with custom ID and store it in dHEDGE NFT tracker contract", async () => {
        await createAccountWithId(ID);
        expect(await accountNFT.balanceOf(poolAddress)).to.equal(1);
        const idCreated = await accountNFT.tokenOfOwnerByIndex(poolAddress, 0);
        expect(idCreated.toNumber()).to.equal(ID);
        const ids = await infrastructureData.dhedgeNftTrackerStorage.getAllUintIds(
          SYNTHETIX_PERPS_ACCOUNT_NFT_TYPE,
          poolAddress,
        );
        expect(ids.length).to.equal(1);
        expect(ids[0]).to.equal(ID);
      });

      it("should forbid creating more than 1 Synthetix V3 Perps account in the pool", async () => {
        await createAccount();
        await expect(createAccount()).to.be.revertedWith("only one account allowed");
        await expect(createAccountWithId(ID)).to.be.revertedWith("only one account allowed");
      });

      it("should not allow to create Synthetix V3 Perps account if Synthetix V3 perps market is not enabled in the pool", async () => {
        await whitelistedManagerLogic.connect(manager).changeAssets([], [synthetixV3PerpsAddress]);
        await expect(createAccount()).to.be.revertedWith("enable synthetix v3 perps market");
      });
    });

    describe("Collateral", () => {
      it("should not be able to add synth collateral to the account", async () => {
        await createAccountWithId(ID);

        // synthMarketId of 1 is sUSDC on Andromeda
        await expect(modifyCollateral(ID, depositAmount.div(2), 1)).to.be.revertedWith("unsupported synthMarketId");
      });

      it("should not be able to withdraw collateral (snxUSD) if it's an unsupported asset", async () => {
        await createAccountWithId(ID);
        await getSUSD(depositAmount);
        // deposit all to get balance of 0
        await modifyCollateral(ID, depositAmount);

        await infrastructureData.whitelistedPool.poolManagerLogicProxy
          .connect(manager)
          .changeAssets([], [infrastructureData.DEBT_ASSET.address]);

        await expect(modifyCollateral(ID, depositAmount.mul(-1))).to.be.revertedWith("unsupported asset as margin");
        // withdraw all
      });

      it("should add collateral (snxUSD) to the account", async () => {
        await createAccountWithId(ID);
        await getSUSD(depositAmount);
        const totalValueBefore = await whitelistedManagerLogic.totalFundValue();
        await modifyCollateral(ID, depositAmount.div(2));
        const sUSDBalance = await infrastructureData.DEBT_ASSET.balanceOf(poolAddress);
        const totalValueAfter = await whitelistedManagerLogic.totalFundValue();
        expect(sUSDBalance).eq(depositAmount.div(2));
        expect(totalValueAfter).to.be.closeTo(totalValueBefore, totalValueBefore.div(10000));
      });

      it("should remove collateral from the account", async () => {
        await createAccountWithId(ID);
        await getSUSD(depositAmount);
        await modifyCollateral(ID, depositAmount);
        await modifyCollateral(ID, depositAmount.div(2).mul(-1));
        const sUSDBalance = await infrastructureData.DEBT_ASSET.balanceOf(poolAddress);
        expect(sUSDBalance).eq(depositAmount.div(2));
      });
    });

    describe("Order", () => {
      it("should commit an order", async () => {
        await getSUSD(depositAmount);
        await createAccountWithId(ID);
        await modifyCollateral(ID, depositAmount);
        await commitOrder(ID, depositAmount, 1);
        const order = await getOrder(ID);
        expect(order[0]).gt(0);
        utils.delay(10);
        await updatePythPriceFeed(chainData.pyth.contract, chainData.pyth.priceFeedId, manager);
        await settleOrder(ID);
        console.log("open position", await getOpenPosition(ID));
      });

      it("should revert if leverage is too high", async () => {
        await getSUSD(depositAmount);
        await createAccountWithId(ID);
        await modifyCollateral(ID, depositAmount);
        await expect(commitOrder(ID, depositAmount, 6)).to.be.revertedWith("leverage must be less");
      });
    });

    describe("Withdrawal", () => {
      it("should not be able to withdraw if not enough withdraw asset in pool", async () => {
        await createAccountWithId(ID);
        //Keep 25% in collateral USDC
        await getSUSD(depositAmount.div(4).mul(3));
        await modifyCollateral(ID, depositAmount.div(4).mul(3));
        const remainingSUSDC = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);
        await getUSDC(remainingSUSDC);
        const ownerPoolTokenBalanceBefore = await whitelistedPoolLogic.balanceOf(deployments.owner.address);
        // Withdraw 50% of the pool tokens
        const tokensToWithdraw = ownerPoolTokenBalanceBefore.div(2);
        expect(whitelistedPoolLogic.withdraw(tokensToWithdraw)).to.revertedWith("not enough available balance_1");
      });

      it("should be able to withdraw if enough withdraw asset in pool", async () => {
        await createAccountWithId(ID);
        //Keep 25% in collateral USDC
        await getSUSD(depositAmount.div(4).mul(3));
        await modifyCollateral(ID, depositAmount.div(4).mul(3));
        const remainingSUSDC = await infrastructureData.COLLATERAL_ASSET.balanceOf(poolAddress);
        await getUSDC(remainingSUSDC);
        const ownerPoolTokenBalanceBefore = await whitelistedPoolLogic.balanceOf(deployments.owner.address);
        // Withdraw 10% of the pool tokens
        const tokensToWithdraw = ownerPoolTokenBalanceBefore.div(10);
        await whitelistedPoolLogic.withdraw(tokensToWithdraw);
        const WITHDRAWAL_ASSET = <IERC20>(
          await ethers.getContractAt(IERC20Path, chainData.systemAssets.withdrawalAsset.address)
        );
        const collateralBalance = (await WITHDRAWAL_ASSET.balanceOf(deployments.owner.address)).mul(
          10 ** (18 - chainData.systemAssets.withdrawalAsset.decimals),
        );
        //Order was not executed, so no change in pool value
        expect(collateralBalance).to.be.closeTo(
          depositAmount.div(10),
          depositAmount.div(10).div(10_000), // 0.01%
        );
      });
    });
  });
};
