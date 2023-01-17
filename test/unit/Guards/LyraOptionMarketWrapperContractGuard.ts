import { expect } from "chai";
import { ethers } from "hardhat";
import {
  MockContract,
  PoolManagerLogic__factory,
  LyraOptionMarketWrapperContractGuard,
  ISynthetixAdapter__factory,
  IAddressResolver__factory,
  IOptionMarketViewer__factory,
  IOptionMarketWrapper__factory,
  IOptionToken__factory,
} from "../../../types";

const susdKey = "0x7355534400000000000000000000000000000000000000000000000000000000";
const sethKey = "0x7345544800000000000000000000000000000000000000000000000000000000";

describe("LyraOptionMarketWrapperContractGuard Test", () => {
  let poolLogic: MockContract, poolManagerLogic: MockContract;
  let lyraOptionMarketWrapperContractGuard: LyraOptionMarketWrapperContractGuard;
  let optionMarketWrapper: MockContract,
    optionMarket: MockContract,
    optionToken: MockContract,
    marketViewer: MockContract,
    synthetixAdapter: MockContract,
    synthetixAddressResolver: MockContract;
  let seth: MockContract, susd: MockContract;
  const MAX_POSITION_COUNT = 2;
  const iSyntheixAdapter = new ethers.utils.Interface(ISynthetixAdapter__factory.abi);
  const iAddressResolver = new ethers.utils.Interface(IAddressResolver__factory.abi);
  const iPoolManagerLogic = new ethers.utils.Interface(PoolManagerLogic__factory.abi);
  const iOptionMarketWrapper = new ethers.utils.Interface(IOptionMarketWrapper__factory.abi);
  const iOptionToken = new ethers.utils.Interface(IOptionToken__factory.abi);
  const iOptionMarketViewer = new ethers.utils.Interface(IOptionMarketViewer__factory.abi);

  beforeEach(async () => {
    const MockContract = await ethers.getContractFactory("MockContract");

    poolLogic = await MockContract.deploy();
    poolManagerLogic = await MockContract.deploy();
    seth = await MockContract.deploy();
    susd = await MockContract.deploy();
    optionMarketWrapper = await MockContract.deploy();
    optionMarketWrapper = await MockContract.deploy();
    optionMarket = await MockContract.deploy();
    optionToken = await MockContract.deploy();
    marketViewer = await MockContract.deploy();
    synthetixAdapter = await MockContract.deploy();
    synthetixAddressResolver = await MockContract.deploy();

    const LyraOptionMarketWrapperContractGuard = await ethers.getContractFactory(
      "LyraOptionMarketWrapperContractGuard",
    );
    lyraOptionMarketWrapperContractGuard = <LyraOptionMarketWrapperContractGuard>(
      await LyraOptionMarketWrapperContractGuard.deploy(
        marketViewer.address,
        synthetixAdapter.address,
        synthetixAddressResolver.address,
        MAX_POSITION_COUNT, // set max position count
      )
    );
    await lyraOptionMarketWrapperContractGuard.deployed();

    await poolManagerLogic.givenCalldataReturnAddress(
      iPoolManagerLogic.encodeFunctionData("poolLogic", []),
      poolLogic.address,
    );

    await poolManagerLogic.givenCalldataReturnBool(
      iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [seth.address]),
      false,
    );
    await poolManagerLogic.givenCalldataReturnBool(
      iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [susd.address]),
      false,
    );

    await synthetixAdapter.givenCalldataReturn(
      iSyntheixAdapter.encodeFunctionData("quoteKey", [optionMarket.address]),
      sethKey,
    );
    await synthetixAdapter.givenCalldataReturn(
      iSyntheixAdapter.encodeFunctionData("baseKey", [optionMarket.address]),
      susdKey,
    );

    await synthetixAddressResolver.givenCalldataReturnAddress(
      iAddressResolver.encodeFunctionData("getAddress", [sethKey]),
      seth.address,
    );
    await synthetixAddressResolver.givenCalldataReturnAddress(
      iAddressResolver.encodeFunctionData("getAddress", [susdKey]),
      susd.address,
    );

    await marketViewer.givenCalldataReturn(
      iOptionMarketViewer.encodeFunctionData("getMarketAddresses", []),
      iOptionMarketViewer.encodeFunctionResult("getMarketAddresses", [
        [
          [
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            optionToken.address,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
          ],
        ],
      ]),
    );
    await optionToken.givenCalldataReturnUint(
      iOptionToken.encodeFunctionData("balanceOf", [poolLogic.address]),
      MAX_POSITION_COUNT - 1,
    );
  });

  describe("open position", () => {
    it("Reverts if quote asset is not supported", async () => {
      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [optionMarket.address, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await expect(
        lyraOptionMarketWrapperContractGuard.txGuard(
          poolManagerLogic.address,
          optionMarketWrapper.address,
          openPositionABI,
        ),
      ).to.revertedWith("unsupported quote synth");
    });

    it("Reverts if base asset is not supported", async () => {
      await poolManagerLogic.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [seth.address]),
        true,
      );

      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [optionMarket.address, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await expect(
        lyraOptionMarketWrapperContractGuard.txGuard(
          poolManagerLogic.address,
          optionMarketWrapper.address,
          openPositionABI,
        ),
      ).to.revertedWith("unsupported base synth");
    });

    it("Reverts if reaches maximum positions count", async () => {
      await optionToken.givenCalldataReturnUint(
        iOptionToken.encodeFunctionData("balanceOf", [poolLogic.address]),
        MAX_POSITION_COUNT,
      );

      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [optionMarket.address, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await expect(
        lyraOptionMarketWrapperContractGuard.txGuard(
          poolManagerLogic.address,
          optionMarketWrapper.address,
          openPositionABI,
        ),
      ).to.revertedWith("exceed maximum position count");
    });

    it("Can create a new option position", async () => {
      await poolManagerLogic.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [seth.address]),
        true,
      );
      await poolManagerLogic.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [susd.address]),
        true,
      );

      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [optionMarket.address, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await lyraOptionMarketWrapperContractGuard.txGuard(
        poolManagerLogic.address,
        optionMarketWrapper.address,
        openPositionABI,
      );
    });
  });

  describe("close position", () => {
    it("Reverts if quote asset is not supported", async () => {
      const closePositionABI = iOptionMarketWrapper.encodeFunctionData("closePosition", [
        [optionMarket.address, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await expect(
        lyraOptionMarketWrapperContractGuard.txGuard(
          poolManagerLogic.address,
          optionMarketWrapper.address,
          closePositionABI,
        ),
      ).to.revertedWith("unsupported quote synth");
    });

    it("Reverts if base asset is not supported", async () => {
      await poolManagerLogic.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [seth.address]),
        true,
      );

      const closePositionABI = iOptionMarketWrapper.encodeFunctionData("closePosition", [
        [optionMarket.address, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await expect(
        lyraOptionMarketWrapperContractGuard.txGuard(
          poolManagerLogic.address,
          optionMarketWrapper.address,
          closePositionABI,
        ),
      ).to.revertedWith("unsupported base synth");
    });

    it("Can close the existing position", async () => {
      await poolManagerLogic.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [seth.address]),
        true,
      );
      await poolManagerLogic.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [susd.address]),
        true,
      );

      const closePositionABI = iOptionMarketWrapper.encodeFunctionData("closePosition", [
        [optionMarket.address, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await lyraOptionMarketWrapperContractGuard.txGuard(
        poolManagerLogic.address,
        optionMarketWrapper.address,
        closePositionABI,
      );
    });
  });

  describe("force close position", () => {
    it("Reverts if quote asset is not supported", async () => {
      const forceClosePositionABI = iOptionMarketWrapper.encodeFunctionData("forceClosePosition", [
        [optionMarket.address, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await expect(
        lyraOptionMarketWrapperContractGuard.txGuard(
          poolManagerLogic.address,
          optionMarketWrapper.address,
          forceClosePositionABI,
        ),
      ).to.revertedWith("unsupported quote synth");
    });

    it("Reverts if base asset is not supported", async () => {
      await poolManagerLogic.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [seth.address]),
        true,
      );

      const forceClosePositionABI = iOptionMarketWrapper.encodeFunctionData("forceClosePosition", [
        [optionMarket.address, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await expect(
        lyraOptionMarketWrapperContractGuard.txGuard(
          poolManagerLogic.address,
          optionMarketWrapper.address,
          forceClosePositionABI,
        ),
      ).to.revertedWith("unsupported base synth");
    });

    it("Can forc-close the existing position", async () => {
      await poolManagerLogic.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [seth.address]),
        true,
      );
      await poolManagerLogic.givenCalldataReturnBool(
        iPoolManagerLogic.encodeFunctionData("isSupportedAsset", [susd.address]),
        true,
      );

      const forceClosePositionABI = iOptionMarketWrapper.encodeFunctionData("forceClosePosition", [
        [optionMarket.address, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, susd.address],
      ]);

      await lyraOptionMarketWrapperContractGuard.txGuard(
        poolManagerLogic.address,
        optionMarketWrapper.address,
        forceClosePositionABI,
      );
    });
  });
});
