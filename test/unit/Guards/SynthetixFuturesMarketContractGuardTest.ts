import { expect } from "chai";
import { ethers } from "hardhat";

import { FakeContract, MockContract, smock } from "@defi-wonderland/smock";

import {
  ISynth,
  SynthetixFuturesMarketContractGuard,
  IAddressResolver,
  IFuturesMarket,
  IFuturesMarket__factory,
  PoolManagerLogic,
  PoolManagerLogic__factory,
  ISynth__factory,
  IAddressResolver__factory,
} from "../../../types";

const iFuturesMarket = new ethers.utils.Interface(IFuturesMarket__factory.abi);
const mockSUSDProxyAddress = ethers.Wallet.createRandom().address;

describe("Futures Market Contract Guard Test", function () {
  let mockPoolManager: MockContract<PoolManagerLogic>;
  let futuresMarketContractGuard: SynthetixFuturesMarketContractGuard;
  let futuresMarket: FakeContract<IFuturesMarket>;
  beforeEach(async function () {
    const SynthetixFuturesMarketContractGuard = await ethers.getContractFactory("SynthetixFuturesMarketContractGuard");
    futuresMarketContractGuard = await SynthetixFuturesMarketContractGuard.deploy();
    await futuresMarketContractGuard.deployed();

    // mocking this path ISynth(IFuturesMarket(to).resolver().getSynth("sUSD")).proxy();
    const fakeSUSD = await smock.fake<ISynth>(ISynth__factory.abi);
    fakeSUSD.proxy.returns(mockSUSDProxyAddress);

    const fakeResolver = await smock.fake<IAddressResolver>(IAddressResolver__factory.abi);
    fakeResolver.getSynth.returns(fakeSUSD.address);
    futuresMarket = await smock.fake<IFuturesMarket>(IFuturesMarket__factory.abi);
    futuresMarket.resolver.returns(fakeResolver.address);

    const PoolManagerLogicFactory = await smock.mock<PoolManagerLogic__factory>("PoolManagerLogic");
    mockPoolManager = await PoolManagerLogicFactory.deploy();
    await mockPoolManager.setVariable("poolLogic", ethers.Wallet.createRandom().address);
    mockPoolManager.isSupportedAsset.whenCalledWith(futuresMarket.address).returns(true);
    mockPoolManager.isSupportedAsset.whenCalledWith(mockSUSDProxyAddress).returns(true);
  });

  it("Reverts if FuturesMarket is not supported asset", async () => {
    mockPoolManager.isSupportedAsset.whenCalledWith(futuresMarket.address).returns(false);
    await expect(
      futuresMarketContractGuard.txGuard(
        mockPoolManager.address,
        futuresMarket.address,
        iFuturesMarket.encodeFunctionData("transferMargin", [0]),
      ),
    ).to.revertedWith("unsupported asset");
  });

  it("Reverts if SUSD is not supported asset", async () => {
    mockPoolManager.isSupportedAsset.whenCalledWith(mockSUSDProxyAddress).returns(false);
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
