import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract } from "ethers";
import { artifacts, ethers } from "hardhat";
import { assets, assetsBalanceOfSlot, price_feeds } from "../../../config/chainData/polygon-data";
import { IERC20, MockContract, PoolFactory } from "../../../types";
import { checkAlmostSame, currentBlockTimestamp, units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { getAccountToken } from "../utils/getAccountTokens";

describe("ManagerFee Test", function () {
  let USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress;
  let poolFactory: PoolFactory, poolManagerLogic: Contract, poolLogicProxy: Contract, poolManagerLogicProxy: Contract;
  let usdc_price_feed: MockContract;
  let latestRoundDataABI: string;

  before(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();

    const MockContract = await ethers.getContractFactory("MockContract");
    usdc_price_feed = await MockContract.deploy();

    const AggregatorV3 = await artifacts.readArtifact("AggregatorV3Interface");
    const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
    latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);
    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 100000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1

    const assetUsdc = { asset: assets.usdc, assetType: 0, aggregator: usdc_price_feed.address };

    const deployments = await deployPolygonContracts();
    USDC = deployments.assets.USDC;
    deployments.assetHandler.addAssets([assetUsdc]);
    poolFactory = deployments.poolFactory;
    poolManagerLogic = deployments.poolManagerLogic;
  });

  beforeEach(async () => {
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
    poolManagerLogicProxy = await poolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());
    await getAccountToken(units(5000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
    await getAccountToken(units(5000, 6), logicOwner.address, assets.wmatic, assetsBalanceOfSlot.wmatic);
  });

  it("should be able to deposit", async function () {
    const supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    console.log("supportedAssets: ", supportedAssets);

    const chainlinkEth = await ethers.getContractAt("AggregatorV3Interface", price_feeds.eth);
    const ethPrice = await chainlinkEth.latestRoundData();
    console.log("eth price: ", ethPrice[1].toString());
    console.log("updatedAt: ", ethPrice[3].toString());

    const chainlinkUsdc = await ethers.getContractAt("AggregatorV3Interface", price_feeds.usdc);
    const usdcPrice = await chainlinkUsdc.latestRoundData();
    console.log("usdc price: ", usdcPrice[1].toString());
    console.log("updatedAt: ", usdcPrice[3].toString());

    const assetBalance = await poolManagerLogicProxy.assetBalance(assets.usdc);
    console.log("assetBalance: ", assetBalance.toString());

    const assetValue = await poolManagerLogicProxy["assetValue(address)"](assets.usdc);
    console.log("assetValue: ", assetValue.toString());

    let totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(assets.wmatic, (200e6).toString())).to.be.revertedWith("invalid deposit asset");

    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());

    totalFundValue = await poolManagerLogicProxy.totalFundValue();
    checkAlmostSame(totalFundValue, units(200));
  });

  it("should mint manager fee after 1 day", async () => {
    // deposit 200 USDC
    await USDC.approve(poolLogicProxy.address, (200e6).toString());
    await poolLogicProxy.deposit(assets.usdc, (200e6).toString());

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
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    const streamingFeeNumerator = await poolManagerLogicProxy.streamingFeeNumerator();
    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(streamingFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    const calculatedAvailableFee = tokenPricePreMint
      .sub(tokenPriceAtLastFeeMint)
      .mul(totalSupplyPreMint)
      .mul(managerFeeNumerator)
      .div(10000)
      .div(tokenPricePreMint)
      .add(streamingFee);
    expect(streamingFee).lt(calculatedAvailableFee);
    expect(availableFeePreMint).to.be.gt("0");
    checkAlmostSame(availableFeePreMint, calculatedAvailableFee);

    await poolLogicProxy.mintManagerFee();

    const tokenPricePostMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPostMint = await poolLogicProxy.totalSupply();

    checkAlmostSame(totalSupplyPostMint, totalSupplyPreMint.add(availableFeePreMint));
    checkAlmostSame(tokenPricePostMint, tokenPricePreMint.mul(totalSupplyPreMint).div(totalSupplyPostMint));

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
    );

    const availableFeePostMint = await poolLogicProxy.availableManagerFee();
    expect(availableFeePostMint).to.be.eq("0");
  });

  it("only streaming fee fee after 1 block", async () => {
    const daoFees = await poolFactory.getDaoFee();

    await usdc_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ["uint256", "int256", "uint256", "uint256", "uint256"],
        [0, 115000000, 0, await currentBlockTimestamp(), 0],
      ),
    ); // $1.15

    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = await poolLogicProxy.balanceOf(dao.address);
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const streamingFeeNumerator = await poolManagerLogicProxy.streamingFeeNumerator();

    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(streamingFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    checkAlmostSame(availableFeePreMint, streamingFee);

    await poolLogicProxy.mintManagerFee();

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
    );
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
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    const streamingFeeNumerator = await poolManagerLogicProxy.streamingFeeNumerator();
    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(streamingFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    const calculatedAvailableFee = tokenPricePreMint
      .sub(tokenPriceAtLastFeeMint)
      .mul(totalSupplyPreMint)
      .mul(managerFeeNumerator)
      .div(10000)
      .div(tokenPricePreMint)
      .add(streamingFee);

    expect(streamingFee).lt(calculatedAvailableFee);
    expect(availableFeePreMint).to.be.gt("0");
    checkAlmostSame(availableFeePreMint, calculatedAvailableFee);

    await poolLogicProxy.mintManagerFee();

    const tokenPricePostMint = await poolLogicProxy.tokenPrice();
    const totalSupplyPostMint = await poolLogicProxy.totalSupply();

    checkAlmostSame(totalSupplyPostMint, totalSupplyPreMint.add(availableFeePreMint));
    checkAlmostSame(tokenPricePostMint, tokenPricePreMint.mul(totalSupplyPreMint).div(totalSupplyPostMint));

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
    );

    const availableFeePostMint = await poolLogicProxy.availableManagerFee();
    expect(availableFeePostMint).to.be.eq("0");
  });
});
