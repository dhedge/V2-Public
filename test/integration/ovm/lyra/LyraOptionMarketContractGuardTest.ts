import { lyraUtils, TestSystemContractsType } from "@lyrafinance/protocol";
import { IERC721__factory, MockAggregatorV2V3 } from "@lyrafinance/protocol/dist/typechain-types";
import { OptionPositionStructOutput } from "@lyrafinance/protocol/dist/typechain-types/OptionMarketViewer";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { assert, expect } from "chai";
import { ethers } from "hardhat";
import { ovmChainData } from "../../../../config/chainData/ovmData";
import { IERC20__factory, ISynthAddressProxy, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { currentBlockTimestamp, units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { deployLyraTestSystem } from "./LyraTestHelpers";

describe("LyraOptionMarketWrapperContractGuard Test", function () {
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
    await testSystem.basicFeeCounter.setTrustedCounter(testSystem.optionMarket.address, true);

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

  utils.beforeAfterReset(beforeEach, afterEach);

  it("it should check if lyra asset is enabled", async () => {
    const openPositionABI = await testSystem.optionMarket.populateTransaction.openPosition({
      amount: units(1),
      iterations: 1,
      maxTotalCost: ethers.constants.MaxUint256,
      minTotalCost: 0,
      optionType: 0,
      positionId: 0,
      setCollateralTo: 0,
      strikeId: 1,
    });

    assert(openPositionABI.data);

    // disable lyra asset
    await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.optionMarketWrapper.address]);

    // try to open position
    await expect(
      poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, openPositionABI.data),
    ).to.revertedWith("lyra not enabled");
  });

  describe("open position", () => {
    it("Reverts if input quote is not supported", async () => {
      const openPositionABI = await testSystem.optionMarket.populateTransaction.openPosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: 0,
        setCollateralTo: 0,
        strikeId: 1,
      });

      assert(openPositionABI.data);
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.quoteAsset.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, openPositionABI.data),
      ).to.revertedWith("unsupported quote asset");
    });

    it("Reverts if base asset is not supported", async () => {
      const optionType = 2; // short
      const openPositionABI = await testSystem.optionMarket.populateTransaction.openPosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: optionType,
        positionId: 0,
        setCollateralTo: 0,
        strikeId: 1,
      });

      assert(openPositionABI.data);
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.baseAsset.address]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, openPositionABI.data),
      ).to.revertedWith("unsupported base asset");
    });

    it("Can create a new option position", async () => {
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarket.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openPositionABI = await testSystem.optionMarket.populateTransaction.openPosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: 0,
        setCollateralTo: 0,
        strikeId: 1,
      });
      assert(openPositionABI.data);

      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, openPositionABI.data);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.lt(susdBalanceBefore);
    });

    it("Reverts if reaches maximum positions count", async () => {
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarket.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openPositionABI = await testSystem.optionMarket.populateTransaction.openPosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: 0,
        setCollateralTo: 0,
        strikeId: 1,
      });
      assert(openPositionABI.data);

      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, openPositionABI.data);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, openPositionABI.data);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, openPositionABI.data),
      ).to.revertedWith("exceed maximum position count");
    });
  });

  describe("close position", () => {
    let position: OptionPositionStructOutput;

    it("Reverts if quote asset is not supported", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.quoteAsset.address]);

      const closePositionABI = await testSystem.optionMarket.populateTransaction.closePosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: 1,
        setCollateralTo: 0,
        strikeId: 1,
      });

      assert(closePositionABI.data);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, closePositionABI.data),
      ).to.revertedWith("unsupported quote asset");
    });

    it("Reverts if base asset is not supported", async () => {
      const optionType = 2; // short
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.baseAsset.address]);
      const closePositionABI = await testSystem.optionMarket.populateTransaction.closePosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType,
        positionId: 1,
        setCollateralTo: 0,
        strikeId: 1,
      });

      assert(closePositionABI.data);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, closePositionABI.data),
      ).to.revertedWith("unsupported base asset");
    });

    it("Can close the existing position", async () => {
      // deposit
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));

      // approve
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarket.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      // open position
      const openPositionABI = await testSystem.optionMarket.populateTransaction.openPosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: 0,
        setCollateralTo: 0,
        strikeId: 1,
      });
      assert(openPositionABI.data);

      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, openPositionABI.data);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarket.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);

      // close position
      const closePositionABI = await testSystem.optionMarket.populateTransaction.closePosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: position.positionId,
        setCollateralTo: 0,
        strikeId: 1,
      });

      assert(closePositionABI.data);
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, closePositionABI.data);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
    });
  });

  describe("force close position", () => {
    let position: OptionPositionStructOutput;

    it("Reverts if quote asset is not supported", async () => {
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.quoteAsset.address]);

      const closePositionABI = await testSystem.optionMarket.populateTransaction.forceClosePosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: 1,
        setCollateralTo: 0,
        strikeId: 1,
      });

      assert(closePositionABI.data);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, closePositionABI.data),
      ).to.revertedWith("unsupported quote asset");
    });

    it("Reverts if base asset is not supported", async () => {
      const optionType = 2; // short
      await poolManagerLogicProxy.connect(manager).changeAssets([], [testSystem.snx.baseAsset.address]);

      const closePositionABI = await testSystem.optionMarket.populateTransaction.forceClosePosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType,
        positionId: 1,
        setCollateralTo: 0,
        strikeId: 1,
      });

      assert(closePositionABI.data);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, closePositionABI.data),
      ).to.revertedWith("unsupported base asset");
    });

    it("Can force close the existing position", async () => {
      // deposit
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, units(5000));

      // approve
      const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarket.address, units(5000)]);
      await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

      const openPositionABI = await testSystem.optionMarket.populateTransaction.openPosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: 0,
        setCollateralTo: 0,
        strikeId: 1,
      });
      assert(openPositionABI.data);

      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, openPositionABI.data);

      position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];

      // approve
      const optionTokenApproveABI = iERC721.encodeFunctionData("approve", [
        testSystem.optionMarket.address,
        position.positionId,
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionToken.address, optionTokenApproveABI);

      // close position
      const closePositionABI = await testSystem.optionMarket.populateTransaction.closePosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: position.positionId,
        setCollateralTo: 0,
        strikeId: 1,
      });

      assert(closePositionABI.data);
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, closePositionABI.data);
      const susdBalanceAfter = await susdProxy.balanceOf(poolLogicProxy.address);
      expect(susdBalanceAfter).to.gt(susdBalanceBefore);
    });
  });

  describe("addCollateral", () => {
    it("reverts if pool does not own position", async () => {
      // create a real position not owned by the pool
      await testSystem.snx.quoteAsset.approve(testSystem.optionMarket.address, units(5000));
      await testSystem.optionMarket.openPosition({
        amount: units(1),
        iterations: 1,
        maxTotalCost: ethers.constants.MaxUint256,
        minTotalCost: 0,
        optionType: 0,
        positionId: 0,
        setCollateralTo: 0,
        strikeId: 1,
      });

      const position = (await testSystem.optionToken.getOwnerPositions(logicOwner.address))[0];
      const addCollateralAbi = await testSystem.optionMarket.populateTransaction.addCollateral(
        position.positionId,
        units(1),
      );
      assert(addCollateralAbi.data);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, addCollateralAbi.data),
      ).to.be.revertedWith("not position owner");
    });
  });

  describe("liquidatePosition", () => {
    it("reverts if beneficiary is not pool", async () => {
      const liquidateABI = await testSystem.optionMarket.populateTransaction.liquidatePosition(
        0,
        ethers.Wallet.createRandom().address,
      );
      assert(liquidateABI.data);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarket.address, liquidateABI.data),
      ).to.be.revertedWith("reward beneficiary not pool");
    });
  });
});
