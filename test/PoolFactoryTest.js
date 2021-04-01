// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0x242a3DF52c375bEe81b1c668741D7c63aF68FDD2';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

const { expect } = require("chai");

let logicOwner, poolFactory, poolLogic, poolManagerLogic, mock;

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

const _SYNTHETIX_KEY = "0x53796e7468657469780000000000000000000000000000000000000000000000" // Synthetix

const _SUSD_KEY = "0x7355534400000000000000000000000000000000000000000000000000000000" // SUSD

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
    let synthsABI = iSynthetix.encodeFunctionData("synths", [_SUSD_KEY])
    await mock.givenMethodReturnAddress(synthsABI, mock.address)

    // mock ISynth
    const ISynth = await hre.artifacts.readArtifact("ISynth");
    let iSynth = new ethers.utils.Interface(ISynth.abi)
    let proxyABI = iSynth.encodeFunctionData("proxy", [])
    await mock.givenMethodReturnAddress(proxyABI, mock.address)

    const PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();
    console.log("poolLogic deployed at: ", poolLogic.address)

    const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
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
                managerFeeNumerator,
                managerFeeDenominator
            });
        });

        setTimeout(() => {
            reject(new Error('timeout'));
        }, 60000)
    });

    // await poolManagerLogic.initialize(poolFactory.address, logicAdmin.address, "Barren Wuffet", mock.address, [])

    // console.log("Passed poolManagerLogic Init!")

    // await poolLogic.initialize(poolFactory.address, false, logicAdmin.address, "Barren Wuffet", "Test Fund", mock.address)

    // console.log("Passed poolLogic Init!")

    let tx = await poolFactory.createFund(
      false, logicAdmin.address, 'Barren Wuffet', 'Test Fund', new ethers.BigNumber.from('5000'), []
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

  });

  it('should be able to upgrade/set implementation logic', async function() {
    await poolFactory.setLogic(ZERO_ADDRESS, ZERO_ADDRESS)

    let poolManagerLogicAddress = await poolFactory.getLogic(1)
    expect(poolManagerLogicAddress).to.equal(ZERO_ADDRESS);

    let poolLogicAddress = await poolFactory.getLogic(2)
    expect(poolLogicAddress).to.equal(ZERO_ADDRESS);
  });
});

