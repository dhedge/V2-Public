import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { artifacts, ethers } from "hardhat";

import { IERC20, MockContract, PoolFactory, PoolManagerLogic, PoolLogic } from "../../../types";
import { checkAlmostSame, currentBlockTimestamp, units } from "../../testHelpers";
import { createFund } from "../utils/createFund";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { getAccountToken } from "../utils/getAccountTokens";

import { polygonChainData } from "../../../config/chainData/polygonData";
import { utils } from "../utils/utils";
const { assets, assetsBalanceOfSlot } = polygonChainData;

describe("ManagerFee Test", function () {
  let USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress;
  let poolFactory: PoolFactory,
    poolManagerLogic: PoolManagerLogic,
    poolLogicProxy: PoolLogic,
    poolManagerLogicProxy: PoolManagerLogic;
  let usdc_price_feed: MockContract;
  let latestRoundDataABI: string;

  let snapId: string;
  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });
  before(async () => {
    snapId = await utils.evmTakeSnap();

    [logicOwner, manager, dao] = await ethers.getSigners();

    const MockContract = await ethers.getContractFactory("MockContract");
    usdc_price_feed = await MockContract.deploy();

    const AggregatorV3 = await artifacts.readArtifact("AggregatorV3Interface");
    const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
    latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);

    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: usdc_price_feed.address };

    const deployments = await deployContracts("polygon");
    USDC = deployments.assets.USDC;
    deployments.assetHandler.addAssets([assetUsdc]);
    poolFactory = deployments.poolFactory;
    poolManagerLogic = deployments.poolManagerLogic;
  });

  beforeEach(async () => {
    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 100000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1

    const funds = await createFund(
      poolFactory,
      logicOwner,
      manager,
      [
        { asset: assets.usdc, isDeposit: true },
        { asset: assets.usdt, isDeposit: true },
      ],
      { performance: ethers.BigNumber.from("5000"), management: ethers.BigNumber.from("200") },
    );
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = poolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());
    await getAccountToken(units(5000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await getAccountToken(units(5000, 6), logicOwner.address, assets.wmatic, assetsBalanceOfSlot.wmatic);

    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());
  });

  it("only manager fee after 1 block", async () => {
    // manager fee is set 50%
    // update price from $1 to $1.1
    // should mint 50% of profit

    const daoFees = await poolFactory.getDaoFee();

    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 110000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.1

    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = await poolLogicProxy.balanceOf(dao.address);
    const tokenPriceAtLastFeeMint = await poolLogicProxy.tokenPriceAtLastFeeMint();
    const availableFeePreMint = await poolLogicProxy.calculateAvailableManagerFee(
      await poolManagerLogicProxy.totalFundValue(),
    );
    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const totalFundValue = await poolManagerLogicProxy.callStatic.totalFundValueMutable();
    const performanceFeeNumerator = await poolManagerLogicProxy.performanceFeeNumerator();
    const feeDollarAmount = tokenPricePreMint
      .sub(tokenPriceAtLastFeeMint)
      .mul(totalSupplyPreMint)
      .mul(performanceFeeNumerator)
      .div(ethers.BigNumber.from(10000).mul(ethers.BigNumber.from(10).pow(18)));
    const calculatedAvailableFee = feeDollarAmount.mul(totalSupplyPreMint).div(totalFundValue.sub(feeDollarAmount));

    checkAlmostSame(availableFeePreMint, calculatedAvailableFee, 0.001);

    await poolLogicProxy.mintManagerFee();

    const tokenPricePostMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPostMint = await poolLogicProxy.totalSupply();

    checkAlmostSame(totalSupplyPostMint, totalSupplyPreMint.add(availableFeePreMint), 0.001);
    checkAlmostSame(tokenPricePostMint, tokenPricePreMint.mul(totalSupplyPreMint).div(totalSupplyPostMint), 0.001);
    expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.eq(tokenPricePreMint);

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
      0.001,
    );

    const availableFeePostMint = await poolLogicProxy.calculateAvailableManagerFee(
      await poolManagerLogicProxy.totalFundValue(),
    );
    expect(availableFeePostMint).to.be.eq("0");
  });

  it("manager fee can only be high watermark", async () => {
    // manager fee is set 50%
    // update price from $1 to $1.1
    // should mint 50% of profit
    const tokenPriceAtLastFeeMintBeforeIncrease = await poolLogicProxy.tokenPriceAtLastFeeMint();
    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 110000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.1

    await ethers.provider.send("evm_mine", []);
    expect(await poolLogicProxy.calculateAvailableManagerFee(await poolManagerLogicProxy.totalFundValue())).to.be.gt(0);

    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();

    // MINT FEE
    await poolLogicProxy.mintManagerFee();
    const tokenPriceAtLastFeeMintAfterIncrease = await poolLogicProxy.tokenPriceAtLastFeeMint();
    expect(tokenPriceAtLastFeeMintBeforeIncrease.lt(tokenPriceAtLastFeeMintAfterIncrease));
    expect(await poolLogicProxy.calculateAvailableManagerFee(await poolManagerLogicProxy.totalFundValue())).to.equal(0);
    expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.eq(tokenPricePreMint);

    // DROP PRICE
    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 110000000 / 2, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.1 / 2

    // only streaming fee available
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(managerFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    expect(await poolLogicProxy.calculateAvailableManagerFee(await poolManagerLogicProxy.totalFundValue())).to.eq(
      streamingFee,
    );

    await poolLogicProxy.mintManagerFee();

    // Should not be decreased
    expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.eq(tokenPriceAtLastFeeMintAfterIncrease);
  });

  it("only streaming fee after 6 months", async () => {
    // streaming fee is set 2% year
    // should mint 1% of total pool tokens after 6 months
    const daoFees = await poolFactory.getDaoFee();

    await ethers.provider.send("evm_increaseTime", [(3600 * 24 * 365) / 2]);
    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = await poolLogicProxy.balanceOf(dao.address);
    const availableFeePreMint = await poolLogicProxy.calculateAvailableManagerFee(
      await poolManagerLogicProxy.totalFundValue(),
    );
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();

    const streamingFee = totalSupplyPreMint.div(100);
    checkAlmostSame(availableFeePreMint, streamingFee, 0.001);

    await poolLogicProxy.mintManagerFee();

    expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.eq(tokenPricePreMint);
    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
      0.001,
    );
  });

  it("should mint both manager/streaming fee", async () => {
    const daoFees = await poolFactory.getDaoFee();

    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 110000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.1

    await ethers.provider.send("evm_increaseTime", [3600 * 24]);
    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = await poolLogicProxy.balanceOf(dao.address);
    const tokenPriceAtLastFeeMint = await poolLogicProxy.tokenPriceAtLastFeeMint();
    const availableFeePreMint = await poolLogicProxy.calculateAvailableManagerFee(
      await poolManagerLogicProxy.totalFundValue(),
    );
    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const performanceFeeNumerator = await poolManagerLogicProxy.performanceFeeNumerator();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(managerFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    const totalFundValue = await poolManagerLogicProxy.callStatic.totalFundValueMutable();
    const feeDollarAmount = tokenPricePreMint
      .sub(tokenPriceAtLastFeeMint)
      .mul(totalSupplyPreMint)
      .mul(performanceFeeNumerator)
      .div(ethers.BigNumber.from(10000).mul(ethers.BigNumber.from(10).pow(18)));
    const calculatedAvailablePerformanceFee = feeDollarAmount
      .mul(totalSupplyPreMint)
      .div(totalFundValue.sub(feeDollarAmount));
    const calculatedAvailableFee = calculatedAvailablePerformanceFee.add(streamingFee);

    expect(streamingFee).lt(calculatedAvailableFee);
    expect(availableFeePreMint).to.be.gt("0");
    checkAlmostSame(availableFeePreMint, calculatedAvailableFee, 0.001);

    await poolLogicProxy.mintManagerFee();

    const tokenPricePostMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPostMint = await poolLogicProxy.totalSupply();

    checkAlmostSame(totalSupplyPostMint, totalSupplyPreMint.add(availableFeePreMint), 0.001);
    checkAlmostSame(tokenPricePostMint, tokenPricePreMint.mul(totalSupplyPreMint).div(totalSupplyPostMint), 0.001);
    expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.eq(tokenPricePreMint);

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
      0.001,
    );

    const availableFeePostMint = await poolLogicProxy.calculateAvailableManagerFee(
      await poolManagerLogicProxy.totalFundValue(),
    );
    expect(availableFeePostMint).to.be.eq("0");
  });

  it("should mint manager fee after large deposit (1 year after)", async () => {
    const daoFees = await poolFactory.getDaoFee();

    // deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());

    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 110000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.1

    // deposit 2000 USDC
    await USDC.approve(poolLogicProxy.address, (2000e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (2000e6).toString());

    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 120000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.2

    await ethers.provider.send("evm_increaseTime", [3600 * 24 * 365]);
    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = await poolLogicProxy.balanceOf(dao.address);
    const tokenPriceAtLastFeeMint = await poolLogicProxy.tokenPriceAtLastFeeMint();
    const availableFeePreMint = await poolLogicProxy.calculateAvailableManagerFee(
      await poolManagerLogicProxy.totalFundValue(),
    );
    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const totalFundValue = await poolManagerLogicProxy.callStatic.totalFundValueMutable();
    const performanceFeeNumerator = await poolManagerLogicProxy.performanceFeeNumerator();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(managerFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    const feeDollarAmount = tokenPricePreMint
      .sub(tokenPriceAtLastFeeMint)
      .mul(totalSupplyPreMint)
      .mul(performanceFeeNumerator)
      .div(ethers.BigNumber.from(10000).mul(ethers.BigNumber.from(10).pow(18)));
    const calculatedAvailablePerformanceFee = feeDollarAmount
      .mul(totalSupplyPreMint)
      .div(totalFundValue.sub(feeDollarAmount));
    const calculatedAvailableFee = calculatedAvailablePerformanceFee.add(streamingFee);

    expect(streamingFee).lt(calculatedAvailableFee);
    expect(availableFeePreMint).to.be.gt("0");
    checkAlmostSame(availableFeePreMint, calculatedAvailableFee, 0.001);

    await poolLogicProxy.mintManagerFee();

    const tokenPricePostMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPostMint = await poolLogicProxy.totalSupply();

    checkAlmostSame(totalSupplyPostMint, totalSupplyPreMint.add(availableFeePreMint), 0.001);
    checkAlmostSame(tokenPricePostMint, tokenPricePreMint.mul(totalSupplyPreMint).div(totalSupplyPostMint), 0.001);
    expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.eq(tokenPricePreMint);

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
      0.001,
    );

    const availableFeePostMint = await poolLogicProxy.calculateAvailableManagerFee(
      await poolManagerLogicProxy.totalFundValue(),
    );
    expect(availableFeePostMint).to.be.eq("0");
  });

  it("should mint manager fee at commitFeeIncrease", async () => {
    await poolFactory.setMaximumFee(6000, 300, 0, 0);
    await poolFactory.setPerformanceFeeNumeratorChangeDelay(3600 * 24); // fee increase delay for 1 day

    // 1. increase price
    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 120000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.2

    let tokenPriceBefore = await poolLogicProxy.tokenPriceWithoutManagerFee();

    // 2. increase fee
    await poolManagerLogicProxy.connect(manager).announceFeeIncrease(5500, 250, 0, 0);
    await ethers.provider.send("evm_increaseTime", [3600 * 24]);
    await ethers.provider.send("evm_mine", []);
    await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

    // 3. check tokenPrice & lastFeeMintTime
    expect(await poolLogicProxy.lastFeeMintTime()).to.eq(await currentBlockTimestamp());
    expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.eq(tokenPriceBefore);

    // 4. decrease price
    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 100000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1

    tokenPriceBefore = await poolLogicProxy.tokenPriceWithoutManagerFee();
    const tokenPriceAtLastFeeMintBefore = await poolLogicProxy.tokenPriceAtLastFeeMint();

    // 5. increase fee
    await poolManagerLogicProxy.connect(manager).announceFeeIncrease(6000, 300, 0, 0);
    await ethers.provider.send("evm_increaseTime", [3600 * 24]);
    await ethers.provider.send("evm_mine", []);
    await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

    // 6. check tokenPrice & lastFeeMintTime
    expect(await poolLogicProxy.lastFeeMintTime()).to.eq(await currentBlockTimestamp());
    expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.not.eq(tokenPriceBefore);
    expect(await poolLogicProxy.tokenPriceAtLastFeeMint()).to.eq(tokenPriceAtLastFeeMintBefore);
  });

  it("should initialize announcedFeeNumerators after commitFeeIncrease", async () => {
    await poolFactory.setMaximumFee(6000, 300, 100, 100);
    await poolFactory.setPerformanceFeeNumeratorChangeDelay(3600 * 24); // fee increase delay for 1 day

    await poolManagerLogicProxy.connect(manager).announceFeeIncrease(5500, 250, 100, 100);
    await ethers.provider.send("evm_increaseTime", [3600 * 24]);
    await ethers.provider.send("evm_mine", []);
    await poolManagerLogicProxy.connect(manager).commitFeeIncrease();

    expect(await poolManagerLogicProxy.announcedPerformanceFeeNumerator()).to.equal(0);
    expect(await poolManagerLogicProxy.announcedManagerFeeNumerator()).to.equal(0);
    expect(await poolManagerLogicProxy.announcedEntryFeeNumerator()).to.equal(0);
    expect(await poolManagerLogicProxy.announcedExitFeeNumerator()).to.equal(0);
    expect(await poolManagerLogicProxy.announcedFeeIncreaseTimestamp()).to.equal(0);
  });
});
