import { assert, expect } from "chai";
import { ethers, waffle } from "hardhat";
import type { MockContract } from "ethereum-waffle";

import {
  IPerpsV2Market__factory,
  SynthetixPerpsV2MarketContractGuard,
  PoolManagerLogic__factory,
  PoolLogic__factory,
} from "../../../../types";
import { BigNumber, BaseContract } from "ethers";

const PRICE_IMPACT_DELTA = BigNumber.from("500000000000000000");
const TRACKING_CODE = ethers.utils.formatBytes32String("0");
const TIME_DELTA = ethers.utils.formatBytes32String("0");
const iPerpsV2Market = new ethers.utils.Interface(IPerpsV2Market__factory.abi);
const mockSUSDProxyAddress = ethers.Wallet.createRandom().address;

describe("PerpsV2 Market Contract Guard Test", function () {
  let mockPoolManager: MockContract<BaseContract>;
  let mockPoolLogic: MockContract<BaseContract>;
  let perpsV2MarketContractGuard: SynthetixPerpsV2MarketContractGuard;
  let perpsV2Market: MockContract<BaseContract>;
  beforeEach(async function () {
    const [owner] = await ethers.getSigners();

    mockPoolLogic = await waffle.deployMockContract(owner, PoolLogic__factory.abi);
    const SynthetixPerpsV2MarketContractGuard = await ethers.getContractFactory("SynthetixPerpsV2MarketContractGuard");
    perpsV2MarketContractGuard = await SynthetixPerpsV2MarketContractGuard.deploy(mockSUSDProxyAddress, [
      mockPoolLogic.address,
    ]);
    await perpsV2MarketContractGuard.deployed();

    mockPoolManager = await waffle.deployMockContract(owner, PoolManagerLogic__factory.abi);
    perpsV2Market = await waffle.deployMockContract(owner, IPerpsV2Market__factory.abi);

    await mockPoolManager.mock.poolLogic.returns(ethers.Wallet.createRandom().address);
    await mockPoolManager.mock.isSupportedAsset.withArgs(perpsV2Market.address).returns(true);
    await mockPoolManager.mock.isSupportedAsset.withArgs(mockSUSDProxyAddress).returns(true);
    await mockPoolManager.mock.poolLogic.withArgs().returns(mockPoolLogic.address);
    await perpsV2Market.mock.positions.withArgs(mockPoolLogic.address).returns({
      id: "1", // id
      lastFundingIndex: "0", // lastFundingIndex
      margin: "1000000000000000000", // margin
      lastPrice: "1000000000000000000", // lastPrice
      size: "100", // size
    });
    await perpsV2Market.mock.fillPrice.returns(0, false);
  });

  it("Reverts if PerpsV2Market is not supported asset", async () => {
    await mockPoolManager.mock.isSupportedAsset.withArgs(perpsV2Market.address).returns(false);
    await expect(
      perpsV2MarketContractGuard.txGuard(
        mockPoolManager.address,
        perpsV2Market.address,
        iPerpsV2Market.encodeFunctionData("transferMargin", [0]),
      ),
    ).to.revertedWith("unsupported asset");
  });

  it("Reverts if SUSD is not supported asset", async () => {
    await mockPoolManager.mock.isSupportedAsset.withArgs(mockSUSDProxyAddress).returns(false);
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
        transferMargin.data as string,
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
        submitOffchainDelayedOrder.data as string,
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
        submitOffchainDelayedOrderWithTracking.data as string,
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
        withdrawAllMargin.data as string,
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
        cancelDelayedOrder.data as string,
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
        cancelOffchainDelayedOrder.data as string,
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
        positions.data as string,
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
        modifyPositionWithTracking.data as string,
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
        modifyPositionWithTracking.data as string,
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
        submitDelayedOrder.data as string,
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
        submitDelayedOrderWithTracking.data as string,
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
        closePositionWithTracking.data as string,
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
        closePosition.data as string,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });
  });
});
