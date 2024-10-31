import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import { BaseContract } from "ethers";
import type { MockContract } from "ethereum-waffle";

import {
  SynthetixFuturesMarketContractGuard,
  IFuturesMarket__factory,
  PoolManagerLogic__factory,
  ISynth__factory,
  IAddressResolver__factory,
} from "../../../../types";

const iFuturesMarket = new ethers.utils.Interface(IFuturesMarket__factory.abi);
const mockSUSDProxyAddress = ethers.Wallet.createRandom().address;

describe("Futures Market Contract Guard Test", function () {
  let mockPoolManager: MockContract<BaseContract>;
  let futuresMarketContractGuard: SynthetixFuturesMarketContractGuard;
  let futuresMarket: MockContract<BaseContract>;
  beforeEach(async function () {
    const [owner] = await ethers.getSigners();

    const SynthetixFuturesMarketContractGuard = await ethers.getContractFactory("SynthetixFuturesMarketContractGuard");
    futuresMarketContractGuard = await SynthetixFuturesMarketContractGuard.deploy();
    await futuresMarketContractGuard.deployed();

    // mocking this path ISynth(IFuturesMarket(to).resolver().getSynth("sUSD")).proxy();
    const fakeSUSD = await waffle.deployMockContract(owner, ISynth__factory.abi);
    await fakeSUSD.mock.proxy.returns(mockSUSDProxyAddress);

    const fakeResolver = await waffle.deployMockContract(owner, IAddressResolver__factory.abi);
    await fakeResolver.mock.getSynth.returns(fakeSUSD.address);
    futuresMarket = await waffle.deployMockContract(owner, IFuturesMarket__factory.abi);
    await futuresMarket.mock.resolver.returns(fakeResolver.address);

    mockPoolManager = await waffle.deployMockContract(owner, PoolManagerLogic__factory.abi);
    await mockPoolManager.mock.poolLogic.returns(ethers.Wallet.createRandom().address);
    await mockPoolManager.mock.isSupportedAsset.withArgs(futuresMarket.address).returns(true);
    await mockPoolManager.mock.isSupportedAsset.withArgs(mockSUSDProxyAddress).returns(true);
  });

  it("Reverts if FuturesMarket is not supported asset", async () => {
    await mockPoolManager.mock.isSupportedAsset.withArgs(futuresMarket.address).returns(false);
    await expect(
      futuresMarketContractGuard.txGuard(
        mockPoolManager.address,
        futuresMarket.address,
        iFuturesMarket.encodeFunctionData("transferMargin", [0]),
      ),
    ).to.revertedWith("unsupported asset");
  });

  it("Reverts if SUSD is not supported asset", async () => {
    await mockPoolManager.mock.isSupportedAsset.withArgs(mockSUSDProxyAddress).returns(false);
    await expect(
      futuresMarketContractGuard.txGuard(
        mockPoolManager.address,
        futuresMarket.address,
        iFuturesMarket.encodeFunctionData("transferMargin", [0]),
      ),
    ).to.revertedWith("susd must be enabled asset");
  });

  describe("Allowed methods", () => {
    it("transferMargin", async () => {
      const transferMargin = iFuturesMarket.encodeFunctionData("transferMargin", [0]);
      const [txType, isPublic] = await futuresMarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        futuresMarket.address,
        transferMargin,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(29);
    });

    it("modifyPositionWithTracking", async () => {
      const modifyPositionWithTracking = iFuturesMarket.encodeFunctionData("modifyPositionWithTracking", [
        0,
        ethers.utils.formatBytes32String("0"),
      ]);
      const [txType, isPublic] = await futuresMarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        futuresMarket.address,
        modifyPositionWithTracking,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(29);
    });

    it("closePositionWithTracking", async () => {
      const closePositionWithTracking = iFuturesMarket.encodeFunctionData("closePositionWithTracking", [
        ethers.utils.formatBytes32String("0"),
      ]);
      const [txType, isPublic] = await futuresMarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        futuresMarket.address,
        closePositionWithTracking,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(29);
    });

    it("withdrawAllMargin", async () => {
      const withdrawAllMargin = iFuturesMarket.encodeFunctionData("withdrawAllMargin");
      const [txType, isPublic] = await futuresMarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        futuresMarket.address,
        withdrawAllMargin,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(29);
    });
  });

  describe("Not Allowed methods", () => {
    it("positions", async () => {
      const positions = iFuturesMarket.encodeFunctionData("positions", [ethers.constants.AddressZero]);
      const [txType, isPublic] = await futuresMarketContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        futuresMarket.address,
        positions,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });
  });
});
