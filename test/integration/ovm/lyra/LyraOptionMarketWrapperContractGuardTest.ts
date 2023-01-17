import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { lyraUtils, TestSystemContractsType } from "@lyrafinance/protocol";
import {
  IERC20__factory,
  IOptionMarketWrapper__factory,
  ISynthAddressProxy,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { createFund } from "../../utils/createFund";
import { utils } from "../../utils/utils";
import { currentBlockTimestamp, units } from "../../../TestHelpers";
import { OptionPositionStructOutput } from "@lyrafinance/protocol/dist/typechain-types/OptionMarketViewer";
import { IERC721__factory, MockAggregatorV2V3 } from "@lyrafinance/protocol/dist/typechain-types";
import { solidityPack } from "ethers/lib/utils";
import { deployLyraTestSystem } from "./LyraTestHelpers";
import { ovmChainData } from "../../../../config/chainData/ovm-data";

describe("LyraOptionMarketWrapperContractGuard Test", function () {
  const iOptionMarketWrapper = new ethers.utils.Interface(IOptionMarketWrapper__factory.abi);
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iERC721 = new ethers.utils.Interface(IERC721__factory.abi);

  let quotekey: string, baseKey: string;
  let testSystem: TestSystemContractsType;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let susdProxy: ISynthAddressProxy;
  let ethMockAggregator: MockAggregatorV2V3;

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("ovm");
    testSystem = await deployLyraTestSystem(deployments, ovmChainData);
    poolFactory = deployments.poolFactory;

    // set chainlink timeout
    await deployments.assetHandler.setChainlinkTimeout(60 * 60 * 24 * 365 * 1000);

    quotekey = await testSystem.synthetixAdapter.quoteKey(testSystem.optionMarket.address);
    baseKey = await testSystem.synthetixAdapter.baseKey(testSystem.optionMarket.address);
    await testSystem.snx.addressResolver.setAddresses(
      [quotekey, baseKey],
      [testSystem.snx.quoteAsset.address, testSystem.snx.baseAsset.address],
    );
    await testSystem.basicFeeCounter.setTrustedCounter(testSystem.optionMarketWrapper.address, true);

    const boardIds = await testSystem.optionMarket.getLiveBoards();
    const strikeIds = await testSystem.optionMarket.getBoardStrikes(boardIds[0]);
    const strike = await testSystem.optionMarket.getStrike(strikeIds[0]);
    expect(strike.strikePrice).eq(lyraUtils.toBN("1500"));

    susdProxy = await ethers.getContractAt("ISynthAddressProxy", testSystem.snx.quoteAsset.address);

    const fund = await createFund(
      poolFactory,
      logicOwner,
      manager,
      [
        { asset: testSystem.snx.quoteAsset.address, isDeposit: true },
        { asset: testSystem.snx.baseAsset.address, isDeposit: true },
        { asset: testSystem.optionMarketWrapper.address, isDeposit: false },
      ],
      {
        performance: ethers.BigNumber.from("0"),
        management: ethers.BigNumber.from("0"),
      },
    );
    poolLogicProxy = fund.poolLogicProxy;
    poolManagerLogicProxy = fund.poolManagerLogicProxy;

    await testSystem.snx.quoteAsset.approve(poolLogicProxy.address, units(50000));
    await testSystem.snx.baseAsset.approve(poolLogicProxy.address, units(50000));

    const assetHandler = await ethers.getContractAt("AssetHandler", await poolFactory.getAssetHandler());
    ethMockAggregator = <MockAggregatorV2V3>(
      await ethers.getContractAt(
        "MockAggregatorV2V3",
        await assetHandler.priceAggregators(testSystem.snx.baseAsset.address),
      )
    );
    await ethMockAggregator.setLatestAnswer(
      (await testSystem.snx.exchangeRates.rateAndInvalid(baseKey)).rate
        .mul(await assetHandler.getUSDPrice(testSystem.snx.quoteAsset.address))
        .div(units(1, 28)),
      await currentBlockTimestamp(),
    );

    await testSystem.optionMarketWrapper.addCurveStable(testSystem.snx.quoteAsset.address, 0);
    await testSystem.optionMarketWrapper.addCurveStable(testSystem.snx.baseAsset.address, 1);
    const params = await testSystem.optionGreekCache.getMinCollatParams();
    await testSystem.optionGreekCache.setMinCollateralParameters({
      ...params,
      minStaticQuoteCollateral: units(1).div(2),
    });
  });

  let snapId: string;
  beforeEach(async () => {
    snapId = await utils.evmTakeSnap();
  });

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  it("it should check if lyra asset is enabled", async () => {
    await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
    const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
    await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

    const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
      [
        testSystem.optionMarket.address,
        1, // strike Id
        0, // position Id
        1, // iteration
        0, // set collateral to
        0, // current collateral
        0, // optionType - long call
        units(1), // amount
        0, // min cost
        ethers.constants.MaxUint256, // max cost
        units(500), // input amount
        testSystem.snx.quoteAsset.address, // input asset
      ],
    ]);

    // disable lyra asset
    await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.optionMarketWrapper.address]);

    // try to open position
    await expect(
      poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI),
    ).to.revertedWith("lyra not enabled");

    // enable lyra asset
    await poolManagerLogicProxy.connect(manager).changeAssets(
      [
        {
          asset: testSystem.optionMarketWrapper.address,
          isDeposit: false,
        },
      ],
      [],
    );

    // try to open position
    await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
  });

  describe("open position", () => {
    it("Reverts if input quote is not supported", async () => {
      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [testSystem.optionMarket.address, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, testSystem.snx.quoteAsset.address],
      ]);
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.quoteAsset.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI),
      ).to.revertedWith("unsupported quote asset");
    });

    it("Reverts if base asset is not supported", async () => {
      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [testSystem.optionMarket.address, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, testSystem.snx.quoteAsset.address],
      ]);
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.baseAsset.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI),
      ).to.revertedWith("unsupported base asset");
    });

    it("Reverts if reaches maximum positions count", async () => {
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          0, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          0, // optionType - long call
          units(1), // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          units(500), // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI),
      ).to.revertedWith("exceed maximum position count");
    });

    it("Can create a new option position", async () => {
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          0, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          0, // optionType - long call
          units(1), // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          units(500), // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);

      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.lt(susdBalanceBefore);
    });
  });

  describe("close position", () => {
    let position: OptionPositionStructOutput;

    it("Reverts if quote asset is not supported", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.quoteAsset.address]);

      const closePositionABI = iOptionMarketWrapper.encodeFunctionData("closePosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          1, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          0, // optionType - long call
          0, // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          0, // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closePositionABI),
      ).to.revertedWith("unsupported quote asset");
    });

    it("Reverts if base asset is not supported", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.baseAsset.address]);

      const closePositionABI = iOptionMarketWrapper.encodeFunctionData("closePosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          1, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          2, // optionType - short-call-base
          0, // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          0, // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closePositionABI),
      ).to.revertedWith("unsupported base asset");
    });

    it("Can close the existing position", async () => {
      // deposit
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));

      // approve
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      // open position
      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          0, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          0, // optionType - long call
          units(1), // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          units(500), // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);

      // close position
      const closePositionABI = iOptionMarketWrapper.encodeFunctionData("closePosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          position.positionId, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          0, // optionType - long call
          position.amount.div(2), // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          0, // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closePositionABI);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
    });
  });

  describe("force close position", () => {
    let position: OptionPositionStructOutput;

    it("Reverts if quote asset is not supported", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.quoteAsset.address]);

      const closePositionABI = iOptionMarketWrapper.encodeFunctionData("forceClosePosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          1, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          0, // optionType - long call
          0, // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          0, // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closePositionABI),
      ).to.revertedWith("unsupported quote asset");
    });

    it("Reverts if base asset is not supported", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.baseAsset.address]);

      const closePositionABI = iOptionMarketWrapper.encodeFunctionData("forceClosePosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          1, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          2, // optionType - long call
          0, // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          0, // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closePositionABI),
      ).to.revertedWith("unsupported base asset");
    });

    it("Can force close the existing position", async () => {
      // deposit
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));

      // approve
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      // open position
      const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          0, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          0, // optionType - long call
          units(1), // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          units(500), // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);

      // close position
      const closePositionABI = iOptionMarketWrapper.encodeFunctionData("forceClosePosition", [
        [
          testSystem.optionMarket.address,
          1, // strike Id
          position.positionId, // position Id
          1, // iteration
          0, // set collateral to
          0, // current collateral
          0, // optionType - long call
          position.amount.div(2), // amount
          0, // min cost
          ethers.constants.MaxUint256, // max cost
          0, // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closePositionABI);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
    });
  });

  describe("openLong", () => {
    it("Reverts if input quote is not supported", async () => {
      const openLongParam = solidityPack(
        ["uint64", "uint32", "uint32", "uint32", "uint8", "bool", "uint8", "uint8"],
        [0, 1, 0, 0, 0, true, 0, 0],
      );
      const openLongABI = iOptionMarketWrapper.encodeFunctionData("openLong", [openLongParam]);

      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.quoteAsset.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openLongABI),
      ).to.revertedWith("unsupported quote asset");
    });

    it("Reverts if reaches maximum positions count", async () => {
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openLongParam = solidityPack(
        ["uint64", "uint32", "uint32", "uint32", "uint8", "bool", "uint8", "uint8"],
        [units(1, 8), units(500, 2), units(1000, 2), 1, 1, true, 0, 0],
      );
      const openLongABI = iOptionMarketWrapper.encodeFunctionData("openLong", [openLongParam]);

      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openLongABI);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openLongABI);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openLongABI),
      ).to.revertedWith("exceed maximum position count");
    });

    it("Can create a new option position", async () => {
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openLongParam = solidityPack(
        ["uint64", "uint32", "uint32", "uint32", "uint8", "bool", "uint8", "uint8"],
        [units(1, 8), units(500, 2), units(1000, 2), 1, 1, true, 0, 0],
      );
      const openLongABI = iOptionMarketWrapper.encodeFunctionData("openLong", [openLongParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openLongABI);

      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.lt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });
  });

  describe("addLong", () => {
    let position;

    const openLong = async () => {
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openLongParam = solidityPack(
        ["uint64", "uint32", "uint32", "uint32", "uint8", "bool", "uint8", "uint8"],
        [units(1, 8), units(500, 2), units(1000, 2), 1, 1, true, 0, 0],
      );
      const openLongABI = iOptionMarketWrapper.encodeFunctionData("openLong", [openLongParam]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openLongABI);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);
    };

    it("add long positions", async () => {
      await openLong();
      const addLongParam = solidityPack(
        ["uint64", "uint32", "uint32", "uint32", "uint8", "uint8", "uint8"],
        [units(1, 8), units(500, 2), units(1000, 2), position.positionId, 1, 0, 0],
      );
      const addLongAbI = iOptionMarketWrapper.encodeFunctionData("addLong", [addLongParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, addLongAbI);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.lt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });
  });

  describe("reduceLong", () => {
    let position;
    const openLong = async () => {
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openLongParam = solidityPack(
        ["uint64", "uint32", "uint32", "uint32", "uint8", "bool", "uint8", "uint8"],
        [units(1, 8), units(500, 2), units(1000, 2), 1, 1, true, 0, 0],
      );
      const openLongABI = iOptionMarketWrapper.encodeFunctionData("openLong", [openLongParam]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openLongABI);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);
    };

    it("close: reduce long positions", async () => {
      await openLong();
      const reduceLongParam = solidityPack(
        ["uint32", "uint64", "uint32", "uint32", "bool", "uint8", "uint8", "uint8"],
        [0, position.amount.div(2).div(units(1, 16)), 0, position.positionId, false, 1, 0, 0],
      );
      const reduceLongAbi = iOptionMarketWrapper.encodeFunctionData("reduceLong", [reduceLongParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, reduceLongAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });

    it("force-close: reduce long positions", async () => {
      await openLong();
      const reduceLongParam = solidityPack(
        ["uint32", "uint64", "uint32", "uint32", "bool", "uint8", "uint8", "uint8"],
        [0, position.amount.div(2).div(units(1, 16)), 0, position.positionId, true, 1, 0, 0],
      );
      const reduceLongAbi = iOptionMarketWrapper.encodeFunctionData("reduceLong", [reduceLongParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, reduceLongAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });
  });

  describe("closeLong", () => {
    let position;
    const openLong = async () => {
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openLongParam = solidityPack(
        ["uint64", "uint32", "uint32", "uint32", "uint8", "bool", "uint8", "uint8"],
        [units(1, 8), units(500, 2), units(1000, 2), 1, 1, true, 0, 0],
      );
      const openLongABI = iOptionMarketWrapper.encodeFunctionData("openLong", [openLongParam]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openLongABI);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);
    };

    it("close: close long positions", async () => {
      await openLong();
      const closeLongParam = solidityPack(
        ["uint32", "uint32", "uint32", "bool", "uint8", "uint8", "uint8"],
        [0, 0, position.positionId, false, 1, 0, 0],
      );
      const closeLongAbi = iOptionMarketWrapper.encodeFunctionData("closeLong", [closeLongParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closeLongAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });

    it("force-close: close long positions", async () => {
      await openLong();
      const closeLongParam = solidityPack(
        ["uint32", "uint32", "uint32", "bool", "uint8", "uint8", "uint8"],
        [0, 0, position.positionId, true, 1, 0, 0],
      );
      const closeLongAbi = iOptionMarketWrapper.encodeFunctionData("closeLong", [closeLongParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closeLongAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
      // 1% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(totalFundBefore, totalFundBefore.div(100));
    });
  });

  describe("openShort", () => {
    it("Reverts if input quote is not supported", async () => {
      const openShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "uint8", "uint8", "uint8", "uint8"],
        [0, 0, 1, 0, 0, 0, 3, 0, 0],
      );
      const openShortAbi = iOptionMarketWrapper.encodeFunctionData("openShort", [openShortParam]);

      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.quoteAsset.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openShortAbi),
      ).to.revertedWith("unsupported quote asset");
    });

    it("Reverts if input base is not supported", async () => {
      const openShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "uint8", "uint8", "uint8", "uint8"],
        [0, 0, 1, 0, 0, 0, 2, 0, 0],
      );
      const openShortAbi = iOptionMarketWrapper.encodeFunctionData("openShort", [openShortParam]);

      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.baseAsset.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openShortAbi),
      ).to.revertedWith("unsupported base asset");
    });

    it("Reverts if reaches maximum positions count", async () => {
      await poolLogicProxy.deposit(testSystem.snx.baseAsset.address, units(10));
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(50000));
      let approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(10)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.baseAsset.address, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(50000)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.quoteAsset.address, approveABI);

      const openShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "uint8", "uint8", "uint8", "uint8"],
        [units(1, 8), units(1, 5), units(5000, 2), 0, 1, 1, 3, 0, 0],
      );
      const openShortAbi = iOptionMarketWrapper.encodeFunctionData("openShort", [openShortParam]);

      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openShortAbi);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openShortAbi);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openShortAbi),
      ).to.revertedWith("exceed maximum position count");
    });

    it("Can create a new option position", async () => {
      await poolLogicProxy.deposit(testSystem.snx.baseAsset.address, units(1));
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      let approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(1)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.baseAsset.address, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.quoteAsset.address, approveABI);

      const openShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "uint8", "uint8", "uint8", "uint8"],
        [units(1, 8), units(1, 5), units(5000, 2), 0, 1, 1, 3, 0, 0],
      );
      const openShortAbi = iOptionMarketWrapper.encodeFunctionData("openShort", [openShortParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openShortAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.lt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });
  });

  describe("addShort", () => {
    let position;

    const openShort = async () => {
      await poolLogicProxy.deposit(testSystem.snx.baseAsset.address, units(10));
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(50000));
      let approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(10)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.baseAsset.address, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(50000)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.quoteAsset.address, approveABI);

      const openShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "uint8", "uint8", "uint8", "uint8"],
        [units(1, 8), units(1, 5), units(5000, 2), 0, 1, 1, 3, 0, 0],
      );
      const openShortAbi = iOptionMarketWrapper.encodeFunctionData("openShort", [openShortParam]);

      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openShortAbi);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);
    };

    it("can add short", async () => {
      await openShort();
      const addShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "uint8", "uint8", "uint8"],
        [units(2, 8), units(1, 5), 0, units(5000, 2), position.positionId, 1, 0, 0],
      );
      const addShortAbi = iOptionMarketWrapper.encodeFunctionData("addShort", [addShortParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, addShortAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.lt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });
  });

  describe("reduceShort", () => {
    let position;

    const openShort = async () => {
      await poolLogicProxy.deposit(testSystem.snx.baseAsset.address, units(10));
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(50000));
      let approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(10)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.baseAsset.address, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(50000)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.quoteAsset.address, approveABI);

      const openShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "uint8", "uint8", "uint8", "uint8"],
        [units(1, 8), units(1, 5), units(5000, 2), 0, 1, 1, 3, 0, 0],
      );
      const openShortAbi = iOptionMarketWrapper.encodeFunctionData("openShort", [openShortParam]);

      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openShortAbi);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);
    };

    it("close: can reduce short", async () => {
      await openShort();
      const reduceShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "bool", "uint8", "uint8", "uint8"],
        [0, position.amount.div(units(1, 10)), units(1000000, 2), 0, position.positionId, false, 1, 0, 0],
      );
      const reduceShortAbi = iOptionMarketWrapper.encodeFunctionData("reduceShort", [reduceShortParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, reduceShortAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });

    it("forceclose: can reduce short", async () => {
      await openShort();
      const reduceShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "bool", "uint8", "uint8", "uint8"],
        [0, position.amount.div(units(1, 10)), units(1000000, 2), 0, position.positionId, true, 1, 0, 0],
      );
      const reduceShortAbi = iOptionMarketWrapper.encodeFunctionData("reduceShort", [reduceShortParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, reduceShortAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });
  });

  describe("closeShort", () => {
    let position;

    const openShort = async () => {
      await poolLogicProxy.deposit(testSystem.snx.baseAsset.address, units(10));
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(50000));
      let approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(10)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.baseAsset.address, approveABI);
      approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, units(50000)]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.snx.quoteAsset.address, approveABI);

      const openShortParam = solidityPack(
        ["uint64", "uint64", "uint32", "uint32", "uint32", "uint8", "uint8", "uint8", "uint8"],
        [units(1, 8), units(1, 5), units(5000, 2), 0, 1, 1, 3, 0, 0],
      );
      const openShortAbi = iOptionMarketWrapper.encodeFunctionData("openShort", [openShortParam]);

      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openShortAbi);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);
    };

    it("close: can close short", async () => {
      await openShort();
      const closeShortParam = solidityPack(
        ["uint32", "uint32", "uint32", "bool", "uint8", "uint8", "uint8"],
        [units(1000000, 2), 0, position.positionId, false, 1, 0, 0],
      );
      const closeShortAbi = iOptionMarketWrapper.encodeFunctionData("closeShort", [closeShortParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closeShortAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });

    it("forceclose: can close short", async () => {
      await openShort();
      const closeShortParam = solidityPack(
        ["uint32", "uint32", "uint32", "bool", "uint8", "uint8", "uint8"],
        [units(1000000, 2), 0, position.positionId, true, 1, 0, 0],
      );
      const closeShortAbi = iOptionMarketWrapper.encodeFunctionData("closeShort", [closeShortParam]);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, closeShortAbi);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore,
        totalFundBefore.mul(5).div(1000),
      );
    });
  });

  it("test direct interaction with wrapper", async () => {
    await testSystem.snx.quoteAsset.approve(testSystem.optionMarketWrapper.address, units(5000));
    await testSystem.optionMarketWrapper.openPosition({
      optionMarket: testSystem.optionMarket.address,
      strikeId: 1, // strike Id
      positionId: 0, // position Id
      iterations: 1, // iteration
      setCollateralTo: 0, // set collateral to
      currentCollateral: 0, // current collateral
      optionType: 0, // optionType - long call
      amount: units(1), // amount
      minCost: 0, // min cost
      maxCost: ethers.constants.MaxUint256, // max cost
      inputAmount: units(500), // input amount
      inputAsset: testSystem.snx.quoteAsset.address, // input asset
    });

    const position = (await testSystem.optionToken.getOwnerPositions(logicOwner.address))[0];

    await testSystem.optionToken.approve(testSystem.optionMarketWrapper.address, position.positionId);
    await testSystem.optionMarketWrapper.forceClosePosition({
      optionMarket: testSystem.optionMarket.address,
      strikeId: 1, // strike Id
      positionId: position.positionId, // position Id
      iterations: 1, // iteration
      setCollateralTo: 0, // set collateral to
      currentCollateral: 0, // current collateral
      optionType: 0, // optionType - long call
      amount: position.amount.div(2), // amount
      minCost: 0, // min cost
      maxCost: ethers.constants.MaxUint256, // max cost
      inputAmount: 0, // input amount
      inputAsset: testSystem.snx.quoteAsset.address, // input asset
    });
  });
});
