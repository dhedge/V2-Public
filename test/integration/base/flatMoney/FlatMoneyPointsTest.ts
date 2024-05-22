import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { baseChainData } from "../../../../config/chainData/baseData";
import {
  FlatMoneyDelayedOrderContractGuard,
  IDelayerOrder,
  IDelayerOrder__factory,
  IERC20,
  IPointsModule,
  IPointsModule__factory,
  PoolLogic,
  PoolManagerLogic,
  IFlatcoinVault,
  IFlatcoinVault__factory,
  IStableModule,
  IStableModule__factory,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import {
  IBackboneDeployments,
  IERC20Path,
  deployBackboneContracts,
  iERC20,
} from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";
import { deployFlatMoneyInfrastructure, IFlatMoneyTestParams } from "./flatMoneyTestDeploymentHelpers";
import { getAccountToken } from "../../utils/getAccountTokens";
import { currentBlockTimestamp, units } from "../../../testHelpers";

const delayedOrderInterface = new ethers.utils.Interface(IDelayerOrder__factory.abi);

const KEEPER_FEE = "299086318601533";
const TOTAL_POINTS_MINTED = units(21_000_000);

const testParams: IFlatMoneyTestParams = {
  ...baseChainData,
  ...baseChainData.flatMoney,
  UNIT: {
    address: baseChainData.assets.unit,
  },
  collateralAsset: {
    address: baseChainData.assets.reth,
    priceFeed: baseChainData.usdPriceFeeds.eth,
    balanceOfSlot: baseChainData.assetsBalanceOfSlot.reth,
  },
};

describe("Flat Money Test", () => {
  let deployments: IBackboneDeployments;
  let delayedOrderGuard: FlatMoneyDelayedOrderContractGuard;
  let poolLogicProxy: PoolLogic;
  let poolManagerLogicProxy: PoolManagerLogic;
  let manager: SignerWithAddress;
  let collateralAsset: IERC20;
  let UNIT: IStableModule;
  let delayedOrder: IDelayerOrder;
  let pointsModule: IPointsModule;

  utils.beforeAfterReset(beforeEach, afterEach);

  before(async () => {
    deployments = await deployBackboneContracts(testParams);
    manager = deployments.manager;

    const { flatMoneyDelayedOrderContractGuard } = await deployFlatMoneyInfrastructure(deployments, testParams);

    delayedOrderGuard = flatMoneyDelayedOrderContractGuard;
    collateralAsset = <IERC20>await ethers.getContractAt(IERC20Path, testParams.collateralAsset.address);
    UNIT = <IStableModule>await ethers.getContractAt(IStableModule__factory.abi, testParams.UNIT.address);
    delayedOrder = <IDelayerOrder>await ethers.getContractAt(IDelayerOrder__factory.abi, testParams.delayedOrder);
    pointsModule = <IPointsModule>await ethers.getContractAt(IPointsModule__factory.abi, testParams.pointsModule);

    /* Test vault will contain collateral asset */
    const poolProxies = await createFund(
      deployments.poolFactory,
      deployments.owner,
      manager,
      [
        {
          asset: collateralAsset.address,
          isDeposit: true,
        },
        {
          asset: UNIT.address,
          isDeposit: true,
        },
      ],
      {
        performance: ethers.constants.Zero,
        management: ethers.constants.Zero,
      },
    );
    poolLogicProxy = poolProxies.poolLogicProxy;
    poolManagerLogicProxy = poolProxies.poolManagerLogicProxy;

    const ownerCollateralBalance = units(100);
    await getAccountToken(
      ownerCollateralBalance,
      deployments.owner.address,
      collateralAsset.address,
      testParams.collateralAsset.balanceOfSlot,
    );

    await collateralAsset.approve(poolLogicProxy.address, ownerCollateralBalance);
    await poolLogicProxy.deposit(collateralAsset.address, ownerCollateralBalance);
  });

  const approveAndAnnounceDeposit = async () => {
    await poolLogicProxy
      .connect(manager)
      .execTransaction(
        collateralAsset.address,
        iERC20.encodeFunctionData("approve", [testParams.delayedOrder, units(100)]),
      );
    await poolLogicProxy
      .connect(manager)
      .execTransaction(
        testParams.delayedOrder,
        delayedOrderInterface.encodeFunctionData("announceStableDeposit", [units(10), 0, KEEPER_FEE]),
      );
  };

  /* To work around delayed orders, this is a cheat function to mint UNIT to the vault */
  const mintoUNITIntoVault = async () => {
    const amountOfCollateralToDeposit = units(10);
    await getAccountToken(
      amountOfCollateralToDeposit,
      testParams.delayedOrder,
      collateralAsset.address,
      testParams.collateralAsset.balanceOfSlot,
    );
    const delayerOrderAddress = await utils.impersonateAccount(testParams.delayedOrder);
    const executableAtTime = (await currentBlockTimestamp()) - 60 * 60 * 12; // Accept 12 hours maxAge for testing purposes
    await UNIT.connect(delayerOrderAddress).executeDeposit(poolLogicProxy.address, executableAtTime, {
      depositAmount: amountOfCollateralToDeposit,
      minAmountOut: 0,
    });
    const amountMinted = await UNIT.balanceOf(poolLogicProxy.address);
    return amountMinted;
  };

  const announceWithdraw = async () => {
    const amountMinted = await mintoUNITIntoVault();

    await poolLogicProxy
      .connect(manager)
      .execTransaction(
        testParams.delayedOrder,
        delayedOrderInterface.encodeFunctionData("announceStableWithdraw", [amountMinted, 0, KEEPER_FEE]),
      );
  };

  const mintPointsIntoVault = async () => {
    const vault = <IFlatcoinVault>await ethers.getContractAt(IFlatcoinVault__factory.abi, await pointsModule.vault());
    const ownerAddress = await vault.owner();
    const owner = await utils.impersonateAccount(ownerAddress);
    await pointsModule.connect(owner).mintTo({
      to: poolLogicProxy.address,
      amount: TOTAL_POINTS_MINTED,
    });
  };

  it("should revert if caller is not pool logic", async () => {
    await expect(
      delayedOrderGuard.txGuard(poolManagerLogicProxy.address, testParams.delayedOrder, []),
    ).to.be.revertedWith("not pool logic");
  });

  it("should be able to announce stable deposit", async () => {
    await approveAndAnnounceDeposit();

    const existingOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
    expect(existingOrder.orderType).to.equal(1);
  });

  it("should revert if announcing stable deposit when UNIT is disabled", async () => {
    await poolManagerLogicProxy.connect(manager).changeAssets([], [UNIT.address]);

    await expect(
      poolLogicProxy
        .connect(manager)
        .execTransaction(
          testParams.delayedOrder,
          delayedOrderInterface.encodeFunctionData("announceStableDeposit", [units(100), 0, KEEPER_FEE]),
        ),
    ).to.be.revertedWith("unsupported destination asset");
  });

  it("should be able to announce stable withdraw", async () => {
    await announceWithdraw();

    const existingOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
    expect(existingOrder.orderType).to.equal(2);
  });

  it("should revert if announcing stable withdraw when collateral asset is disabled", async () => {
    const { poolLogicProxy: newPoolWithCollateralAssetDisabled } = await createFund(
      deployments.poolFactory,
      deployments.owner,
      manager,
      [
        {
          asset: UNIT.address,
          isDeposit: true,
        },
      ],
    );

    await expect(
      newPoolWithCollateralAssetDisabled
        .connect(manager)
        .execTransaction(
          testParams.delayedOrder,
          delayedOrderInterface.encodeFunctionData("announceStableWithdraw", [units(100), 0, KEEPER_FEE]),
        ),
    ).to.be.revertedWith("unsupported destination asset");
  });

  it("should be able to cancel pending order", async () => {
    await approveAndAnnounceDeposit();

    await utils.increaseTime(600); // 10 minutes

    await poolLogicProxy
      .connect(manager)
      .execTransaction(
        testParams.delayedOrder,
        delayedOrderInterface.encodeFunctionData("cancelExistingOrder", [poolLogicProxy.address]),
      );
    const existingOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
    expect(existingOrder.orderType).to.equal(0);
  });

  it("should revert if removing UNIT after stable deposit order announced", async () => {
    await approveAndAnnounceDeposit();

    await expect(poolManagerLogicProxy.connect(manager).changeAssets([], [UNIT.address])).to.be.revertedWith(
      "order in progress",
    );
  });

  it("should revert if removing collateral asset after stable withdraw order announced", async () => {
    await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(deployments.owner.address));
    await announceWithdraw();

    await expect(poolManagerLogicProxy.connect(manager).changeAssets([], [collateralAsset.address])).to.be.revertedWith(
      "order in progress",
    );
  });

  it("should not be able to deposit into the vault if stable deposit order announced", async () => {
    await approveAndAnnounceDeposit();

    await expect(poolLogicProxy.deposit(collateralAsset.address, units(100))).to.be.revertedWith("order in progress");
  });

  it("should not be able to deposit into the vault if stable withdraw order announced", async () => {
    await announceWithdraw();

    await expect(poolLogicProxy.deposit(collateralAsset.address, units(100))).to.be.revertedWith("order in progress");
  });

  it("should not be able to withdraw from the vault if stable deposit order announced", async () => {
    await approveAndAnnounceDeposit();

    await expect(poolLogicProxy.withdraw(units(100))).to.be.revertedWith("order in progress");
  });

  it("should not be able to withdraw from the vault if stable withdraw order announced", async () => {
    await announceWithdraw();

    await expect(poolLogicProxy.withdraw(units(100))).to.be.revertedWith("order in progress");
  });

  it("should correctly account for UNIT in the vault", async () => {
    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
    const amountOfUNITDeposited = await mintoUNITIntoVault();

    const valueOfUNITDeposited = await poolManagerLogicProxy["assetValue(address,uint256)"](
      UNIT.address,
      amountOfUNITDeposited,
    );
    const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValueAfter).to.equal(totalFundValueBefore.add(valueOfUNITDeposited));
  });

  it("should be able to withdraw from the vault after 1 year and receive correct amount of UNIT and FMP", async () => {
    await deployments.assetHandler.setChainlinkTimeout(86400 * 400); // 400 days expiry

    const amountOfUNITDeposited = await mintoUNITIntoVault();
    await mintPointsIntoVault();

    const unitBalanceBefore = await UNIT.balanceOf(deployments.owner.address);
    const pointsBalanceBefore = await pointsModule.balanceOf(deployments.owner.address);
    const pointsBalanceInVaultBefore = await pointsModule.balanceOf(poolLogicProxy.address);

    expect(unitBalanceBefore).to.equal(0);
    expect(pointsBalanceBefore).to.equal(0);
    expect(pointsBalanceInVaultBefore).to.equal(TOTAL_POINTS_MINTED);

    utils.increaseTime(86400 * 365); // 365 days

    await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(deployments.owner.address));

    const unitBalanceAfter = await UNIT.balanceOf(deployments.owner.address);
    const pointsBalanceAfter = await pointsModule.balanceOf(deployments.owner.address);
    const pointsBalanceInVaultAfter = await pointsModule.balanceOf(poolLogicProxy.address);

    expect(unitBalanceAfter).to.equal(unitBalanceBefore.add(amountOfUNITDeposited));
    expect(pointsBalanceAfter).to.equal(TOTAL_POINTS_MINTED);
    expect(pointsBalanceInVaultAfter).to.equal(0);
  });

  it("should be able to withdraw from the vault after half a year and receive correct amount of UNIT and FMP", async () => {
    await deployments.assetHandler.setChainlinkTimeout(86400 * 400); // 400 days expiry

    const amountOfUNITDeposited = await mintoUNITIntoVault();
    await mintPointsIntoVault();

    const unitBalanceBefore = await UNIT.balanceOf(deployments.owner.address);
    const pointsBalanceBefore = await pointsModule.balanceOf(deployments.owner.address);
    const pointsBalanceInVaultBefore = await pointsModule.balanceOf(poolLogicProxy.address);

    expect(unitBalanceBefore).to.equal(0);
    expect(pointsBalanceBefore).to.equal(0);
    expect(pointsBalanceInVaultBefore).to.equal(TOTAL_POINTS_MINTED);

    utils.increaseTime(86400 * 182.5);

    await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(deployments.owner.address));

    const unitBalanceAfter = await UNIT.balanceOf(deployments.owner.address);
    const pointsBalanceAfter = await pointsModule.balanceOf(deployments.owner.address);
    const pointsBalanceInVaultAfter = await pointsModule.balanceOf(poolLogicProxy.address);

    expect(unitBalanceAfter).to.equal(unitBalanceBefore.add(amountOfUNITDeposited));
    expect(pointsBalanceAfter).to.be.closeTo(TOTAL_POINTS_MINTED.div(2), pointsBalanceAfter.div(100_000)); // 0.001%
    expect(pointsBalanceInVaultAfter).to.equal(0);
  });
});
