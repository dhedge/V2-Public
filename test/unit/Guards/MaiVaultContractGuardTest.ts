import { expect } from "chai";
import { ethers } from "hardhat";

import { FakeContract, MockContract, smock } from "@defi-wonderland/smock";

import {
  IStableQiVault,
  IStableQiVault__factory,
  MaiVaultContractGuard,
  PoolManagerLogic,
  PoolManagerLogic__factory,
} from "../../../types";

const iMaiVault = new ethers.utils.Interface(IStableQiVault__factory.abi);
const mockCollateralAddress = ethers.Wallet.createRandom().address;
const mockMaiAddress = ethers.Wallet.createRandom().address;

describe("MaiVault TxGuard Test", function () {
  let mockPoolManager: MockContract<PoolManagerLogic>;
  let maiVaultContractGuard: MaiVaultContractGuard;
  let fakeVault: FakeContract<IStableQiVault>;
  beforeEach(async function () {
    const MaiVaultContractGuard = await ethers.getContractFactory("MaiVaultContractGuard");
    const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
    const nftStorage = await DhedgeNftTrackerStorage.deploy();

    maiVaultContractGuard = await MaiVaultContractGuard.deploy(nftStorage.address);
    await maiVaultContractGuard.deployed();

    // mocking this path IStableQiVault(to).collateral()
    fakeVault = await smock.fake<IStableQiVault>(IStableQiVault__factory.abi);
    fakeVault.collateral.returns(mockCollateralAddress);
    fakeVault.mai.returns(mockMaiAddress);

    const PoolManagerLogicFactory = await smock.mock<PoolManagerLogic__factory>("PoolManagerLogic");
    mockPoolManager = await PoolManagerLogicFactory.deploy();
    await mockPoolManager.setVariable("poolLogic", ethers.Wallet.createRandom().address);
    mockPoolManager.isSupportedAsset.whenCalledWith(fakeVault.address).returns(true);
    mockPoolManager.isSupportedAsset.whenCalledWith(mockCollateralAddress).returns(true);
    mockPoolManager.isSupportedAsset.whenCalledWith(mockMaiAddress).returns(true);
  });

  it("Reverts if MaiVault is not supported asset", async () => {
    mockPoolManager.isSupportedAsset.whenCalledWith(fakeVault.address).returns(false);
    await expect(
      maiVaultContractGuard.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        iMaiVault.encodeFunctionData("createVault"),
      ),
    ).to.revertedWith("unsupported asset");
  });

  it("Reverts if collateral is not supported asset", async () => {
    mockPoolManager.isSupportedAsset.whenCalledWith(mockCollateralAddress).returns(false);
    await expect(
      maiVaultContractGuard.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        iMaiVault.encodeFunctionData("createVault"),
      ),
    ).to.revertedWith("collateral not enabled");
  });

  it("Reverts if mai is not supported asset", async () => {
    mockPoolManager.isSupportedAsset.whenCalledWith(mockMaiAddress).returns(false);
    await expect(
      maiVaultContractGuard.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        iMaiVault.encodeFunctionData("createVault"),
      ),
    ).to.revertedWith("mai not enabled");
  });

  describe("Allowed methods", () => {
    const vaultID = 1337;
    const amount = 1338;
    const front = 1339;
    it("createVault", async () => {
      const createVault = iMaiVault.encodeFunctionData("createVault");
      const [txType, isPublic] = await maiVaultContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        createVault,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(32);
    });

    it("destroyVault", async () => {
      const destroyVault = iMaiVault.encodeFunctionData("destroyVault", [vaultID]);
      const [txType, isPublic] = await maiVaultContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        destroyVault,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(32);
    });

    it("depositCollateral", async () => {
      const depositCollateral = iMaiVault.encodeFunctionData("depositCollateral", [vaultID, amount]);
      const [txType, isPublic] = await maiVaultContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        depositCollateral,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(32);
    });

    it("borrowToken", async () => {
      const borrowToken = iMaiVault.encodeFunctionData("borrowToken", [vaultID, amount, front]);
      const [txType, isPublic] = await maiVaultContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        borrowToken,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(32);
    });

    it("payBackToken", async () => {
      const payBackToken = iMaiVault.encodeFunctionData("payBackToken", [vaultID, amount, front]);
      const [txType, isPublic] = await maiVaultContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        payBackToken,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(32);
    });

    it("paybackTokenAll", async () => {
      const deadline = 1340;
      const paybackTokenAll = iMaiVault.encodeFunctionData("paybackTokenAll", [vaultID, deadline, front]);
      const [txType, isPublic] = await maiVaultContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        paybackTokenAll,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(32);
    });

    it("withdrawCollateral", async () => {
      const withdrawCollateral = iMaiVault.encodeFunctionData("withdrawCollateral", [vaultID, amount]);
      const [txType, isPublic] = await maiVaultContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        withdrawCollateral,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(32);
    });
  });

  describe("Not Allowed methods", () => {
    it("no accidental passthrough approval", async () => {
      const vaultCount = iMaiVault.encodeFunctionData("vaultCount");
      const [txType, isPublic] = await maiVaultContractGuard.callStatic.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        vaultCount,
      );
      expect(isPublic).to.be.false;
      expect(txType).to.equal(0);
    });
  });
});
