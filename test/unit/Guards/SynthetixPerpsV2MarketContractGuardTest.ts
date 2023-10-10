import { assert, expect } from "chai";
import { ethers } from "hardhat";

import { FakeContract, MockContract, smock } from "@defi-wonderland/smock";

import {
  IPerpsV2Market,
  IPerpsV2Market__factory,
  SynthetixPerpsV2MarketContractGuard,
  PoolManagerLogic,
  PoolManagerLogic__factory,
  PoolLogic,
  PoolLogic__factory,
} from "../../../types";
import { BigNumber } from "ethers";

const PRICE_IMPACT_DELTA = BigNumber.from("500000000000000000");
const TRACKING_CODE = ethers.utils.formatBytes32String("0");
const TIME_DELTA = ethers.utils.formatBytes32String("0");
const iPerpsV2Market = new ethers.utils.Interface(IPerpsV2Market__factory.abi);
const mockSUSDProxyAddress = ethers.Wallet.createRandom().address;

describe("PerpsV2 Market Contract Guard Test", function () {
  let mockPoolManager: MockContract<PoolManagerLogic>;
  let mockPoolLogic: MockContract<PoolLogic>;
  let perpsV2MarketContractGuard: SynthetixPerpsV2MarketContractGuard;
  let perpsV2Market: FakeContract<IPerpsV2Market>;
  beforeEach(async function () {
    const PoolLogicFactory = await smock.mock<PoolLogic__factory>("PoolLogic");
    mockPoolLogic = await PoolLogicFactory.deploy();
    const SynthetixPerpsV2MarketContractGuard = await ethers.getContractFactory("SynthetixPerpsV2MarketContractGuard");
    perpsV2MarketContractGuard = await SynthetixPerpsV2MarketContractGuard.deploy(mockSUSDProxyAddress, [
      mockPoolLogic.address,
    ]);
    await perpsV2MarketContractGuard.deployed();

    const PoolManagerLogicFactory = await smock.mock<PoolManagerLogic__factory>("PoolManagerLogic");
    mockPoolManager = await PoolManagerLogicFactory.deploy();
    perpsV2Market = await smock.fake<IPerpsV2Market>(IPerpsV2Market__factory.abi);
    await mockPoolManager.setVariable("poolLogic", ethers.Wallet.createRandom().address);
    mockPoolManager.isSupportedAsset.whenCalledWith(perpsV2Market.address).returns(true);
    mockPoolManager.isSupportedAsset.whenCalledWith(mockSUSDProxyAddress).returns(true);
    mockPoolManager.poolLogic.whenCalledWith().returns(mockPoolLogic.address);
    perpsV2Market.positions.whenCalledWith(mockPoolLogic.address).returns({
      id: "1", // id

      lastFundingIndex: "0", // lastFundingIndex
      margin: "1000000000000000000", // margin
      lastPrice: "1000000000000000000", // lastPrice
      size: "100", // size
    });
  });

  it("Reverts if PerpsV2Market is not supported asset", async () => {
    mockPoolManager.isSupportedAsset.whenCalledWith(perpsV2Market.address).returns(false);
    await expect(
      perpsV2MarketContractGuard.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        iPerpsV2Market.encodeFunctionData("transferMargin", [0]),
      ),
    ).to.revertedWith("unsupported asset");
  });

  it("Reverts if SUSD is not supported asset", async () => {
    mockPoolManager.isSupportedAsset.whenCalledWith(mockSUSDProxyAddress).returns(false);
    await expect(
      perpsV2MarketContractGuard.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        iPerpsV2Market.encodeFunctionData("transferMargin", [0]),
      ),
    ).to.revertedWith("susd must be enabled asset");
  });

  describe("Allowed methods", () => {
    it("transferMargin", async () => {
      const transferMargin = await perpsV2Market.populateTransaction.transferMargin(0);
      assert(transferMargin.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        transferMargin.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(35);
    });

    it("submitOffchainDelayedOrder", async () => {
      const submitOffchainDelayedOrder = await perpsV2Market.populateTransaction.submitOffchainDelayedOrder(
        0,
        PRICE_IMPACT_DELTA,
      );
      assert(submitOffchainDelayedOrder.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        submitOffchainDelayedOrder.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(35);
    });

    it("submitOffchainDelayedOrderWithTracking", async () => {
      const submitOffchainDelayedOrderWithTracking =
        await perpsV2Market.populateTransaction.submitOffchainDelayedOrderWithTracking(
          0,
          PRICE_IMPACT_DELTA,
          TRACKING_CODE,
        );
      assert(submitOffchainDelayedOrderWithTracking.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        submitOffchainDelayedOrderWithTracking.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(35);
    });

    it("withdrawAllMargin", async () => {
      const withdrawAllMargin = await perpsV2Market.populateTransaction.withdrawAllMargin();
      assert(withdrawAllMargin.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        withdrawAllMargin.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(35);
    });

    it("cancelDelayedOrder", async () => {
      const cancelDelayedOrder = await perpsV2Market.populateTransaction.cancelDelayedOrder(
        ethers.Wallet.createRandom().address,
      );
      assert(cancelDelayedOrder.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        cancelDelayedOrder.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(35);
    });

    it("cancelOffchainDelayedOrder", async () => {
      const cancelOffchainDelayedOrder = await perpsV2Market.populateTransaction.cancelOffchainDelayedOrder(
        ethers.Wallet.createRandom().address,
      );
      assert(cancelOffchainDelayedOrder.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        cancelOffchainDelayedOrder.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(35);
    });
  });

  describe("Not Allowed methods", () => {
    it("positions", async () => {
      const positions = await perpsV2Market.populateTransaction.positions(ethers.constants.AddressZero);
      assert(positions.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        positions.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });

    // The following methods have been disabled because only delayed offchain transactions are supported in Perps v2
    it("modifyPosition", async () => {
      const modifyPositionWithTracking = await perpsV2Market.populateTransaction.modifyPosition(0, PRICE_IMPACT_DELTA);
      assert(modifyPositionWithTracking.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        modifyPositionWithTracking.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });

    it("modifyPositionWithTracking", async () => {
      const modifyPositionWithTracking = await perpsV2Market.populateTransaction.modifyPositionWithTracking(
        0,
        PRICE_IMPACT_DELTA,
        TRACKING_CODE,
      );
      assert(modifyPositionWithTracking.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        modifyPositionWithTracking.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });

    it("submitDelayedOrder", async () => {
      const submitDelayedOrder = await perpsV2Market.populateTransaction.submitDelayedOrder(
        0,
        PRICE_IMPACT_DELTA,
        TIME_DELTA,
      );
      assert(submitDelayedOrder.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        submitDelayedOrder.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });

    it("submitDelayedOrderWithTracking", async () => {
      const submitDelayedOrderWithTracking = await perpsV2Market.populateTransaction.submitDelayedOrderWithTracking(
        0,
        PRICE_IMPACT_DELTA,
        TIME_DELTA,
        TRACKING_CODE,
      );
      assert(submitDelayedOrderWithTracking.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        submitDelayedOrderWithTracking.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });

    it("closePositionWithTracking", async () => {
      const closePositionWithTracking = await perpsV2Market.populateTransaction.closePositionWithTracking(
        PRICE_IMPACT_DELTA,
        TRACKING_CODE,
      );
      assert(closePositionWithTracking.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        closePositionWithTracking.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });

    it("closePosition", async () => {
      const closePosition = await perpsV2Market.populateTransaction.closePosition(PRICE_IMPACT_DELTA);
      assert(closePosition.data);
      const [txType, isPublic] = await perpsV2MarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        closePosition.data,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });
  });
});
