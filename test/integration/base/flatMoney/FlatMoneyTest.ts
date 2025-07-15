import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { baseChainData } from "../../../../config/chainData/baseData";
import {
  FlatMoneyDelayedOrderContractGuard,
  IDelayedOrder,
  IDelayedOrder__factory,
  IERC20,
  IPointsModule,
  IPointsModule__factory,
  PoolLogic,
  PoolManagerLogic,
  IFlatcoinVault,
  IFlatcoinVault__factory,
  IStableModule,
  IStableModule__factory,
  ILeverageModule,
  ILeverageModule__factory,
  IOracleModule,
  IOracleModule__factory,
  DhedgeNftTrackerStorage,
  IERC20Extended,
  IERC721Enumerable,
  IERC721Enumerable__factory,
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
import { BigNumber } from "ethers";

const delayedOrderInterface = new ethers.utils.Interface(IDelayedOrder__factory.abi);

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
    priceFeed: baseChainData.usdPriceFeeds.reth,
    balanceOfSlot: baseChainData.assetsBalanceOfSlot.reth,
  },
  withdrawalAsset: {
    address: baseChainData.assets.usdc,
    priceFeed: baseChainData.usdPriceFeeds.usdc,
    balanceOfSlot: baseChainData.assetsBalanceOfSlot.usdc,
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
  let delayedOrder: IDelayedOrder;
  let pointsModule: IPointsModule;
  let leverageModule: ILeverageModule;
  let oracleModule: IOracleModule;

  utils.beforeAfterReset(beforeEach, afterEach);

  before(async () => {
    deployments = await deployBackboneContracts(testParams);
    manager = deployments.manager;

    collateralAsset = <IERC20>await ethers.getContractAt(IERC20Path, testParams.collateralAsset.address);
    UNIT = <IStableModule>await ethers.getContractAt(IStableModule__factory.abi, testParams.UNIT.address);
    delayedOrder = <IDelayedOrder>await ethers.getContractAt(IDelayedOrder__factory.abi, testParams.delayedOrder);
    pointsModule = <IPointsModule>await ethers.getContractAt(IPointsModule__factory.abi, testParams.pointsModule);
    leverageModule = <ILeverageModule>(
      await ethers.getContractAt(ILeverageModule__factory.abi, testParams.leverageModule)
    );
    oracleModule = <IOracleModule>await ethers.getContractAt(IOracleModule__factory.abi, testParams.oracleModule);

    /* Test vault will contain collateral asset */
    const poolProxies = await createFund(
      deployments.poolFactory,
      deployments.owner,
      manager,
      [
        {
          asset: testParams.assets.usdc,
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

    const { flatMoneyDelayedOrderContractGuard } = await deployFlatMoneyInfrastructure(deployments, testParams);
    delayedOrderGuard = flatMoneyDelayedOrderContractGuard;

    await poolManagerLogicProxy.connect(manager).changeAssets(
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
      [],
    );

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
    const delayedOrderAddress = await utils.impersonateAccount(testParams.delayedOrder);
    const executableAtTime = (await currentBlockTimestamp()) - 60 * 60 * 12; // Accept 12 hours maxAge for testing purposes
    await UNIT.connect(delayedOrderAddress).executeDeposit(poolLogicProxy.address, executableAtTime, {
      depositAmount: amountOfCollateralToDeposit,
      minAmountOut: 0,
      announcedBy: poolLogicProxy.address,
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

  const cancelOrder = async () =>
    await poolLogicProxy
      .connect(manager)
      .execTransaction(
        testParams.delayedOrder,
        delayedOrderInterface.encodeFunctionData("cancelExistingOrder", [poolLogicProxy.address]),
      );

  describe("UNIT & FMP integration", () => {
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

      await cancelOrder();
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

      await expect(
        poolManagerLogicProxy.connect(manager).changeAssets([], [collateralAsset.address]),
      ).to.be.revertedWith("order in progress");
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

    it("should be able to deposit and withdraw if stable deposit order announced by someone else", async () => {
      await getAccountToken(
        units(10),
        deployments.owner.address,
        collateralAsset.address,
        testParams.collateralAsset.balanceOfSlot,
      );
      await collateralAsset.approve(delayedOrder.address, ethers.constants.MaxUint256);
      await delayedOrder.announceStableDepositFor(units(1), 0, KEEPER_FEE, poolLogicProxy.address);

      const existingOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
      expect(existingOrder.orderType).to.equal(1);

      await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(deployments.owner.address));
      await collateralAsset.approve(poolLogicProxy.address, ethers.constants.MaxUint256);
      await poolLogicProxy.deposit(collateralAsset.address, units(1));
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

  describe("Perp Market integration", () => {
    let withdrawalAsset: IERC20Extended;
    let emptyPoolLogicProxy: PoolLogic;
    let emptyPoolManagerLogicProxy: PoolManagerLogic;

    before(async () => {
      withdrawalAsset = <IERC20Extended>(
        await ethers.getContractAt("IERC20Extended", testParams.withdrawalAsset.address)
      );

      /* Create separate test vault for perp integration and empty vault */
      const poolProxies = await createFund(
        deployments.poolFactory,
        deployments.owner,
        manager,
        [
          {
            asset: testParams.withdrawalAsset.address,
            isDeposit: true,
          },
          {
            asset: testParams.leverageModule,
            isDeposit: false,
          },
        ],
        {
          performance: ethers.constants.Zero,
          management: ethers.constants.Zero,
        },
      );
      poolLogicProxy = poolProxies.poolLogicProxy;
      poolManagerLogicProxy = poolProxies.poolManagerLogicProxy;

      const emptyPoolProxeis = await createFund(
        deployments.poolFactory,
        deployments.owner,
        manager,
        [
          {
            asset: testParams.withdrawalAsset.address,
            isDeposit: true,
          },
          {
            asset: testParams.leverageModule,
            isDeposit: false,
          },
        ],
        {
          performance: ethers.constants.Zero,
          management: ethers.constants.Zero,
        },
      );
      emptyPoolLogicProxy = emptyPoolProxeis.poolLogicProxy;
      emptyPoolManagerLogicProxy = emptyPoolProxeis.poolManagerLogicProxy;
      /* End of vault creation */

      /* Re-deploy FlatMoneyDelayedOrderContractGuard with this vault as whitelisted for perps */
      const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
      const dhedgeNftTrackerStorage = <DhedgeNftTrackerStorage>(
        await upgrades.deployProxy(DhedgeNftTrackerStorage, [deployments.poolFactory.address])
      );
      await dhedgeNftTrackerStorage.deployed();

      const FlatMoneyDelayedOrderContractGuard = await ethers.getContractFactory("FlatMoneyDelayedOrderContractGuard");
      const flatMoneyDelayedOrderContractGuard = await FlatMoneyDelayedOrderContractGuard.deploy(
        dhedgeNftTrackerStorage.address,
        [
          {
            poolLogic: poolLogicProxy.address,
            withdrawalAsset: withdrawalAsset.address,
          },
          {
            poolLogic: emptyPoolLogicProxy.address,
            withdrawalAsset: withdrawalAsset.address,
          },
        ],
      );
      await flatMoneyDelayedOrderContractGuard.deployed();

      await deployments.governance.setContractGuard(
        testParams.delayedOrder,
        flatMoneyDelayedOrderContractGuard.address,
      );

      delayedOrderGuard = flatMoneyDelayedOrderContractGuard;
      /* End of deployment transactions */

      /* Deposit funds into the vault */
      const decimals = await withdrawalAsset.decimals();
      const withdrawalAssetOwnerBalance = units(100_000, decimals);

      await getAccountToken(
        withdrawalAssetOwnerBalance,
        deployments.owner.address,
        withdrawalAsset.address,
        testParams.withdrawalAsset.balanceOfSlot,
      );

      const withdrawalAssetBalanceToDeposit = withdrawalAssetOwnerBalance.div(4);
      await withdrawalAsset.approve(poolLogicProxy.address, withdrawalAssetBalanceToDeposit);
      await poolLogicProxy.deposit(withdrawalAsset.address, withdrawalAssetBalanceToDeposit);
      /* End of deposit transactions */

      /* Deposit collateral into the vault, if it's not equal to withdrawal asset  */
      if (collateralAsset.address !== withdrawalAsset.address) {
        await emptyPoolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: collateralAsset.address,
              isDeposit: true,
            },
          ],
          [],
        );

        await poolManagerLogicProxy.connect(manager).changeAssets(
          [
            {
              asset: collateralAsset.address,
              isDeposit: true,
            },
          ],
          [],
        );

        const collateralAssetOwnerBalance = units(10);

        await getAccountToken(
          collateralAssetOwnerBalance,
          deployments.owner.address,
          collateralAsset.address,
          testParams.collateralAsset.balanceOfSlot,
        );

        const collateralAssetBalanceToDeposit = collateralAssetOwnerBalance.div(2);
        await collateralAsset.approve(poolLogicProxy.address, collateralAssetBalanceToDeposit);
        await poolLogicProxy.deposit(collateralAsset.address, collateralAssetBalanceToDeposit);
      }

      /* Unlimited approve collateral asset for delayed order */
      await poolLogicProxy
        .connect(manager)
        .execTransaction(
          collateralAsset.address,
          iERC20.encodeFunctionData("approve", [testParams.delayedOrder, ethers.constants.MaxUint256]),
        );
    });

    const mintLeverageNFTIntoAddress = async (
      receiver = poolLogicProxy.address,
      margin = units(1),
      additionalSize = units(2),
    ) => {
      const delayedOrderAddress = await utils.impersonateAccount(testParams.delayedOrder);
      const executableAtTime = (await currentBlockTimestamp()) - 60 * 60 * 12; // Accept 12 hours maxAge for testing purposes
      const maxFillPrice = ethers.constants.MaxUint256;
      const tradeFee = units(1, 16);
      await leverageModule.connect(delayedOrderAddress).executeOpen(receiver, deployments.dao.address, {
        executableAtTime,
        keeperFee: KEEPER_FEE,
        orderType: 3,
        orderData: ethers.utils.defaultAbiCoder.encode(
          ["tuple(uint256, uint256, uint256, uint256, address)"],
          [[margin, additionalSize, maxFillPrice, tradeFee, receiver]],
        ),
      });

      const [tokenId] = await delayedOrderGuard.getOwnedTokenIds(receiver);

      return {
        margin,
        tradeFee,
        tokenId,
      };
    };

    const burnLeverageNFT = async (tokenId: BigNumber) => {
      const delayedOrderAddress = await utils.impersonateAccount(testParams.delayedOrder);
      const executableAtTime = (await currentBlockTimestamp()) - 60 * 60 * 12; // Accept 12 hours maxAge for testing purposes
      const minFillPrice = 0;
      const tradeFee = units(1, 16);
      await leverageModule.connect(delayedOrderAddress).executeClose(poolLogicProxy.address, deployments.dao.address, {
        executableAtTime,
        keeperFee: KEEPER_FEE,
        orderType: 4,
        orderData: ethers.utils.defaultAbiCoder.encode(
          ["tuple(uint256, uint256, uint256)"],
          [[tokenId, minFillPrice, tradeFee]],
        ),
      });
    };

    const announceLeverageOpen = async () =>
      await poolLogicProxy
        .connect(manager)
        .execTransaction(
          testParams.delayedOrder,
          delayedOrderInterface.encodeFunctionData("announceLeverageOpen", [
            units(1),
            units(2),
            units(10_000),
            KEEPER_FEE,
          ]),
        );

    const announceLeverageAdjust = async (
      tokenId: BigNumber,
      poolLogic = poolLogicProxy,
      marginAdjust = units(1),
      sizeAdjust = units(2),
      fillPrice = units(10_000),
    ) =>
      await poolLogic
        .connect(manager)
        .execTransaction(
          testParams.delayedOrder,
          delayedOrderInterface.encodeFunctionData("announceLeverageAdjust", [
            tokenId,
            marginAdjust,
            sizeAdjust,
            fillPrice,
            KEEPER_FEE,
          ]),
        );

    const announceLeverageClose = async (tokenId: BigNumber, poolLogic = poolLogicProxy) =>
      await poolLogic
        .connect(manager)
        .execTransaction(
          testParams.delayedOrder,
          delayedOrderInterface.encodeFunctionData("announceLeverageClose", [tokenId, 0, KEEPER_FEE]),
        );

    it("should correctly account for leverage NFT positions in the vault", async () => {
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const { margin, tradeFee } = await mintLeverageNFTIntoAddress();
      const result = await oracleModule["getPrice()"]();
      const positionValue = margin.sub(tradeFee).mul(result.price).div(units(1));

      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

      expect(totalFundValueAfter).to.be.closeTo(
        totalFundValueBefore.add(positionValue),
        totalFundValueAfter.div(1_000), // 0.1% deviation
      );
    });

    it("should correctly account for multiple leverage NFT positions in the vault", async () => {
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const { margin: margin1, tradeFee: tradeFee1 } = await mintLeverageNFTIntoAddress();
      const { margin: margin2, tradeFee: tradeFee2 } = await mintLeverageNFTIntoAddress(
        poolLogicProxy.address,
        units(1, 17),
        units(1),
      );
      const { margin: margin3, tradeFee: tradeFee3 } = await mintLeverageNFTIntoAddress(
        poolLogicProxy.address,
        units(4),
        units(10),
      );

      const result = await oracleModule["getPrice()"]();
      const positionValue = margin1
        .add(margin2)
        .add(margin3)
        .sub(tradeFee1)
        .sub(tradeFee2)
        .sub(tradeFee3)
        .mul(result.price)
        .div(units(1));

      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();

      expect(totalFundValueAfter).to.be.closeTo(
        totalFundValueBefore.add(positionValue),
        totalFundValueAfter.div(500), // 0.5% deviation
      );
    });

    it("should leave depositor with correct value after withdrawal", async () => {
      await mintLeverageNFTIntoAddress();

      const { assets } = await poolManagerLogicProxy.getFundComposition();

      const getDepositorAssetsValue = async () => {
        let assetsValue = ethers.BigNumber.from(0);
        for (const { asset } of assets) {
          if (asset.toLowerCase() === leverageModule.address.toLowerCase()) continue;
          const assetContract = <IERC20>await ethers.getContractAt(IERC20Path, asset);
          const assetBalance = await assetContract.balanceOf(deployments.owner.address);
          const assetValue = await poolManagerLogicProxy["assetValue(address,uint256)"](asset, assetBalance);
          assetsValue = assetsValue.add(assetValue);
        }
        return assetsValue;
      };

      const withdrawalAssetsValueBefore = await getDepositorAssetsValue();

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

      const poolTokensBalance = await poolLogicProxy.balanceOf(deployments.owner.address);
      const poolTokensBalanceToWithdraw = poolTokensBalance.mul(20).div(100); // 20%
      const poolTokenPrice = await poolLogicProxy.tokenPrice();
      const expectedValueToReceive = poolTokensBalanceToWithdraw.mul(poolTokenPrice).div(units(1));

      await poolLogicProxy.withdraw(poolTokensBalanceToWithdraw);

      const withdrawalAssetsValueAfter = await getDepositorAssetsValue();

      expect(withdrawalAssetsValueAfter).to.be.closeTo(
        withdrawalAssetsValueBefore.add(expectedValueToReceive),
        withdrawalAssetsValueAfter.div(100_000), // 0.001% deviation
      );

      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
      expect(totalFundValueAfter).to.be.closeTo(
        totalFundValueBefore.mul(80).div(100), // 80%
        totalFundValueAfter.div(100_000), // 0.001% deviation
      );

      const poolTokenPriceAfter = await poolLogicProxy.tokenPrice();
      expect(poolTokenPriceAfter).to.be.closeTo(
        poolTokenPrice,
        poolTokenPrice.div(1_000_000), // 0.0001% deviation
      );
    });

    it("should revert when announce leverage open on non-whitelisted vault", async () => {
      const { poolLogicProxy } = await createFund(
        deployments.poolFactory,
        deployments.owner,
        manager,
        [
          {
            asset: testParams.withdrawalAsset.address,
            isDeposit: true,
          },
        ],
        {
          performance: ethers.constants.Zero,
          management: ethers.constants.Zero,
        },
      );
      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(
            testParams.delayedOrder,
            delayedOrderInterface.encodeFunctionData("announceLeverageOpen", [0, 0, 0, KEEPER_FEE]),
          ),
      ).to.be.revertedWith("not perps whitelisted");
    });

    it("should revert when announce leverage adjust on non-whitelisted vault", async () => {
      const { poolLogicProxy } = await createFund(
        deployments.poolFactory,
        deployments.owner,
        manager,
        [
          {
            asset: testParams.withdrawalAsset.address,
            isDeposit: true,
          },
        ],
        {
          performance: ethers.constants.Zero,
          management: ethers.constants.Zero,
        },
      );
      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(
            testParams.delayedOrder,
            delayedOrderInterface.encodeFunctionData("announceLeverageAdjust", [0, 0, 0, 0, KEEPER_FEE]),
          ),
      ).to.be.revertedWith("not perps whitelisted");
    });

    it("should be able to announce leverage open", async () => {
      await announceLeverageOpen();

      const existingOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
      expect(existingOrder.orderType).to.equal(3);
    });

    it("should be able to announce leverage adjust", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress();

      await announceLeverageAdjust(tokenId);

      const existingOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
      expect(existingOrder.orderType).to.equal(5);
    });

    it("should be able to announce leverage close", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress();

      await announceLeverageClose(tokenId);

      const existingOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
      expect(existingOrder.orderType).to.equal(4);
    });

    it("should revert when trying to send leverage NFT via safeTransfer", async () => {
      await mintLeverageNFTIntoAddress(deployments.owner.address);

      const leverageNFT = <IERC721Enumerable>(
        await ethers.getContractAt(IERC721Enumerable__factory.abi, testParams.leverageModule)
      );

      const tokenId = await leverageNFT.tokenOfOwnerByIndex(deployments.owner.address, 0);

      await expect(
        leverageNFT["safeTransferFrom(address,address,uint256)"](
          deployments.owner.address,
          poolLogicProxy.address,
          tokenId,
        ),
      ).to.be.revertedWith("only guarded address");
    });

    it("should not account for leverage NFT received using transfer", async () => {
      const poolTokenIdsBefore = await delayedOrderGuard.getOwnedTokenIds(poolLogicProxy.address);

      await mintLeverageNFTIntoAddress(deployments.owner.address);

      const leverageNFT = <IERC721Enumerable>(
        await ethers.getContractAt(IERC721Enumerable__factory.abi, testParams.leverageModule)
      );
      const tokenId = await leverageNFT.tokenOfOwnerByIndex(deployments.owner.address, 0);
      await leverageNFT.transferFrom(deployments.owner.address, poolLogicProxy.address, tokenId);

      expect(await leverageNFT.ownerOf(tokenId)).to.equal(poolLogicProxy.address);
      expect(await leverageNFT.balanceOf(poolLogicProxy.address)).to.equal(1);

      const poolTokenIdsAfter = await delayedOrderGuard.getOwnedTokenIds(poolLogicProxy.address);

      expect(poolTokenIdsBefore).to.deep.equal(poolTokenIdsAfter);
    });

    it("should revert if trying to open more than limit", async () => {
      await mintLeverageNFTIntoAddress();
      await mintLeverageNFTIntoAddress();
      await mintLeverageNFTIntoAddress();
      await expect(mintLeverageNFTIntoAddress()).to.be.revertedWith("max position reached");
    });

    it("should revert when announce leverage open with more than max allowed leverage", async () => {
      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(
            testParams.delayedOrder,
            delayedOrderInterface.encodeFunctionData("announceLeverageOpen", [
              units(1),
              units(10),
              units(10_000),
              KEEPER_FEE,
            ]),
          ),
      ).to.be.revertedWith("leverage too high");
    });

    it("should revert when announce leverage adjust with more than max allowed leverage", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress();

      await expect(announceLeverageAdjust(tokenId, poolLogicProxy, units(0), units(4))).to.be.revertedWith(
        "leverage too high",
      );

      // withdraw 80% of margin
      await expect(announceLeverageAdjust(tokenId, poolLogicProxy, units(-8, 17), units(0))).to.be.revertedWith(
        "leverage too high",
      );
    });

    it("should be able to announce leverage adjust to decrease leverage", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress();

      const result = await oracleModule["getPrice()"]();
      await announceLeverageAdjust(
        tokenId,
        poolLogicProxy,
        BigNumber.from(0),
        units(-1, 17),
        result.price.mul(4).div(5), // fillPrice
      );
      const existingOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
      expect(existingOrder.orderType).to.equal(5);
    });

    it("should revert if trying to announce leverage open when positions asset is disabled", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets([], [leverageModule.address]);
      await expect(announceLeverageOpen()).to.be.revertedWith("unsupported destination asset");
    });

    it("should revert if trying to announce leverage adjust when collateral asset is disabled", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress(emptyPoolLogicProxy.address);

      await emptyPoolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: testParams.assets.usdc,
            isDeposit: true,
          },
        ],
        [collateralAsset.address],
      );
      await expect(announceLeverageAdjust(tokenId, emptyPoolLogicProxy)).to.be.revertedWith(
        "unsupported destination asset",
      );
    });

    it("should revert if trying to announce leverage adjust on a not owned position", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress();

      await expect(announceLeverageAdjust(tokenId.add(1))).to.be.revertedWith("position is not in track");
    });

    it("should revert if trying to announce leverage close when collateral asset is disabled", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress(emptyPoolLogicProxy.address);

      await emptyPoolManagerLogicProxy.connect(manager).changeAssets(
        [
          {
            asset: testParams.assets.usdc,
            isDeposit: true,
          },
        ],
        [collateralAsset.address],
      );
      await expect(announceLeverageClose(tokenId, emptyPoolLogicProxy)).to.be.revertedWith(
        "unsupported destination asset",
      );
    });

    it("should revert if trying to announce leverage close on a not owned position", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress();

      await expect(announceLeverageClose(tokenId.add(1))).to.be.revertedWith("position is not in track");
    });

    it("should revert if removing position asset after leverage open order announced", async () => {
      await announceLeverageOpen();

      await expect(
        poolManagerLogicProxy.connect(manager).changeAssets([], [leverageModule.address]),
      ).to.be.revertedWith("order in progress");
    });

    it("should revert during deposits/withdrawals if leverage open order announced", async () => {
      await announceLeverageOpen();

      await expect(poolLogicProxy.deposit(collateralAsset.address, units(100))).to.be.revertedWith("order in progress");
      await expect(poolLogicProxy.withdraw(units(100))).to.be.revertedWith("order in progress");
    });

    it("should revert during deposits/withdrawals if leverage adjust order announced", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress();
      await announceLeverageAdjust(tokenId);

      await expect(poolLogicProxy.deposit(collateralAsset.address, units(100))).to.be.revertedWith("order in progress");
      await expect(poolLogicProxy.withdraw(units(100))).to.be.revertedWith("order in progress");
    });

    it("should revert during deposits/withdrawals if leverage close order announced", async () => {
      const { tokenId } = await mintLeverageNFTIntoAddress();
      await announceLeverageClose(tokenId);

      await expect(poolLogicProxy.deposit(collateralAsset.address, units(100))).to.be.revertedWith("order in progress");
      await expect(poolLogicProxy.withdraw(units(100))).to.be.revertedWith("order in progress");
    });

    it("should be able to deposit and withdraw if leverage open order announced by someone else", async () => {
      await collateralAsset.approve(delayedOrder.address, ethers.constants.MaxUint256);
      await delayedOrder.announceLeverageOpenFor(units(1), units(2), units(10_000), KEEPER_FEE, poolLogicProxy.address);

      const existingOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
      expect(existingOrder.orderType).to.equal(3);

      await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(deployments.owner.address));
      await collateralAsset.approve(poolLogicProxy.address, ethers.constants.MaxUint256);
      await poolLogicProxy.deposit(collateralAsset.address, units(1));
    });

    it("should revert during withdraw if withdrawal asset not enabled", async function () {
      if (collateralAsset.address.toLowerCase() === withdrawalAsset.address.toLowerCase()) {
        console.log("Skipping test because withdrawal asset is same as collateral asset");
        this.skip();
      }

      await collateralAsset.approve(emptyPoolLogicProxy.address, ethers.constants.MaxUint256);
      await emptyPoolLogicProxy.deposit(collateralAsset.address, units(1));

      await mintLeverageNFTIntoAddress(emptyPoolLogicProxy.address);

      await emptyPoolManagerLogicProxy.connect(manager).changeAssets([], [withdrawalAsset.address]);

      const poolShares = await emptyPoolLogicProxy.balanceOf(deployments.owner.address);
      await expect(emptyPoolLogicProxy.withdraw(poolShares.div(2))).to.be.revertedWith("withdrawal asset not enabled");
    });

    it("should revert during withdraw if withdrawal asset has no balance/value", async function () {
      if (collateralAsset.address.toLowerCase() === withdrawalAsset.address.toLowerCase()) {
        console.log("Skipping test because withdrawal asset is same as collateral asset");
        this.skip();
      }

      await collateralAsset.approve(emptyPoolLogicProxy.address, ethers.constants.MaxUint256);
      await emptyPoolLogicProxy.deposit(collateralAsset.address, units(1));

      await mintLeverageNFTIntoAddress(emptyPoolLogicProxy.address);

      const poolShares = await emptyPoolLogicProxy.balanceOf(deployments.owner.address);
      await expect(emptyPoolLogicProxy.withdraw(poolShares.div(2))).to.be.revertedWith(
        "not enough available balance_0",
      );
    });

    it("should revert during withdraw from single remaining depositor", async () => {
      await collateralAsset.approve(emptyPoolLogicProxy.address, ethers.constants.MaxUint256);
      await emptyPoolLogicProxy.deposit(collateralAsset.address, units(1));

      await withdrawalAsset.approve(emptyPoolLogicProxy.address, ethers.constants.MaxUint256);
      const decimals = await withdrawalAsset.decimals();
      await emptyPoolLogicProxy.deposit(withdrawalAsset.address, units(1, decimals));

      await mintLeverageNFTIntoAddress(emptyPoolLogicProxy.address);

      const poolShares = await emptyPoolLogicProxy.balanceOf(deployments.owner.address);
      await expect(emptyPoolLogicProxy.withdraw(poolShares)).to.be.revertedWith("invalid withdraw portion");
    });

    it("should revert during withdraw if withdrawal asset balance is not enough to cover leverage position portion", async function () {
      if (collateralAsset.address.toLowerCase() === withdrawalAsset.address.toLowerCase()) {
        console.log("Skipping test because withdrawal asset is same as collateral asset");
        this.skip();
      }

      await collateralAsset.approve(emptyPoolLogicProxy.address, ethers.constants.MaxUint256);
      await emptyPoolLogicProxy.deposit(collateralAsset.address, units(1));

      await withdrawalAsset.approve(emptyPoolLogicProxy.address, ethers.constants.MaxUint256);
      const decimals = await withdrawalAsset.decimals();
      await emptyPoolLogicProxy.deposit(withdrawalAsset.address, units(1, decimals));

      await mintLeverageNFTIntoAddress(emptyPoolLogicProxy.address);

      const poolShares = await emptyPoolLogicProxy.balanceOf(deployments.owner.address);
      await expect(emptyPoolLogicProxy.withdraw(poolShares.div(2))).to.be.revertedWith(
        "not enough available balance_1",
      );
    });

    it("should be able to cancel leverage pending order", async () => {
      await announceLeverageOpen();

      await utils.increaseTime(120); // 2 minutes

      await cancelOrder();

      const existingOpenOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
      expect(existingOpenOrder.orderType).to.equal(0);

      const { tokenId } = await mintLeverageNFTIntoAddress();
      await announceLeverageAdjust(tokenId);

      await utils.increaseTime(120); // 2 minutes

      await cancelOrder();
      const existingAdjustOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
      expect(existingAdjustOrder.orderType).to.equal(0);

      await announceLeverageClose(tokenId);

      await utils.increaseTime(120); // 2 minutes

      await cancelOrder();
      const existingCloseOrder = await delayedOrder.getAnnouncedOrder(poolLogicProxy.address);
      expect(existingCloseOrder.orderType).to.equal(0);
    });

    it("should correctly track for NFT leverage positions after close", async () => {
      await mintLeverageNFTIntoAddress();
      await mintLeverageNFTIntoAddress();

      const tokenIds = await delayedOrderGuard.getOwnedTokenIds(poolLogicProxy.address);
      expect(tokenIds.length).to.equal(2);

      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      const [firstPositionId] = tokenIds;
      await burnLeverageNFT(firstPositionId);

      // After closing (burning), the position is still in track until a new one is minted
      const tokenIdsAfter = await delayedOrderGuard.getOwnedTokenIds(poolLogicProxy.address);
      expect(tokenIdsAfter.length).to.equal(2);

      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
      expect(totalFundValueAfter).to.be.closeTo(
        totalFundValueBefore,
        totalFundValueAfter.div(1_000), // 0.1% deviation
      );
    });

    it("should correctly track for NFT leverage positions when opened again after close", async () => {
      await mintLeverageNFTIntoAddress();
      await mintLeverageNFTIntoAddress();

      const [firstPositionId, secondPositionId] = await delayedOrderGuard.getOwnedTokenIds(poolLogicProxy.address);

      await burnLeverageNFT(firstPositionId);

      await mintLeverageNFTIntoAddress();

      const [secondPositionId2, thirdPositionId] = await delayedOrderGuard.getOwnedTokenIds(poolLogicProxy.address);

      const tokenIdsAfter = await delayedOrderGuard.getOwnedTokenIds(poolLogicProxy.address);
      expect(secondPositionId2).to.equal(secondPositionId);
      expect(tokenIdsAfter[0]).to.equal(secondPositionId);
      expect(tokenIdsAfter[1]).to.equal(thirdPositionId);
      expect(tokenIdsAfter.length).to.equal(2);
    });

    it("should correctly reach max positions after close", async () => {
      await mintLeverageNFTIntoAddress();
      await mintLeverageNFTIntoAddress();

      const [firstPositionId] = await delayedOrderGuard.getOwnedTokenIds(poolLogicProxy.address);

      await burnLeverageNFT(firstPositionId);

      await mintLeverageNFTIntoAddress();

      await mintLeverageNFTIntoAddress();

      const delayedOrderAddress = await utils.impersonateAccount(testParams.delayedOrder);
      const executableAtTime = (await currentBlockTimestamp()) - 60 * 60 * 12; // Accept 12 hours maxAge for testing purposes
      const maxFillPrice = ethers.constants.MaxUint256;
      const tradeFee = units(1, 16);

      await expect(
        leverageModule.connect(delayedOrderAddress).executeOpen(poolLogicProxy.address, deployments.dao.address, {
          executableAtTime,
          keeperFee: KEEPER_FEE,
          orderType: 3,
          orderData: ethers.utils.defaultAbiCoder.encode(
            ["tuple(uint256, uint256, uint256, uint256, address)"],
            [[units(1), units(1), maxFillPrice, tradeFee, poolLogicProxy.address]],
          ),
        }),
      ).to.be.revertedWith("max position reached");
    });
  });
});
