// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = "0xb08b62e1cdfd37eCCd69A9ACe67322CCF801b3A6";
const TESTNET_DAO = "0xab0c25f17e993F90CaAaec06514A2cc28DEC340b";

const { expect } = require("chai");

const hre = require("hardhat");
const l2ethers = hre.l2ethers;

let poolFactory,
  PoolLogic,
  PoolManagerLogic,
  poolLogic,
  poolManagerLogic,
  mock,
  poolLogicProxy,
  poolManagerLogicProxy,
  synthsABI,
  fundAddress;

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const _SYNTHETIX_KEY = "0x53796e7468657469780000000000000000000000000000000000000000000000"; // Synthetix

const _EXCHANGE_RATES_KEY = "0x45786368616e6765526174657300000000000000000000000000000000000000"; // ExchangeRates

const susdKey = "0x7355534400000000000000000000000000000000000000000000000000000000";
const sethKey = "0x7345544800000000000000000000000000000000000000000000000000000000";
const slinkKey = "0x734c494e4b000000000000000000000000000000000000000000000000000000";
const sbtcKey = "0x7342544300000000000000000000000000000000000000000000000000000000";

const ProxysETH = "0x94B41091eB29b36003aC1C6f0E55a5225633c884";
const ProxysAAVE = "0x503e91fc2b9Ad7453700130d0825E661565E4c3b";
const ProxysUNI = "0x3E88bFAbDCd2b336C4a430262809Cf4a0AC5cd57";
const ProxysLINK = "0xe2B26511C64FE18Acc0BE8EA7c888cDFcacD846E";
const ProxysBTC = "0x23F608ACc41bd7BCC617a01a9202214EE305439a";
const ProxyERC20sUSD = "0xaA5068dC2B3AADE533d3e52C6eeaadC6a8154c57";

const version = "v2.0.0-rc.1";

// For run in console
// const versions = require("./publish/ovm/kovan/versions.json");
const versions = require("../../../publish/ovm/kovan/versions.json");

describe("PoolFactory", function () {
  before(async function () {
    [manager, user1] = await ethers.getSigners();

    const AssetHandlerLogic = await l2ethers.getContractFactory("AssetHandler");
    AssetHandlerProxy = await AssetHandlerLogic.attach(versions[version].contracts.AssetHandlerProxy);

    PoolLogic = await l2ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.attach(versions[version].contracts.PoolLogic);

    PoolManagerLogic = await l2ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.attach(versions[version].contracts.PoolManagerLogic);

    const PoolFactoryLogic = await l2ethers.getContractFactory("PoolFactory");
    poolFactory = await PoolFactoryLogic.attach(versions[version].contracts.PoolFactoryProxy);
  });

  it("Should be able to createFund", async function () {
    console.log("Creating Fund...");

    let fundCreatedEvent = new Promise((resolve, reject) => {
      poolFactory.on(
        "FundCreated",
        (
          fundAddress,
          isPoolPrivate,
          fundName,
          managerName,
          manager,
          time,
          managerFeeNumerator,
          managerFeeDenominator,
          event,
        ) => {
          event.removeListener();

          resolve({
            fundAddress: fundAddress,
            isPoolPrivate: isPoolPrivate,
            fundName: fundName,
            // fundSymbol: fundSymbol,
            managerName: managerName,
            manager: manager,
            time: time,
            managerFeeNumerator: managerFeeNumerator,
            managerFeeDenominator: managerFeeDenominator,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    let deployedFunds = await poolFactory.getDeployedFunds();
    let deployedFundsLength = deployedFunds.length;

    let tx = await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      new ethers.BigNumber.from("5000"),
      [
        [ProxysETH, true],
        [ProxysLINK, true],
      ],
    );

    let event = await fundCreatedEvent;

    fundAddress = event.fundAddress;
    expect(event.isPoolPrivate).to.be.false;
    expect(event.fundName).to.equal("Test Fund");
    // expect(event.fundSymbol).to.equal("DHTF");
    expect(event.managerName).to.equal("Barren Wuffet");
    expect(event.manager).to.equal(manager.address);
    expect(event.managerFeeNumerator.toString()).to.equal("5000");
    expect(event.managerFeeDenominator.toString()).to.equal("10000");

    let deployedFunds = await poolFactory.getDeployedFunds();
    let deployedFundsLengthAfter = deployedFunds.length;
    expect(deployedFundsLengthAfter.toString()).to.equal(deployedFundsLength.add(1).toString());

    let isPool = await poolFactory.isPool(fundAddress);
    expect(isPool).to.be.true;

    let poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(poolManagerLogic.address);

    let poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(poolLogic.address);

    poolLogicProxy = await PoolLogic.attach(fundAddress);
    let poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
    poolManagerLogicProxy = await PoolManagerLogic.attach(poolManagerLogicProxyAddress);

    //default assets are supported
    expect(await poolManagerLogicProxy.numberOfSupportedAssets()).to.equal("2");
    expect(await poolManagerLogicProxy.isSupportedAsset(ProxysETH)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(ProxysLINK)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(ProxysUNI)).to.be.false;
  });

  it("should be able to deposit", async function () {
    let depositEvent = new Promise((resolve, reject) => {
      poolLogicProxy.on(
        "Deposit",
        (
          fundAddress,
          investor,
          valueDeposited,
          fundTokensReceived,
          totalInvestorFundTokens,
          fundValue,
          totalSupply,
          time,
          event,
        ) => {
          event.removeListener();

          resolve({
            fundAddress: fundAddress,
            investor: investor,
            valueDeposited: valueDeposited,
            fundTokensReceived: fundTokensReceived,
            totalInvestorFundTokens: totalInvestorFundTokens,
            fundValue: fundValue,
            totalSupply: totalSupply,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    let totalFundValue = await poolLogicProxy.totalFundValue();
    let totalSupply = await poolLogicProxy.totalSupply();

    const sETH = await ethers.getContractAt("IERC20", ProxysETH);
    let value = (1e15).toString();
    await token.approve(poolLogicProxy.address, value);

    await poolLogicProxy.deposit(ProxysETH, value);

    let event = await depositEvent;
    let balance = await poolLogicProxy.balanceOf(manager.address);

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(manager.address);
    expect(event.valueDeposited).to.equal(value);
    expect(event.fundTokensReceived).to.equal(value);
    expect(event.totalInvestorFundTokens).to.equal(balance.toString());
    expect(event.fundValue).to.equal(totalFundValue.add(value));
    expect(event.totalSupply).to.equal(totalSupply.add(value));
  });

  // it('should be able to deposit again', async function() {

  //     let depositEvent = new Promise((resolve, reject) => {
  //         poolLogicProxy.on('Deposit', (fundAddress,
  //             investor,
  //             valueDeposited,
  //             fundTokensReceived,
  //             totalInvestorFundTokens,
  //             fundValue,
  //             totalSupply,
  //             time, event) => {
  //                 event.removeListener();

  //                 resolve({
  //                     fundAddress: fundAddress,
  //                     investor: investor,
  //                     valueDeposited: valueDeposited,
  //                     fundTokensReceived: fundTokensReceived,
  //                     totalInvestorFundTokens: totalInvestorFundTokens,
  //                     fundValue: fundValue,
  //                     totalSupply: totalSupply,
  //                     time: time
  //                 });
  //             });

  //         setTimeout(() => {
  //             reject(new Error('timeout'));
  //         }, 60000)
  //     });

  //     let totalFundValue = await poolLogicProxy.totalFundValue()
  //     let totalSupply = await poolLogicProxy.totalSupply();
  //     let sUSD = await poolManagerLogicProxy.getAssetProxy(susdKey)
  //     console.log("sUSD address: ", sUSD);
  //     const token = await ethers.getContractAt("IERC20", sUSD);
  //     let value = 1e18.toString()
  //     await token.approve(poolLogicProxy.address, value)

  //     await poolLogicProxy.deposit(value)

  //     let event = await depositEvent;
  //     let balance = await poolLogicProxy.balanceOf(manager.address);

  //     expect(event.fundAddress).to.equal(poolLogicProxy.address);
  //     expect(event.investor).to.equal(manager.address);
  //     expect(event.valueDeposited).to.equal(value);
  //     expect(event.fundTokensReceived).to.equal(value);
  //     expect(event.totalInvestorFundTokens).to.equal(balance.toString());
  //     expect(event.fundValue).to.equal(totalFundValue.add(value));
  //     expect(event.totalSupply).to.equal(totalSupply.add(value));
  // });

  // it('should be able to exchange', async function() {
  //     let exchangeEvent = new Promise((resolve, reject) => {
  //         poolLogicProxy.on('Exchange', (
  //             poolLogicAddress,
  //             manager,
  //             sourceKey,
  //             sourceAmount,
  //             destinationKey,
  //             destinationAmount,
  //             time, event) => {
  //                 event.removeListener();

  //                 resolve({
  //                     poolLogicAddress: poolLogicAddress,
  //                     manager: manager,
  //                     sourceKey: sourceKey,
  //                     sourceAmount: sourceAmount,
  //                     destinationKey: destinationKey,
  //                     destinationAmount: destinationAmount,
  //                     time: time
  //                 });
  //             });

  //         setTimeout(() => {
  //             reject(new Error('timeout'));
  //         }, 60000)
  //     });

  //     let sETH = await poolManagerLogicProxy.getAssetProxy(sethKey)
  //     console.log("sETH address: ", sETH);
  //     const token = await ethers.getContractAt("IERC20", sETH);
  //     let balance = await token.balanceOf(poolLogicProxy.address)

  //     await poolLogicProxy.exchange(susdKey, 1e18.toString(), sethKey);

  //     let event = await exchangeEvent;
  //     expect(event.sourceKey).to.equal(susdKey);
  //     expect(event.sourceAmount).to.equal(1e18.toString());
  //     expect(event.destinationKey).to.equal(sethKey);

  //     let balanceAfter = await token.balanceOf(poolLogicProxy.address)
  //     expect(balanceAfter.sub(balance)).to.be.above(0);
  // });

  /*
    it('should be able to withdraw', async function() {
        let withdrawalEvent = new Promise((resolve, reject) => {
            poolLogicProxy.on('Withdrawal', (
                fundAddress,
                investor,
                valueWithdrawn,
                fundTokensWithdrawn,
                totalInvestorFundTokens,
                fundValue,
                totalSupply,
                time, event) => {
                    event.removeListener();
                    resolve({
                        fundAddress: fundAddress,
                        investor: investor,
                        valueWithdrawn: valueWithdrawn,
                        fundTokensWithdrawn: fundTokensWithdrawn,
                        totalInvestorFundTokens: totalInvestorFundTokens,
                        fundValue: fundValue,
                        totalSupply: totalSupply,
                        time: time
                    });
                });
            setTimeout(() => {
                reject(new Error('timeout'));
            }, 60000)
        });
        let balance = await poolLogicProxy.balanceOf(manager.address);
        console.log("Balance: ", balance.toString())
        let withdrawAmount = 1e18
        let totalSupply = await poolLogicProxy.totalSupply()
        let totalFundValue = await poolLogicProxy.totalFundValue()
        await poolFactory.setExitCooldown(0);
        await poolLogicProxy.withdraw(withdrawAmount.toString())
        // let [exitFeeNumerator, exitFeeDenominator] = await poolFactory.getExitFee()
        // let daoExitFee = withdrawAmount * exitFeeNumerator / exitFeeDenominator
        let event = await withdrawalEvent;
        let fundTokensWithdrawn = withdrawAmount
        let valueWithdrawn = fundTokensWithdrawn / totalSupply * totalFundValue
        expect(event.fundAddress).to.equal(poolLogicProxy.address);
        expect(event.investor).to.equal(manager.address);
        // Comment out as there's little bit off as 333333333333333300 instead of 333333333333333333
        // expect(event.valueWithdrawn).to.equal(valueWithdrawn.toString());
        expect(event.fundTokensWithdrawn).to.equal(fundTokensWithdrawn.toString());
        expect(event.totalInvestorFundTokens).to.equal(50e18.toString());
        expect(event.fundValue).to.equal(2e18.toString());
        expect(event.totalSupply).to.equal((60e18 - fundTokensWithdrawn).toString());
    });
    */
});
