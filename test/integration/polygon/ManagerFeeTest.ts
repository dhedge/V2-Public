import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract } from "ethers";
import { artifacts, ethers } from "hardhat";
import { assets, assetsBalanceOfSlot } from "../../../config/chainData/polygon-data";
import { IERC20, MockContract, PoolFactory } from "../../../types";
import { checkAlmostSame, currentBlockTimestamp, units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { deployContracts } from "../utils/deployContracts";
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
    poolManagerLogicProxy = await poolManagerLogic.attach(await poolLogicProxy.poolManagerLogic());
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
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const calculatedAvailableFee = tokenPricePreMint
      .sub(tokenPriceAtLastFeeMint)
      .mul(totalSupplyPreMint)
      .div(2)
      .div(tokenPricePreMint);
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

  it("only streaming fee after 6 months", async () => {
    // streaming fee is set 2% year
    // should mint 1% of total pool tokens after 6 months
    const daoFees = await poolFactory.getDaoFee();

    await ethers.provider.send("evm_increaseTime", [(3600 * 24 * 365) / 2]);
    await ethers.provider.send("evm_mine", []);

    const daoBalanceBefore = await poolLogicProxy.balanceOf(dao.address);
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();

    const streamingFee = totalSupplyPreMint.div(100);
    checkAlmostSame(availableFeePreMint, streamingFee);

    await poolLogicProxy.mintManagerFee();

    checkAlmostSame(
      await poolLogicProxy.balanceOf(dao.address),
      daoBalanceBefore.add(availableFeePreMint.mul(daoFees[0]).div(daoFees[1])),
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
    const availableFeePreMint = await poolLogicProxy.availableManagerFee();
    const tokenPricePreMint = await poolLogicProxy.tokenPriceWithoutManagerFee();
    const totalSupplyPreMint = await poolLogicProxy.totalSupply();
    const performanceFeeNumerator = await poolManagerLogicProxy.performanceFeeNumerator();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(managerFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    const calculatedAvailableFee = tokenPricePreMint
      .sub(tokenPriceAtLastFeeMint)
      .mul(totalSupplyPreMint)
      .mul(performanceFeeNumerator)
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
    const performanceFeeNumerator = await poolManagerLogicProxy.performanceFeeNumerator();
    const managerFeeNumerator = await poolManagerLogicProxy.managerFeeNumerator();
    const streamingFee = totalSupplyPreMint
      .mul(ethers.BigNumber.from(await currentBlockTimestamp()).sub(await poolLogicProxy.lastFeeMintTime()))
      .mul(managerFeeNumerator)
      .div(10000)
      .div(86400 * 365);
    const calculatedAvailableFee = tokenPricePreMint
      .sub(tokenPriceAtLastFeeMint)
      .mul(totalSupplyPreMint)
      .mul(performanceFeeNumerator)
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
