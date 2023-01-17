import { ethers } from "hardhat";
import { expect } from "chai";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { lyraUtils, TestSystemContractsType } from "@lyrafinance/protocol";
import { IERC20__factory, MockAggregatorV2V3 } from "@lyrafinance/protocol/dist/typechain-types";
import { ovmChainData } from "../../../../config/chainData/ovm-data";
import {
  IOptionMarketWrapper__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  ISynthAddressProxy,
  LyraOptionMarketWrapperAssetGuard,
} from "../../../../types";
import { currentBlockTimestamp, toBytes32, units } from "../../../TestHelpers";
import { createFund } from "../../utils/createFund";
import { BigNumber } from "ethers";
import { deployLyraTestSystem } from "./LyraTestHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const collateralAmount = units(1);

describe("LyraOptionMarketWrapperAssetGuard Test", function () {
  const { assets } = ovmChainData;
  const iOptionMarketWrapper = new ethers.utils.Interface(IOptionMarketWrapper__factory.abi);
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

  let quotekey: string, baseKey: string;
  let testSystem: TestSystemContractsType;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  let susdProxy: ISynthAddressProxy, sethProxy: ISynthAddressProxy;
  let ethMockAggregator: MockAggregatorV2V3;

  const susdInvestAmount = units(5000);
  const sethInvestAmount = units(1);

  let lyraOptionMarketWrapperAssetGuard: LyraOptionMarketWrapperAssetGuard;
  let totalFundBeforeInvest: BigNumber;

  const increaseTimeAndBuyOption = async (times = 1) => {
    // disable circuit breaker update
    const liquidityPoolParams = await testSystem.liquidityPool.lpParams();
    await testSystem.liquidityPool.setLiquidityPoolParameters({
      ...liquidityPoolParams,
      ivVarianceCBTimeout: 0,
      skewVarianceCBTimeout: 0,
      liquidityCBTimeout: 0,
    });
    // buy options
    for (let i = 0; i < times; i++) {
      await utils.increaseTime(60 * 60 * 2);
      await testSystem.snx.quoteAsset.approve(testSystem.optionMarketWrapper.address, units(500000));
      await testSystem.optionMarketWrapper.openPosition({
        optionMarket: testSystem.optionMarket.address,
        strikeId: 1, // strike Id
        positionId: 0, // position Id
        iterations: 1, // iteration
        setCollateralTo: 0, // set collateral to
        currentCollateral: 0, // current collateral
        optionType: 0, // optionType - long call
        amount: units(100), // amount
        minCost: 0, // min cost
        maxCost: ethers.constants.MaxUint256, // max cost
        inputAmount: units(500000), // input amount
        inputAsset: testSystem.snx.quoteAsset.address, // input asset
      });
    }
  };

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("ovm");
    testSystem = await deployLyraTestSystem(deployments, ovmChainData);
    poolFactory = deployments.poolFactory;

    await poolFactory.setExitCooldown(60 * 5);

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
    sethProxy = await ethers.getContractAt("ISynthAddressProxy", testSystem.snx.baseAsset.address);

    const fund = await createFund(
      poolFactory,
      logicOwner,
      manager,
      [
        { asset: testSystem.snx.quoteAsset.address, isDeposit: true },
        { asset: testSystem.snx.baseAsset.address, isDeposit: true },
        { asset: testSystem.optionMarketWrapper.address, isDeposit: false },
        { asset: assets.snxProxy, isDeposit: false },
      ],
      {
        performance: ethers.BigNumber.from("0"),
        management: ethers.BigNumber.from("0"),
      },
    );
    poolLogicProxy = fund.poolLogicProxy;
    poolManagerLogicProxy = fund.poolManagerLogicProxy;

    await susdProxy.approve(poolLogicProxy.address, susdInvestAmount.mul(5));
    await sethProxy.approve(poolLogicProxy.address, sethInvestAmount.mul(5));

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

    // prepare aave flashloan mock
    const lyraOptionMarketWrapperAssetGuardAddress = await poolFactory.getAssetGuard(
      testSystem.optionMarketWrapper.address,
    );
    lyraOptionMarketWrapperAssetGuard = await ethers.getContractAt(
      "LyraOptionMarketWrapperAssetGuard",
      lyraOptionMarketWrapperAssetGuardAddress,
    );
    const dhedgeWrapper = await ethers.getContractAt(
      "DhedgeOptionMarketWrapperForLyra",
      await lyraOptionMarketWrapperAssetGuard.dhedgeLyraWrapper(),
    );
    const aaveFlashloanMock = await ethers.getContractAt("AaveFlashloanMock", await dhedgeWrapper.aaveLendingPool());
    await testSystem.snx.quoteAsset.mint(logicOwner.address, units(10000000));
    await testSystem.snx.quoteAsset.connect(logicOwner).transfer(aaveFlashloanMock.address, units(10000000));
  });

  const openLongCall = async () => {
    // deposit
    await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, susdInvestAmount);

    totalFundBeforeInvest = await poolManagerLogicProxy.totalFundValue();

    // approve
    const approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, susdInvestAmount]);
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
        susdInvestAmount, // input amount
        testSystem.snx.quoteAsset.address, // input asset
      ],
    ]);
    await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
  };

  utils.beforeAfterReset(beforeEach, afterEach);

  // Divergence
  describe("Divergance CB", () => {
    it("assertNoGWAVDivergence", async () => {
      // Wont revert
      await lyraOptionMarketWrapperAssetGuard.assertNoGWAVDivergence(100, 98);
      // Will revert more than 3% divergence
      await expect(lyraOptionMarketWrapperAssetGuard.assertNoGWAVDivergence(100, 96)).to.be.revertedWith(
        "gwav divergence too high",
      );
    });

    it("getGWAVCallPrice Reverts on more than 3% divergance", async () => {
      await lyraOptionMarketWrapperAssetGuard.getGWAVCallPrice(testSystem.optionMarket.address, 1);
      await openLongCall();
      await increaseTimeAndBuyOption(2);
      await expect(
        lyraOptionMarketWrapperAssetGuard.getGWAVCallPrice(testSystem.optionMarket.address, 1),
      ).to.be.revertedWith("gwav divergence too high");
    });

    it("getGWAVPutPrice Reverts on more than 3% divergance", async () => {
      await lyraOptionMarketWrapperAssetGuard.getGWAVPutPrice(testSystem.optionMarket.address, 1);
      await openLongCall();
      await increaseTimeAndBuyOption(2);
      await expect(
        lyraOptionMarketWrapperAssetGuard.getGWAVPutPrice(testSystem.optionMarket.address, 1),
      ).to.be.revertedWith("gwav divergence too high");
    });
  });

  describe("getBalance", () => {
    describe("Price LONG-CALL", () => {
      it("just after deposit", async () => {
        await openLongCall();
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBeforeInvest,
          totalFundBeforeInvest.mul(5).div(1000),
        );
      });

      it("after huge price dump", async () => {
        await openLongCall();
        const totalFundBeforePriceDump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(50).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPriceDump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPriceDump).lt(totalFundBeforePriceDump);
      });

      it("after huge price pump", async () => {
        await openLongCall();
        const totalFundBeforePricePump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(150).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPricePump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPricePump).gt(totalFundBeforePricePump);
      });

      it("Pool has expected funds after withdraw", async () => {
        await openLongCall();
        const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
        const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw half
        await utils.increaseTime(60 * 5);
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.be.closeTo(susdBalanceBefore.div(2), 1);
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBefore.div(2),
          totalFundBefore.mul(5).div(1000),
        );
      });

      it("Use PRICE_GWAV_DURATION callPrice for long-call option", async () => {
        await openLongCall();

        const assetBalance = await poolManagerLogicProxy.assetBalance(testSystem.optionMarketWrapper.address);
        const position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];
        const nowPrices = await testSystem.GWAVOracle.optionPriceGWAV(
          position.strikeId,
          await lyraOptionMarketWrapperAssetGuard.PRICE_GWAV_DURATION(),
        );

        expect(assetBalance).to.equal(nowPrices.callPrice.mul(position.amount).div(units(1)));
      });
    });

    describe("Price LONG-PUT", () => {
      const openLongPut = async () => {
        // deposit
        await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, susdInvestAmount);

        totalFundBeforeInvest = await poolManagerLogicProxy.totalFundValue();

        // approve
        const approveABI = iERC20.encodeFunctionData("approve", [
          testSystem.optionMarketWrapper.address,
          susdInvestAmount,
        ]);
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
            1, // optionType - long put
            units(1), // amount
            0, // min cost
            ethers.constants.MaxUint256, // max cost
            susdInvestAmount, // input amount
            testSystem.snx.quoteAsset.address, // input asset
          ],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
      };

      it("just after deposit", async () => {
        await openLongPut();
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBeforeInvest,
          totalFundBeforeInvest.mul(5).div(1000),
        );
      });

      it("after huge price dump", async () => {
        await openLongPut();
        const totalFundBeforePriceDump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(50).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPriceDump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPriceDump).gt(totalFundBeforePriceDump);
      });

      it("after huge price pump", async () => {
        await openLongPut();
        const totalFundBeforePricePump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(150).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPricePump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPricePump).lt(totalFundBeforePricePump);
      });

      it("Pool has expected funds after withdraw", async () => {
        await openLongPut();
        const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
        const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw half
        await utils.increaseTime(60 * 5);
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.be.closeTo(susdBalanceBefore.div(2), 1);
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBefore.div(2),
          totalFundBefore.mul(5).div(1000),
        );
      });

      it("Use PRICE_GWAV_DURATION putPrice for long-put option", async () => {
        await openLongPut();

        const assetBalance = await poolManagerLogicProxy.assetBalance(testSystem.optionMarketWrapper.address);
        const position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];
        const nowPrices = await testSystem.GWAVOracle.optionPriceGWAV(
          position.strikeId,
          await lyraOptionMarketWrapperAssetGuard.PRICE_GWAV_DURATION(),
        );

        expect(assetBalance).to.equal(nowPrices.putPrice.mul(position.amount).div(units(1)));
      });
    });

    // When withdrawing SHORT-PUT-QUOTE/SHORT-CALL-QUOTE/SHORT-CALL-BASE the DhedgeOptionMarketWrapperForLyra
    // uses the synthetix `Exchanger` it gets from the lyra TestSystem via lyraRegistry.synthetixAdapter.exchanger().
    // Unfortunately the TestSystem only implements `feeRateForExchange` and not `getAmountsForExchange`
    // So here we replace the `Exchanger` with a Mocked version that has `getAmountsForExchange`
    const replaceTestSystemExchanger = async () => {
      const baseAssetSymbol = await testSystem.snx.baseAsset.symbol();
      const { rate } = await testSystem.snx.exchangeRates.rateAndInvalid(toBytes32(baseAssetSymbol));

      const amountToBorrow = units(1).mul(rate).div(units(1));

      const MockContract = await ethers.getContractFactory("MockContract");
      const mockExchanger = await MockContract.deploy();

      await mockExchanger.givenMethodReturn(
        ethers.utils.id("getAmountsForExchange(uint256,bytes32,bytes32)"),
        ethers.utils.solidityPack(["uint256", "uint256", "uint256"], [amountToBorrow, 0, 0]),
      );

      // This is the only function implemented by the TestSystem
      await mockExchanger.givenMethodReturn(
        ethers.utils.id("feeRateForExchange(bytes32,bytes32)"),
        ethers.utils.solidityPack(["uint256"], [0]),
      );

      await testSystem.snx.addressResolver.setAddresses([toBytes32("Exchanger")], [mockExchanger.address]);
      await testSystem.synthetixAdapter.updateSynthetixAddresses();
    };

    describe("Price SHORT-CALL-BASE", () => {
      const openShortCallBase = async () => {
        // deposit
        await poolLogicProxy.deposit(testSystem.snx.baseAsset.address, sethInvestAmount);

        totalFundBeforeInvest = await poolManagerLogicProxy.totalFundValue();

        // approve
        const approveABI = iERC20.encodeFunctionData("approve", [
          testSystem.optionMarketWrapper.address,
          sethInvestAmount,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(sethProxy.address, approveABI);

        // open position
        const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
          [
            testSystem.optionMarket.address,
            1, // strike Id
            0, // position Id
            1, // iteration
            collateralAmount, // set collateral to
            0, // current collateral
            2, // optionType - short call base
            units(1), // amount
            0, // min cost
            ethers.constants.MaxUint256, // max cost
            0, // input amount
            testSystem.snx.quoteAsset.address, // input asset
          ],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
      };

      it("just after deposit", async () => {
        await openShortCallBase();
        // 0.5% difference (consider option price)
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBeforeInvest.sub(units(20)),
          totalFundBeforeInvest.mul(5).div(1000),
        );
      });

      it("after huge price dump", async () => {
        await openShortCallBase();
        const totalFundBeforePriceDump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(50).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPriceDump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPriceDump).lt(totalFundBeforePriceDump);
      });

      it("after huge price pump", async () => {
        await openShortCallBase();
        const totalFundBeforePricePump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(150).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPricePump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPricePump).gt(totalFundBeforePricePump);
      });

      it("Pool has expected funds after half withdraw", async () => {
        await openShortCallBase();
        const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
        const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw half
        await utils.increaseTime(60 * 5);

        await replaceTestSystemExchanger();
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.be.closeTo(susdBalanceBefore.div(2), 1);
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBefore.div(2),
          totalFundBefore.mul(5).div(1000),
        );
      });

      it("Pool has expected funds after all-withdraw", async () => {
        await openShortCallBase();
        // withdraw half
        await utils.increaseTime(60 * 5);

        await replaceTestSystemExchanger();
        await poolLogicProxy.withdraw(await poolLogicProxy.balanceOf(logicOwner.address));

        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.be.equal(0);
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.equal(0);
      });

      it("Use PRICE_GWAV_DURATION callPrice for short-call base option", async () => {
        await openShortCallBase();

        const assetBalance = await poolManagerLogicProxy.assetBalance(testSystem.optionMarketWrapper.address);
        const position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];
        const basePrice = await testSystem.synthetixAdapter.getSpotPriceForMarket(testSystem.optionMarket.address);
        const nowPrices = await testSystem.GWAVOracle.optionPriceGWAV(
          position.strikeId,
          await lyraOptionMarketWrapperAssetGuard.PRICE_GWAV_DURATION(),
        );

        expect(assetBalance).to.equal(
          position.collateral
            .mul(basePrice)
            .div(units(1))
            .sub(nowPrices.callPrice.mul(position.amount).div(units(1))),
        );
      });
    });

    describe("Price SHORT-CALL-QUOTE", () => {
      const openShortCallQuote = async () => {
        const params = await testSystem.optionGreekCache.getMinCollatParams();
        await testSystem.optionGreekCache.setMinCollateralParameters({
          ...params,
          minStaticQuoteCollateral: units(1).div(2),
        });

        // deposit
        await poolLogicProxy.deposit(testSystem.snx.baseAsset.address, sethInvestAmount);
        await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, susdInvestAmount);

        totalFundBeforeInvest = await poolManagerLogicProxy.totalFundValue();

        // approve
        let approveABI = iERC20.encodeFunctionData("approve", [
          testSystem.optionMarketWrapper.address,
          sethInvestAmount,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(sethProxy.address, approveABI);
        approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, susdInvestAmount]);
        await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

        // open position
        const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
          [
            testSystem.optionMarket.address,
            1, // strike Id
            0, // position Id
            1, // iteration
            collateralAmount, // set collateral to
            0, // current collateral
            3, // optionType - short call quote
            units(1, 15), // amount
            0, // min cost
            ethers.constants.MaxUint256, // max cost
            susdInvestAmount, // input amount
            testSystem.snx.quoteAsset.address, // input asset
          ],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
      };

      it("just after deposit", async () => {
        await openShortCallQuote();
        // 0.5% difference (consider option price)
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBeforeInvest,
          totalFundBeforeInvest.mul(5).div(1000),
        );
      });

      it("after huge price dump", async () => {
        await openShortCallQuote();
        const totalFundBeforePriceDump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(50).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPriceDump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPriceDump).gt(totalFundBeforePriceDump);
      });

      it("after huge price pump", async () => {
        await openShortCallQuote();
        const totalFundBeforePricePump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(110).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPricePump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPricePump).lt(totalFundBeforePricePump);
      });

      it("expect zero if callValue is more than collateralValue", async () => {
        await openShortCallQuote();
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(200).div(100),
          baseKeyRate.invalid,
        );

        expect(await poolManagerLogicProxy["assetValue(address)"](testSystem.optionMarketWrapper.address)).to.eq(0);
      });

      it("Pool has expected funds after withdraw", async () => {
        await openShortCallQuote();
        const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
        const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw half
        await utils.increaseTime(60 * 5);
        await replaceTestSystemExchanger();
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.be.closeTo(susdBalanceBefore.div(2), 1);
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBefore.div(2),
          totalFundBefore.mul(5).div(1000),
        );
      });

      it("Should fully close the option position if less than the minCollatAmount after withdraw", async () => {
        await openShortCallQuote();
        // increase min static base collateral
        const minCollatParams = await testSystem.optionGreekCache.getMinCollatParams();
        await testSystem.optionGreekCache.setMinCollateralParameters({
          ...minCollatParams,
          minStaticQuoteCollateral: units(1),
        });

        // withdraw 99% and it should fully close the option position
        await utils.increaseTime(60 * 5);
        await replaceTestSystemExchanger();
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).mul(99).div(100));

        expect(await testSystem.optionToken.balanceOf(poolLogicProxy.address)).to.equal(0);
      });

      it("Use PRICE_GWAV_DURATION callPrice for short-call quote option", async () => {
        await openShortCallQuote();
        const assetBalance = await poolManagerLogicProxy.assetBalance(testSystem.optionMarketWrapper.address);
        const position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];
        const nowPrices = await testSystem.GWAVOracle.optionPriceGWAV(
          position.strikeId,
          await lyraOptionMarketWrapperAssetGuard.PRICE_GWAV_DURATION(),
        );

        expect(assetBalance).to.equal(position.collateral.sub(nowPrices.callPrice.mul(position.amount).div(units(1))));
      });
    });

    describe("Price SHORT-PUT-QUOTE", () => {
      const openShortPutQuote = async () => {
        const params = await testSystem.optionGreekCache.getMinCollatParams();
        await testSystem.optionGreekCache.setMinCollateralParameters({
          ...params,
          minStaticQuoteCollateral: units(1).div(2),
        });

        // deposit
        await poolLogicProxy.deposit(testSystem.snx.baseAsset.address, sethInvestAmount);
        await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, susdInvestAmount);

        totalFundBeforeInvest = await poolManagerLogicProxy.totalFundValue();

        // approve
        let approveABI = iERC20.encodeFunctionData("approve", [
          testSystem.optionMarketWrapper.address,
          sethInvestAmount,
        ]);
        await poolLogicProxy.connect(manager).execTransaction(sethProxy.address, approveABI);
        approveABI = iERC20.encodeFunctionData("approve", [testSystem.optionMarketWrapper.address, susdInvestAmount]);
        await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

        // open position
        const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
          [
            testSystem.optionMarket.address,
            1, // strike Id
            0, // position Id
            1, // iteration
            collateralAmount, // set collateral to
            0, // current collateral
            4, // optionType - short put quote
            units(1, 15), // amount
            0, // min cost
            ethers.constants.MaxUint256, // max cost
            susdInvestAmount, // input amount
            testSystem.snx.quoteAsset.address, // input asset
          ],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
      };

      it("just after deposit", async () => {
        await openShortPutQuote();
        // 0.5% difference (consider option price)
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBeforeInvest,
          totalFundBeforeInvest.mul(5).div(1000),
        );
      });

      it("after huge price dump", async () => {
        await openShortPutQuote();
        const totalFundBeforePriceDump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(50).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPriceDump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPriceDump).lt(totalFundBeforePriceDump);
      });

      it("after huge price pump", async () => {
        await openShortPutQuote();
        const totalFundBeforePricePump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(110).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPricePump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPricePump).gt(totalFundBeforePricePump);
      });

      it("expect zero if putValue is more than collateralValue", async () => {
        await openShortPutQuote();
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(10).div(100),
          baseKeyRate.invalid,
        );

        expect(await poolManagerLogicProxy["assetValue(address)"](testSystem.optionMarketWrapper.address)).to.eq(0);
      });

      it("Pool has expected funds after withdraw", async () => {
        await openShortPutQuote();
        const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
        const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw half
        await utils.increaseTime(60 * 5);
        await replaceTestSystemExchanger();
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.be.closeTo(susdBalanceBefore.div(2), 1);
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBefore.div(2),
          totalFundBefore.mul(5).div(1000),
        );
      });

      it("Should fully close the option position if less than the minCollatAmount after withdraw", async () => {
        await openShortPutQuote();
        // increase min static base collateral
        const minCollatParams = await testSystem.optionGreekCache.getMinCollatParams();
        await testSystem.optionGreekCache.setMinCollateralParameters({
          ...minCollatParams,
          minStaticQuoteCollateral: units(1),
        });

        // withdraw 99% and it should fully close the option position
        await utils.increaseTime(60 * 5);
        await replaceTestSystemExchanger();
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).mul(99).div(100));

        expect(await testSystem.optionToken.balanceOf(poolLogicProxy.address)).to.equal(0);
      });

      it("Use PRICE_GWAV_DURATION putPrice for short-put quote option", async () => {
        await openShortPutQuote();
        const assetBalance = await poolManagerLogicProxy.assetBalance(testSystem.optionMarketWrapper.address);
        const position = (await testSystem.optionToken.getOwnerPositions(poolLogicProxy.address))[0];
        const nowPrices = await testSystem.GWAVOracle.optionPriceGWAV(
          position.strikeId,
          await lyraOptionMarketWrapperAssetGuard.PRICE_GWAV_DURATION(),
        );

        expect(assetBalance).to.equal(position.collateral.sub(nowPrices.putPrice.mul(position.amount).div(units(1))));
      });
    });

    describe("two positions", () => {
      const openTwoPositions = async () => {
        // deposit
        await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, susdInvestAmount.mul(2));

        totalFundBeforeInvest = await poolManagerLogicProxy.totalFundValue();

        // approve
        const approveABI = iERC20.encodeFunctionData("approve", [
          testSystem.optionMarketWrapper.address,
          susdInvestAmount.mul(2),
        ]);
        await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

        // open position
        const openPositionABI1 = iOptionMarketWrapper.encodeFunctionData("openPosition", [
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
            susdInvestAmount, // input amount
            testSystem.snx.quoteAsset.address, // input asset
          ],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI1);

        const openPositionABI2 = iOptionMarketWrapper.encodeFunctionData("openPosition", [
          [
            testSystem.optionMarket.address,
            1, // strike Id
            0, // position Id
            1, // iteration
            0, // set collateral to
            0, // current collateral
            1, // optionType - long put
            units(1), // amount
            0, // min cost
            ethers.constants.MaxUint256, // max cost
            susdInvestAmount, // input amount
            testSystem.snx.quoteAsset.address, // input asset
          ],
        ]);
        await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI2);
      };

      it("just after deposit", async () => {
        await openTwoPositions();
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBeforeInvest,
          totalFundBeforeInvest.mul(5).div(1000),
        );
      });

      it("after huge price dump", async () => {
        await openTwoPositions();
        const totalFundBeforePriceDump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(50).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPriceDump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPriceDump).gt(totalFundBeforePriceDump);
      });

      it("after huge price pump", async () => {
        await openTwoPositions();
        const totalFundBeforePricePump = await poolManagerLogicProxy.totalFundValue();

        const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
        await testSystem.optionGreekCache.setGreekCacheParameters({
          ...geekCacheParams,
          acceptableSpotPricePercentMove: units(1), // 100%
        });
        const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
        await testSystem.snx.exchangeRates.setRateAndInvalid(
          baseKey,
          baseKeyRate.rate.mul(150).div(100),
          baseKeyRate.invalid,
        );
        const totalFundAfterPricePump = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundAfterPricePump).gt(totalFundBeforePricePump);
      });

      it("Pool has expected funds after withdraw", async () => {
        await openTwoPositions();
        const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
        const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

        // withdraw half
        await utils.increaseTime(60 * 5);
        await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

        expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.be.closeTo(susdBalanceBefore.div(2), 1);
        // 0.5% difference
        expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
          totalFundBefore.div(2),
          totalFundBefore.mul(5).div(1000),
        );
      });
    });
  });

  describe("withdrawProcessing", () => {
    const openLongCall = async () => {
      // deposit
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, susdInvestAmount);

      // approve
      const approveABI = iERC20.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        susdInvestAmount,
      ]);
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
          susdInvestAmount, // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
    };

    it("Pool has expected funds after withdraw", async () => {
      await openLongCall();
      const susdBalanceBefore = await susdProxy.balanceOf(poolLogicProxy.address);
      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

      // withdraw half
      await utils.increaseTime(60 * 5);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      expect(await susdProxy.balanceOf(poolLogicProxy.address)).to.be.closeTo(susdBalanceBefore.div(2), 1);
      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore.div(2),
        totalFundBefore.mul(5).div(1000),
      );
    });

    it("Withdrawer receives their portion of the option position", async () => {
      await openLongCall();
      const susdBalanceBefore = await susdProxy.balanceOf(logicOwner.address);

      // withdraw half
      await utils.increaseTime(60 * 5);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      expect(await susdProxy.balanceOf(logicOwner.address)).to.be.gt(susdBalanceBefore);
    });

    it("Withdraw after price pump", async () => {
      await openLongCall();
      const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
      await testSystem.optionGreekCache.setGreekCacheParameters({
        ...geekCacheParams,
        acceptableSpotPricePercentMove: units(1), // 100%
      });
      const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
      await testSystem.snx.exchangeRates.setRateAndInvalid(
        baseKey,
        baseKeyRate.rate.mul(150).div(100),
        baseKeyRate.invalid,
      );

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

      await utils.increaseTime(60 * 5);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore.div(2),
        totalFundBefore.mul(5).div(1000),
      );
    });

    it("Withdraw after price dump", async () => {
      await openLongCall();
      const geekCacheParams = await testSystem.optionGreekCache.getGreekCacheParams();
      await testSystem.optionGreekCache.setGreekCacheParameters({
        ...geekCacheParams,
        acceptableSpotPricePercentMove: units(1), // 100%
      });
      const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
      await testSystem.snx.exchangeRates.setRateAndInvalid(
        baseKey,
        baseKeyRate.rate.mul(50).div(100),
        baseKeyRate.invalid,
      );

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

      await utils.increaseTime(60 * 5);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore.div(2),
        totalFundBefore.mul(5).div(1000),
      );
    });

    it("Withdraw after position expired", async () => {
      await openLongCall();
      const baseKeyRate = await testSystem.snx.exchangeRates.rateAndInvalid(baseKey);
      await testSystem.snx.exchangeRates.setRateAndInvalid(
        baseKey,
        baseKeyRate.rate.mul(200).div(100),
        baseKeyRate.invalid,
      );

      await utils.increaseTime(60 * 5);

      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore.div(2),
        totalFundBefore.mul(5).div(1000),
      );
    });
  });

  describe("after board expiry", () => {
    const openLongCall = async () => {
      // deposit
      await poolLogicProxy.deposit(testSystem.snx.quoteAsset.address, susdInvestAmount.mul(2));

      // approve
      const approveABI = iERC20.encodeFunctionData("approve", [
        testSystem.optionMarketWrapper.address,
        susdInvestAmount.mul(2),
      ]);
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
          susdInvestAmount, // input amount
          testSystem.snx.quoteAsset.address, // input asset
        ],
      ]);

      // open two positions
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);
      await poolLogicProxy.connect(manager).execTransaction(testSystem.optionMarketWrapper.address, openPositionABI);

      // make board expired
      const [, board] = await testSystem.optionMarket.getStrikeAndBoard(1);
      await ethers.provider.send("evm_increaseTime", [board.expiry.toNumber() - (await currentBlockTimestamp()) - 60]);
      await ethers.provider.send("evm_mine", []);
      await testSystem.optionGreekCache.updateBoardCachedGreeks(board.id);
      await ethers.provider.send("evm_increaseTime", [120]);
      await ethers.provider.send("evm_mine", []);
      await testSystem.optionMarket.settleExpiredBoard(board.id);
    };

    it("try withdraw after expiry", async () => {
      await openLongCall();
      const totalFundBefore = await poolManagerLogicProxy.totalFundValue();

      await utils.increaseTime(60 * 5);
      await poolLogicProxy.withdraw((await poolLogicProxy.balanceOf(logicOwner.address)).div(2));

      // 0.5% difference
      expect(await poolManagerLogicProxy.totalFundValue()).to.closeTo(
        totalFundBefore.div(2),
        totalFundBefore.mul(5).div(1000),
      );

      const lyraOptionMarketWrapperContractGuard = await ethers.getContractAt(
        "LyraOptionMarketWrapperContractGuard",
        await poolFactory.getContractGuard(testSystem.optionMarketWrapper.address),
      );
      expect((await lyraOptionMarketWrapperContractGuard.getOptionPositions(poolLogicProxy.address)).length).to.equal(
        0,
      );
    });
  });

  it.skip("test direct interaction with wrapper", async () => {
    await testSystem.snx.baseAsset.approve(testSystem.optionMarketWrapper.address, units(10));
    await testSystem.optionMarketWrapper.openPosition({
      optionMarket: testSystem.optionMarket.address,
      strikeId: 1, // strike Id
      positionId: 0, // position Id
      iterations: 1, // iteration
      setCollateralTo: units(1), // set collateral to
      currentCollateral: 0, // current collateral
      optionType: 2, // optionType - long call
      amount: units(1), // amount
      minCost: 0, // min cost
      maxCost: ethers.constants.MaxUint256, // max cost
      inputAmount: 0, // input amount
      inputAsset: testSystem.snx.quoteAsset.address, // input asset
    });

    const position = (await testSystem.optionToken.getOwnerPositions(logicOwner.address))[0];

    await testSystem.optionToken.approve(testSystem.optionMarketWrapper.address, position.positionId);
    await testSystem.snx.quoteAsset.approve(testSystem.optionMarketWrapper.address, units(5000));
    await testSystem.optionMarketWrapper.forceClosePosition({
      optionMarket: testSystem.optionMarket.address,
      strikeId: 1, // strike Id
      positionId: position.positionId, // position Id
      iterations: 1, // iteration
      setCollateralTo: position.collateral.div(2), // set collateral to
      currentCollateral: position.collateral, // current collateral
      optionType: 2, // optionType - long call
      amount: position.amount.div(2), // amount
      minCost: 0, // min cost
      maxCost: ethers.constants.MaxUint256, // max cost
      inputAmount: units(5000), // input amount
      inputAsset: testSystem.snx.quoteAsset.address, // input asset
    });
  });
});
