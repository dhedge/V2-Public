import { IOptionMarket, IOptionToken } from "@lyrafinance/protocol/dist/typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { ovmChainData } from "../../../../config/chainData/ovm-data";
import { Address } from "../../../../deployment-scripts/types";
import {
  IERC20Extended,
  IERC20__factory,
  ILyraQuoter,
  IOptionMarketWrapper__factory,
  LyraOptionMarketWrapperAssetGuard,
  PoolFactory,
  PoolLogic,
} from "../../../../types";
import { units } from "../../../TestHelpers";
import { createFund } from "../../utils/createFund";
import { deployContracts } from "../../utils/deployContracts/deployContracts";
import { getAccountToken } from "../../utils/getAccountTokens/index";
import { utils } from "../../utils/utils";
import { deployLyraAndConfigureMarket } from "./LyraTestHelpers";

const ITERATIONS = 10;
const susdInvestAmount = units(100);

describe("LyraOptionMarketWrapperAssetGuard Real Test", function () {
  const iOptionMarketWrapper = new ethers.utils.Interface(IOptionMarketWrapper__factory.abi);
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);

  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic;
  let susdProxy: IERC20Extended;

  let lyraQuoter: ILyraQuoter;
  let optionMarket: IOptionMarket;
  let optionToken: IOptionToken;

  let quoteAsset: Address;
  let baseAssetAgg: Address;

  let lyraOptionMarketWrapperAssetGuard: LyraOptionMarketWrapperAssetGuard;

  before(async function () {
    lyraQuoter = await ethers.getContractAt("ILyraQuoter", ovmChainData.lyra.quoter);
    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("ovm");
    const results = await deployLyraAndConfigureMarket(deployments, ovmChainData.lyra);

    lyraOptionMarketWrapperAssetGuard = results.lyraOptionMarketWrapperAssetGuard;

    const { baseAsset } = results;
    ({ optionMarket, optionToken, quoteAsset, baseAssetAgg } = results);
    poolFactory = deployments.poolFactory;

    await poolFactory.setExitCooldown(0);

    const fund = await createFund(
      poolFactory,
      logicOwner,
      manager,
      [
        { asset: quoteAsset, isDeposit: true },
        { asset: baseAsset, isDeposit: true },
        { asset: ovmChainData.lyra.optionMarketWrapper, isDeposit: false },
        { asset: ovmChainData.assets.snxProxy, isDeposit: false },
      ],
      {
        performance: ethers.BigNumber.from("0"),
        management: ethers.BigNumber.from("0"),
      },
    );
    poolLogicProxy = fund.poolLogicProxy;

    susdProxy = await ethers.getContractAt("IERC20Extended", ovmChainData.assets.susd);
    await getAccountToken(
      susdInvestAmount,
      logicOwner.address,
      ovmChainData.synthetix.sUSDProxy_target_tokenState,
      ovmChainData.assetsBalanceOfSlot.susd,
    );
    await susdProxy.approve(poolLogicProxy.address, susdInvestAmount);

    await poolLogicProxy.deposit(susdProxy.address, susdInvestAmount);
  });

  describe("TestCases", () => {
    before(async () => {
      // These are not ordered by date :(
      const boardIds = await optionMarket.getLiveBoards();
      // Fetch all the boards so we can get the expiries
      const boards = await Promise.all(
        boardIds.map((boardId) => {
          return optionMarket.getOptionBoard(boardId);
        }),
      );
      // Sort by expiry ascending (earliest to latest)

      const baseAssetAggregator = await ethers.getContractAt("AggregatorV3Interface", baseAssetAgg);
      const { answer } = await baseAssetAggregator.latestRoundData();
      const baseAssetPrice18 = answer.mul(10 ** 10);
      const above = baseAssetPrice18.div(100).mul(120);
      const below = baseAssetPrice18.div(100).mul(80);

      const orderedBoards = boards.sort((a, b) => a.expiry.sub(b.expiry).toNumber());
      const testCases: { expiry: Date; strikeId: BigNumber; strikePrice: BigNumber }[] = [];
      const lastBoard = orderedBoards[orderedBoards.length - 1];
      for (const board of [lastBoard]) {
        const expiry = new Date(board.expiry.mul(1000).toNumber());
        const strikes: { strikeId: BigNumber; strikePrice: BigNumber }[] = [];
        for (const strikeId of board.strikeIds) {
          const strike = await optionMarket.getStrike(strikeId);

          if (strike.strikePrice.lt(above) && strike.strikePrice.gt(below)) {
            strikes.push({
              strikeId,
              strikePrice: strike.strikePrice,
            });
          }
        }
        strikes.sort((a, b) =>
          a.strikePrice
            .div(units(1))
            .sub(b.strikePrice.div(units(1)))
            .toNumber(),
        );
        strikes.forEach((s) => testCases.push({ ...s, expiry }));
      }

      describe("TestCases", () => {
        utils.beforeAfterReset(beforeEach, afterEach);
        testCases.forEach(createTest);
      });
    });
    it("Dummy test case, so before is executed", () => expect(1).to.eq(1));
  });

  // This function recursively calls the quoter with an amount to buy
  // it finds an amount that will, according to the quoter, exhaust 99% of the investment amount
  const searchForAmount = async (
    amountToTest: BigNumber | undefined,
    min: BigNumber,
    max: BigNumber,
    strikeId: BigNumber,
  ): Promise<{ amountToBuy: BigNumber; totalPremium: BigNumber; totalFee: BigNumber }> => {
    const onePercent = susdInvestAmount.div(100);
    const ninetyNinePercent = susdInvestAmount.sub(onePercent);
    const { totalPremium, totalFee } = await lyraQuoter.quote(
      optionMarket.address,
      strikeId,
      ITERATIONS,
      0,
      amountToTest || units(1),
      0,
      false,
    );

    if (amountToTest == undefined) {
      // Cheap way to find a starting point
      return await searchForAmount(
        ninetyNinePercent.mul(units(1)).div(totalPremium),
        BigNumber.from(0),
        ninetyNinePercent.mul(units(1)).div(totalPremium).mul(2),
        strikeId,
      );
    }

    if (totalPremium.gt(ninetyNinePercent)) {
      return await searchForAmount(min.add(amountToTest).div(2), min, amountToTest, strikeId);
    }

    if (totalPremium.add(onePercent).gt(ninetyNinePercent)) {
      return { amountToBuy: amountToTest, totalPremium, totalFee };
    } else {
      return await searchForAmount(amountToTest.add(max).div(2), amountToTest, max, strikeId);
    }
  };

  const openLongCalls = async (strikeId: BigNumber) => {
    // approve
    const approveABI = iERC20.encodeFunctionData("approve", [ovmChainData.lyra.optionMarketWrapper, susdInvestAmount]);

    await poolLogicProxy.connect(manager).execTransaction(susdProxy.address, approveABI);

    const { amountToBuy, totalPremium, totalFee } = await searchForAmount(
      undefined,
      BigNumber.from(0),
      BigNumber.from(0),
      strikeId,
    );

    expect(totalPremium.lt(susdInvestAmount)).to.be.true;
    // Assert we're about to buy close to susdInvestAmount of options
    expect(totalPremium).to.be.closeTo(susdInvestAmount, susdInvestAmount.div(50));

    // open position
    const openPositionABI = iOptionMarketWrapper.encodeFunctionData("openPosition", [
      [
        optionMarket.address,
        strikeId, // strike Id
        0, // position Id
        ITERATIONS, // iteration
        0, // set collateral to
        0, // current collateral
        0, // optionType - long call
        amountToBuy, // amount
        0, // min cost
        ethers.constants.MaxUint256, // max cost
        susdInvestAmount, // input amount
        quoteAsset, // input asset
      ],
    ]);

    await poolLogicProxy.connect(manager).execTransaction(ovmChainData.lyra.optionMarketWrapper, openPositionABI);
    return totalFee;
  };

  const closePosition = async () => {
    const positions = await optionToken.getOwnerPositions(poolLogicProxy.address);
    expect(positions.length).to.equal(1);
    const position = positions[0];

    const poolImpersonated = await utils.impersonateAccount(poolLogicProxy.address);
    await optionToken.connect(poolImpersonated).setApprovalForAll(ovmChainData.lyra.optionMarketWrapper, true);
    const closePositionABI = iOptionMarketWrapper.encodeFunctionData("closePosition", [
      [
        optionMarket.address,
        position.strikeId, // strike Id
        position.positionId, // position Id
        ITERATIONS, // iteration
        0, // set collateral to
        0, // current collateral
        0, // optionType - long call
        position.amount, // amount
        0, // min cost
        ethers.constants.MaxUint256, // max cost
        0, // input amount
        quoteAsset, // input asset
      ],
    ]);
    await poolLogicProxy.connect(manager).execTransaction(ovmChainData.lyra.optionMarketWrapper, closePositionABI);
  };

  const getPositionValueFromQuoter = async () => {
    const positions = await optionToken.getOwnerPositions(poolLogicProxy.address);
    expect(positions.length).to.equal(1);
    const position = positions[0];

    const { totalFee, totalPremium } = await lyraQuoter.quote(
      optionMarket.address,
      position.strikeId,
      ITERATIONS,
      position.optionType,
      position.amount,
      1,
      false,
    );
    return { closeFee: totalFee, value: totalPremium };
  };

  const createTest = (testCase: { expiry: Date; strikeId: BigNumber; strikePrice: BigNumber }) => {
    it(
      testCase.strikeId +
        " Expiry: " +
        testCase.expiry.toDateString() +
        " Strike:" +
        ethers.utils.formatEther(testCase.strikePrice),
      async function () {
        console.log("boardExpiry", testCase.expiry);
        console.log("StrikePrice", testCase.strikePrice);

        const totalSUSDBefore = await susdProxy.balanceOf(poolLogicProxy.address);
        console.log("totalSUSDInPool ", totalSUSDBefore);
        expect(totalSUSDBefore).to.eq(susdInvestAmount);
        console.log("Opening calls");

        let openFee;
        try {
          openFee = await openLongCalls(testCase.strikeId);
        } catch (e) {
          // Not all strikes can be bought for, mostly because of delta cutoffs and time to expiry
          // But also there are min/max skew and iv bounds
          console.log("Cannot open position for strike", testCase.strikeId);
          this.skip();
        }

        console.log("Quoter openFee  ", openFee);
        const susdLeftInPool = await susdProxy.balanceOf(poolLogicProxy.address);
        console.log("susdLeftInPool  ", susdLeftInPool);
        console.log("spent On Options", susdInvestAmount.sub(susdLeftInPool));

        // This is our value of the Option we don't include the closeFee
        const dhedgeValue = await lyraOptionMarketWrapperAssetGuard.getBalance(
          poolLogicProxy.address,
          ovmChainData.lyra.optionMarketWrapper,
        );

        // The quoter subtracts the fee from the value when selling
        const { closeFee, value } = await getPositionValueFromQuoter();
        console.log("gwav10Min   Value", dhedgeValue);
        console.log("quoter total val", value.add(closeFee));
        console.log("quoter val exfee", value);
        console.log("quoter sell fee ", closeFee);

        await closePosition();

        const totalSUSDAfterClose = await susdProxy.balanceOf(poolLogicProxy.address);
        console.log("closedSusdValue ", totalSUSDAfterClose.sub(susdLeftInPool));
        console.log("totalSUSDAfterCl", totalSUSDAfterClose);

        // Assert we spent at least 95% of the susd on options
        expect(susdLeftInPool.lt(susdInvestAmount.div(100).mul(5))).to.be.true;

        // Make sure were getting at least 80% back
        expect(totalSUSDAfterClose.gt(susdInvestAmount.div(10).mul(8))).to.be.true;
      },
    );
  };
});
