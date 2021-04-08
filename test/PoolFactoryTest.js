// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0x242a3DF52c375bEe81b1c668741D7c63aF68FDD2';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

const { expect } = require("chai");

let logicOwner, poolFactory, PoolLogic, PoolManagerLogic, poolLogic, poolManagerLogic, mock, poolLogicProxy, poolManagerLogicProxy;

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

const _SYNTHETIX_KEY = "0x53796e7468657469780000000000000000000000000000000000000000000000" // Synthetix

const _EXCHANGE_RATES_KEY = "0x45786368616e6765526174657300000000000000000000000000000000000000"; // ExchangeRates

const susdKey =
    '0x7355534400000000000000000000000000000000000000000000000000000000'
const sethKey =
    '0x7345544800000000000000000000000000000000000000000000000000000000'
const slinkKey =
    '0x734c494e4b000000000000000000000000000000000000000000000000000000'

describe("PoolFactory", function() {
  before(async function(){
    [logicOwner, logicAdmin] = await ethers.getSigners();

    const MockContract = await ethers.getContractFactory("MockContract")
    mock = await MockContract.deploy()
    console.log("Mock deployed at: ", mock.address)

    // mock IAddressResolver
    const IAddressResolver = await hre.artifacts.readArtifact("IAddressResolver");
    let iAddressResolver = new ethers.utils.Interface(IAddressResolver.abi)
    let getAddressABI = iAddressResolver.encodeFunctionData("getAddress", [_SYNTHETIX_KEY])
    await mock.givenMethodReturnAddress(getAddressABI, mock.address)

    // mock ISynthetix
    const ISynthetix = await hre.artifacts.readArtifact("ISynthetix");
    let iSynthetix = new ethers.utils.Interface(ISynthetix.abi)
    let synthsABI = iSynthetix.encodeFunctionData("synths", [susdKey])
    await mock.givenMethodReturnAddress(synthsABI, mock.address)

    // mock ISynth
    const ISynth = await hre.artifacts.readArtifact("ISynth");
    let iSynth = new ethers.utils.Interface(ISynth.abi)
    let proxyABI = iSynth.encodeFunctionData("proxy", [])
    await mock.givenMethodReturnAddress(proxyABI, mock.address)

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();
    console.log("poolLogic deployed at: ", poolLogic.address)

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();
    console.log("poolManagerLogic deployed at: ", poolManagerLogic.address)

    const PoolFactoryLogic = await ethers.getContractFactory("PoolFactory");
    poolFactoryLogic = await PoolFactoryLogic.deploy();
    console.log("PoolFactoryLogic deployed at: ", poolFactoryLogic.address)

    // Deploy ProxyAdmin
    const ProxyAdmin = await ethers.getContractFactory('ProxyAdmin')
    const proxyAdmin = await ProxyAdmin.deploy()
    await proxyAdmin.deployed()

    // Deploy PoolFactoryProxy
    const PoolFactoryProxy = await ethers.getContractFactory('OZProxy')
    const poolFactoryProxy = await PoolFactoryProxy.deploy(poolFactoryLogic.address, logicAdmin.address, "0x")
    await poolFactoryProxy.deployed()

    poolFactory = await PoolFactoryLogic.attach(poolFactoryProxy.address)
    await poolFactory.initialize(
      mock.address, poolLogic.address, poolManagerLogic.address, TESTNET_DAO
    );
    await poolFactory.deployed();
    console.log("poolFactory deployed to:", poolFactory.address);
  });

  it("Should be able to createFund", async function() {
    console.log("Creating Fund...")

    let fundCreatedEvent = new Promise((resolve, reject) => {
        poolFactory.on('FundCreated', (fundAddress, isPoolPrivate, fundName, managerName, manager, time, managerFeeNumerator, managerFeeDenominator, event) => {
            event.removeListener();

            resolve({
                fundAddress: fundAddress,
                isPoolPrivate: isPoolPrivate,
                fundName: fundName,
                managerName: managerName,
                manager: manager,
                time: time,
                managerFeeNumerator: managerFeeNumerator,
                managerFeeDenominator: managerFeeDenominator
            });
        });

        setTimeout(() => {
            reject(new Error('timeout'));
        }, 60000)
    });

    // await poolManagerLogic.initialize(poolFactory.address, logicAdmin.address, "Barren Wuffet", mock.address, [sethKey])

    // console.log("Passed poolManagerLogic Init!")

    // await poolLogic.initialize(poolFactory.address, false, logicAdmin.address, "Barren Wuffet", "Test Fund", mock.address)

    // console.log("Passed poolLogic Init!")

    let tx = await poolFactory.createFund(
      false, logicAdmin.address, 'Barren Wuffet', 'Test Fund', new ethers.BigNumber.from('5000'), [sethKey]
    );

    let event = await fundCreatedEvent;

    let fundAddress = event.fundAddress
    expect(event.isPoolPrivate).to.be.false;
    expect(event.fundName).to.equal("Test Fund");
    expect(event.managerName).to.equal("Barren Wuffet");
    expect(event.manager).to.equal(logicAdmin.address);
    expect(event.managerFeeNumerator.toString()).to.equal('5000');
    expect(event.managerFeeDenominator.toString()).to.equal('10000');

    let deployedFundsLength = await poolFactory.deployedFundsLength();
    expect(deployedFundsLength.toString()).to.equal('1');

    let isPool = await poolFactory.isPool(fundAddress)
    expect(isPool).to.be.true;

    let poolManagerLogicAddress = await poolFactory.getLogic(1)
    expect(poolManagerLogicAddress).to.equal(poolManagerLogic.address);

    let poolLogicAddress = await poolFactory.getLogic(2)
    expect(poolLogicAddress).to.equal(poolLogic.address);

    poolLogicProxy = await PoolLogic.attach(fundAddress)
    let poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic()
    poolManagerLogicProxy = await PoolManagerLogic.attach(poolManagerLogicProxyAddress)

    //default assets are supported
    expect(await poolManagerLogicProxy.numberOfSupportedAssets()).to.equal("2")
    expect(await poolManagerLogicProxy.isAssetSupported(susdKey)).to.be.true
    expect(await poolManagerLogicProxy.isAssetSupported(sethKey)).to.be.true

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isAssetSupported(slinkKey)).to.be.false

  });

  it('should be able to deposit', async function() {

    let depositEvent = new Promise((resolve, reject) => {
        poolLogicProxy.on('Deposit', (fundAddress,
            investor,
            valueDeposited,
            fundTokensReceived,
            totalInvestorFundTokens,
            fundValue,
            totalSupply,
            time, event) => {
            event.removeListener();

            resolve({
                fundAddress: fundAddress,
                investor: investor,
                valueDeposited: valueDeposited,
                fundTokensReceived: fundTokensReceived,
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

    // mock IExchangeRates to return value of 1 token
    const IExchangeRates = await hre.artifacts.readArtifact("IExchangeRates");
    let iExchangeRates = new ethers.utils.Interface(IExchangeRates.abi)
    let effectiveValueABI = iExchangeRates.encodeFunctionData("effectiveValue", [susdKey, 0, susdKey])
    await mock.givenMethodReturnUint(effectiveValueABI, 1e18.toString())

    // mock IERC20 transferFrom to return true
    const IERC20 = await hre.artifacts.readArtifact("IERC20");
    let iERC20 = new ethers.utils.Interface(IERC20.abi)
    let transferFromABI = iERC20.encodeFunctionData("transferFrom", [logicOwner.address, poolLogicProxy.address, 1e18.toString()])
    await mock.givenMethodReturnBool(transferFromABI, true)

    let totalFundValue = await poolLogicProxy.totalFundValue()
    // As default there's susd and seth and each return 1 by IExchangeRates
    expect(totalFundValue.toString()).to.equal(2e18.toString());

    await poolLogicProxy.deposit(100e18.toString())

    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    expect(event.valueDeposited).to.equal(100e18.toString());
    expect(event.fundTokensReceived).to.equal(100e18.toString());
    expect(event.totalInvestorFundTokens).to.equal(100e18.toString());
    expect(event.fundValue).to.equal(102e18.toString());
    expect(event.totalSupply).to.equal(100e18.toString());
  });

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

    // Withdraw 50%
    let withdrawAmount = 50e18
    let totalSupply = await poolLogicProxy.totalSupply()
    let totalFundValue = await poolLogicProxy.totalFundValue()

    await poolLogicProxy.withdraw(withdrawAmount.toString())

    let [exitFeeNumerator, exitFeeDenominator] = await poolFactory.getExitFee()
    let daoExitFee = withdrawAmount * exitFeeNumerator / exitFeeDenominator

    let event = await withdrawalEvent;

    let fundTokensWithdrawn = withdrawAmount - daoExitFee
    let valueWithdrawn = fundTokensWithdrawn / totalSupply * totalFundValue
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    expect(event.valueWithdrawn).to.equal(valueWithdrawn.toString());
    expect(event.fundTokensWithdrawn).to.equal(fundTokensWithdrawn.toString());
    expect(event.totalInvestorFundTokens).to.equal(50e18.toString());
    expect(event.fundValue).to.equal(2e18.toString());
    expect(event.totalSupply).to.equal((100e18 - fundTokensWithdrawn).toString());
  });

  it('should be able to upgrade/set implementation logic', async function() {
    await poolFactory.setLogic(ZERO_ADDRESS, ZERO_ADDRESS)

    let poolManagerLogicAddress = await poolFactory.getLogic(1)
    expect(poolManagerLogicAddress).to.equal(ZERO_ADDRESS);

    let poolLogicAddress = await poolFactory.getLogic(2)
    expect(poolLogicAddress).to.equal(ZERO_ADDRESS);
  });

});

