import { expect } from "chai";
import { ethers, waffle } from "hardhat";
import type { MockContract } from "ethereum-waffle";
import { IStableQiVault__factory, MaiVaultContractGuard, PoolManagerLogic__factory } from "../../../../types";
import { BaseContract } from "ethers";

const iMaiVault = new ethers.utils.Interface(IStableQiVault__factory.abi);
const mockCollateralAddress = ethers.Wallet.createRandom().address;
const mockMaiAddress = ethers.Wallet.createRandom().address;

describe("MaiVault TxGuard Test", function () {
  let mockPoolManager: MockContract<BaseContract>;
  let maiVaultContractGuard: MaiVaultContractGuard;
  let fakeVault: MockContract<BaseContract>;
  beforeEach(async function () {
    const [owner] = await ethers.getSigners();

    const MaiVaultContractGuard = await ethers.getContractFactory("MaiVaultContractGuard");
    const DhedgeNftTrackerStorage = await ethers.getContractFactory("DhedgeNftTrackerStorage");
    const nftStorage = await DhedgeNftTrackerStorage.deploy();

    maiVaultContractGuard = await MaiVaultContractGuard.deploy(nftStorage.address);
    await maiVaultContractGuard.deployed();

    // mocking this path IStableQiVault(to).collateral()
    fakeVault = await waffle.deployMockContract(owner, IStableQiVault__factory.abi);
    await fakeVault.mock.collateral.returns(mockCollateralAddress);
    await fakeVault.mock.mai.returns(mockMaiAddress);

    mockPoolManager = await waffle.deployMockContract(owner, PoolManagerLogic__factory.abi);

    await mockPoolManager.mock.poolLogic.returns(ethers.Wallet.createRandom().address);
    await mockPoolManager.mock.isSupportedAsset.withArgs(fakeVault.address).returns(true);
    await mockPoolManager.mock.isSupportedAsset.withArgs(mockCollateralAddress).returns(true);
    await mockPoolManager.mock.isSupportedAsset.withArgs(mockMaiAddress).returns(true);
  });

  it("Reverts if MaiVault is not supported asset", async () => {
    await mockPoolManager.mock.isSupportedAsset.withArgs(fakeVault.address).returns(false);
    await expect(
      maiVaultContractGuard.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        iMaiVault.encodeFunctionData("createVault"),
      ),
    ).to.revertedWith("unsupported asset");
  });

  it("Reverts if collateral is not supported asset", async () => {
    await mockPoolManager.mock.isSupportedAsset.withArgs(mockCollateralAddress).returns(false);
    await expect(
      maiVaultContractGuard.txGuard(
        mockPoolManager.address,
        fakeVault.address,
        iMaiVault.encodeFunctionData("createVault"),
      ),
    ).to.revertedWith("collateral not enabled");
  });

  it("Reverts if mai is not supported asset", async () => {
    await mockPoolManager.mock.isSupportedAsset.withArgs(mockMaiAddress).returns(false);
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
