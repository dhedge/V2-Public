// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0x242a3DF52c375bEe81b1c668741D7c63aF68FDD2';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

const { expect } = require("chai");

let logicOwner, poolFactory, PoolLogic, PoolManagerLogic, poolLogic, poolManagerLogic, mock, poolLogicProxy, poolManagerLogicProxy, synthsABI, fundAddress, synthetixGuard;

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
        [logicOwner, manager, user1] = await ethers.getSigners();

        const MockContract = await ethers.getContractFactory("MockContract")
        mock = await MockContract.deploy()

        // mock IAddressResolver
        const IAddressResolver = await hre.artifacts.readArtifact("IAddressResolver");
        let iAddressResolver = new ethers.utils.Interface(IAddressResolver.abi)
        let getAddressABI = iAddressResolver.encodeFunctionData("getAddress", [_SYNTHETIX_KEY])
        await mock.givenMethodReturnAddress(getAddressABI, mock.address)

        // mock ISynthetix
        const ISynthetix = await hre.artifacts.readArtifact("ISynthetix");
        let iSynthetix = new ethers.utils.Interface(ISynthetix.abi)
        synthsABI = iSynthetix.encodeFunctionData("synths", [susdKey])
        await mock.givenMethodReturnAddress(synthsABI, mock.address)

        // mock ISynth
        const ISynth = await hre.artifacts.readArtifact("ISynth");
        let iSynth = new ethers.utils.Interface(ISynth.abi)
        let proxyABI = iSynth.encodeFunctionData("proxy", [])
        await mock.givenMethodReturnAddress(proxyABI, mock.address)

        PoolLogic = await ethers.getContractFactory("PoolLogic");
        poolLogic = await PoolLogic.deploy();

        PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        poolManagerLogic = await PoolManagerLogic.deploy();

        const PoolFactoryLogic = await ethers.getContractFactory("PoolFactory");
        poolFactoryLogic = await PoolFactoryLogic.deploy();

        // Deploy ProxyAdmin
        const ProxyAdmin = await ethers.getContractFactory('ProxyAdmin')
        const proxyAdmin = await ProxyAdmin.deploy()
        await proxyAdmin.deployed()

        // Deploy PoolFactoryProxy
        const PoolFactoryProxy = await ethers.getContractFactory('OZProxy')
        const poolFactoryProxy = await PoolFactoryProxy.deploy(poolFactoryLogic.address, manager.address, "0x")
        await poolFactoryProxy.deployed()

        poolFactory = await PoolFactoryLogic.attach(poolFactoryProxy.address)
        await poolFactory.initialize(
            mock.address, poolLogic.address, poolManagerLogic.address, TESTNET_DAO
        );
        await poolFactory.deployed();

        const SynthetixGuard = await ethers.getContractFactory("SynthetixGuard");
        synthetixGuard = await SynthetixGuard.deploy();
        synthetixGuard.deployed();

        const synthetixGuardPointer = mock.address;
        await poolFactory.setGuard(synthetixGuardPointer, synthetixGuard.address);
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
                    // fundSymbol: fundSymbol,
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

        // await poolManagerLogic.initialize(poolFactory.address, manager.address, "Barren Wuffet", mock.address, [sethKey])

        // console.log("Passed poolManagerLogic Init!")

        // await poolLogic.initialize(poolFactory.address, false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", mock.address)

        // console.log("Passed poolLogic Init!")

        await expect(poolFactory.createFund(
            false, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('6000'), [sethKey]
        ))
            .to.be.revertedWith('invalid fraction');

        let tx = await poolFactory.createFund(
            false, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('5000'), [sethKey]
        );

        let event = await fundCreatedEvent;

        fundAddress = event.fundAddress
        expect(event.isPoolPrivate).to.be.false;
        expect(event.fundName).to.equal("Test Fund");
        // expect(event.fundSymbol).to.equal("DHTF");
        expect(event.managerName).to.equal("Barren Wuffet");
        expect(event.manager).to.equal(manager.address);
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

    it('should be able to exchange', async function() {
        await expect(poolManagerLogicProxy.exchange(susdKey, 100e18.toString(), sethKey))
            .to.be.revertedWith('only manager or trader');

        let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

        let exchangeEvent = new Promise((resolve, reject) => {
            poolManagerLogicManagerProxy.on('Exchange', (
                managerLogicAddress,
                manager,
                sourceKey,
                sourceAmount,
                destinationKey,
                destinationAmount,
                time, event) => {
                    event.removeListener();

                    resolve({
                        managerLogicAddress: managerLogicAddress,
                        manager: manager,
                        sourceKey: sourceKey,
                        sourceAmount: sourceAmount,
                        destinationKey: destinationKey,
                        destinationAmount: destinationAmount,
                        time: time
                    });
                });

            setTimeout(() => {
                reject(new Error('timeout'));
            }, 60000)
        });

        //now if we exchange all susd into seth
        await poolManagerLogicManagerProxy.exchange(susdKey, 100e18.toString(), sethKey);

        let event = await exchangeEvent;
        expect(event.sourceKey).to.equal(susdKey);
        expect(event.sourceAmount).to.equal(100e18.toString());
        expect(event.destinationKey).to.equal(sethKey);
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

        await expect(poolLogicProxy.withdraw(withdrawAmount.toString()))
            .to.be.revertedWith('cooldown active');

        // await poolFactory.setExitCooldown(0);
        ethers.provider.send("evm_increaseTime", [3600 * 24])   // add 1 day

        await poolLogicProxy.withdraw(withdrawAmount.toString())

        // let [exitFeeNumerator, exitFeeDenominator] = await poolFactory.getExitFee()
        // let daoExitFee = withdrawAmount * exitFeeNumerator / exitFeeDenominator

        let event = await withdrawalEvent;

        let fundTokensWithdrawn = withdrawAmount
        let valueWithdrawn = fundTokensWithdrawn / totalSupply * totalFundValue
        expect(event.fundAddress).to.equal(poolLogicProxy.address);
        expect(event.investor).to.equal(logicOwner.address);
        expect(event.valueWithdrawn).to.equal(valueWithdrawn.toString());
        expect(event.fundTokensWithdrawn).to.equal(fundTokensWithdrawn.toString());
        expect(event.totalInvestorFundTokens).to.equal(50e18.toString());
        expect(event.fundValue).to.equal(2e18.toString());
        expect(event.totalSupply).to.equal((100e18 - fundTokensWithdrawn).toString());
    });

    it('should be able to manage pool',async function() {
        await poolFactory.createFund(
            true, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('5000'), [sethKey]
        );

        let deployedFundsLength = await poolFactory.deployedFundsLength()
        let fundAddress = await poolFactory.deployedFunds(deployedFundsLength - 1)
        let poolLogicPrivateProxy = await PoolLogic.attach(fundAddress)
        // Can't deposit when not being a member
        await expect(poolLogicPrivateProxy.deposit(100e18.toString()))
            .to.be.revertedWith('only members allowed');

        await expect(poolLogicPrivateProxy.addMember(logicOwner.address))
            .to.be.revertedWith('only manager');

        let poolLogicPrivateManagerProxy = poolLogicPrivateProxy.connect(manager);

        // Can deposit after being a member
        await poolLogicPrivateManagerProxy.addMember(logicOwner.address)

        await poolLogicPrivateProxy.deposit(100e18.toString())

        // Can't deposit after being removed from a member
        await poolLogicPrivateManagerProxy.removeMember(logicOwner.address)

        await expect(poolLogicPrivateProxy.deposit(100e18.toString()))
            .to.be.revertedWith('only members allowed');

        // Can set trader
        await expect(poolLogicPrivateProxy.setTrader(user1.address))
            .to.be.revertedWith('only manager');

        await poolLogicPrivateManagerProxy.setTrader(user1.address)

        // Can remove trader
        await expect(poolLogicPrivateProxy.removeTrader())
            .to.be.revertedWith('only manager');

        await poolLogicPrivateManagerProxy.removeTrader()

        // Can change manager
        await poolLogicPrivateManagerProxy.changeManager(user1.address, "User1")

        await expect(poolLogicPrivateManagerProxy.changeManager(logicOwner.address, "Logic Owner"))
            .to.be.revertedWith('only manager');

    });

    it('should be able to manage assets', async function() {
        await expect(poolManagerLogicProxy.addToSupportedAssets(slinkKey))
            .to.be.revertedWith('only manager or trader');

        let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);
        let poolManagerLogicUser1Proxy = poolManagerLogicProxy.connect(user1);

        // Can add asset
        await poolManagerLogicManagerProxy.addToSupportedAssets(slinkKey)

        let numberOfSupportedAssets = await poolManagerLogicManagerProxy.numberOfSupportedAssets()
        expect(numberOfSupportedAssets).to.eq("3");

        // Can not remove persist asset
        await expect(poolManagerLogicUser1Proxy.removeFromSupportedAssets(slinkKey))
            .to.be.revertedWith('only manager, trader or DAO');

        await expect(poolManagerLogicManagerProxy.removeFromSupportedAssets(susdKey))
            .to.be.revertedWith("cannot remove persistent assets");

        // Can't add non-synth asset
        await mock.givenMethodReturnAddress(synthsABI, ZERO_ADDRESS)
        let ASDFKey = '0x4153444600000000000000000000000000000000000000000000000000000000';
        await expect(poolManagerLogicManagerProxy.addToSupportedAssets(ASDFKey))
            .to.be.revertedWith('non-synth asset');
        await mock.givenMethodReturnAddress(synthsABI, mock.address)

        // Can't remove asset with non zero balance
        // mock IERC20 balanceOf to return non zero
        const IERC20 = await hre.artifacts.readArtifact("IERC20");
        let iERC20 = new ethers.utils.Interface(IERC20.abi)
        let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolManagerLogicManagerProxy.address])
        await mock.givenMethodReturnUint(balanceOfABI, 1)

        await expect(poolManagerLogicManagerProxy.removeFromSupportedAssets(slinkKey))
            .to.be.revertedWith("revert cannot remove non-empty asset");

        // Can remove asset
        await mock.givenMethodReturnUint(balanceOfABI, 0)
        await poolManagerLogicManagerProxy.removeFromSupportedAssets(slinkKey)

        numberOfSupportedAssets = await poolManagerLogicManagerProxy.numberOfSupportedAssets()
        expect(numberOfSupportedAssets).to.eq("2");

    });

    it('should be able to manage fees', async function() {
        //Can't set manager fee if not manager or if fee too high
        await expect(poolManagerLogicProxy.announceManagerFeeIncrease(fundAddress, 4000))
            .to.be.revertedWith('only manager');

        let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

        await expect(poolManagerLogicManagerProxy.announceManagerFeeIncrease(fundAddress, 6100))
            .to.be.revertedWith('exceeded allowed increase');

        //Can set manager fee
        await poolManagerLogicManagerProxy.announceManagerFeeIncrease(fundAddress, 4000)

        await expect(poolManagerLogicManagerProxy.commitManagerFeeIncrease(fundAddress))
            .to.be.revertedWith('fee increase delay active');

        ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4])   // add 1 day

        await poolManagerLogicManagerProxy.commitManagerFeeIncrease(fundAddress)

        let [managerFeeNumerator, managerFeeDenominator] = await poolManagerLogicManagerProxy.getManagerFee(fundAddress)
        expect(managerFeeNumerator.toString()).to.equal('4000');
        expect(managerFeeDenominator.toString()).to.equal('10000');
    });

    // Synthetix transaction guard
    it("Only manager or trader can execute transaction", async () => {
        await expect(poolManagerLogicProxy.connect(logicOwner).execTransaction(mock.address, "0x00"))
            .to.be.revertedWith('only manager or trader');
    });

    it("Should fail with invalid destination", async () => {
        await expect(poolManagerLogicProxy.connect(manager).execTransaction(poolManagerLogicProxy.address, "0x00"))
            .to.be.revertedWith("invalid destination");
    });

    it("Should exec transaction", async () => {
        let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

        let exchangeEvent = new Promise((resolve, reject) => {
            poolManagerLogicManagerProxy.on('Exchange', (
                managerLogicAddress,
                manager,
                sourceKey,
                sourceAmount,
                destinationKey,
                destinationAmount,
                time, event) => {
                    event.removeListener();

                    resolve({
                        managerLogicAddress: managerLogicAddress,
                        manager: manager,
                        sourceKey: sourceKey,
                        sourceAmount: sourceAmount,
                        destinationKey: destinationKey,
                        destinationAmount: destinationAmount,
                        time: time
                    });
                });

            setTimeout(() => {
                reject(new Error('timeout'));
            }, 60000)
        });

        const sourceKey = susdKey;
        const sourceAmount = 100e18.toString();
        const destinationKey = sethKey;
        const daoAddress = await poolFactory.getDaoAddress();
        const trackingCode = await poolFactory.getTrackingCode();
        const ISynthetix = await hre.artifacts.readArtifact("ISynthetix");
        const iSynthetix = new ethers.utils.Interface(ISynthetix.abi)
        const exchangeWithTrackingABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [sourceKey, sourceAmount, destinationKey, daoAddress, trackingCode]);

        await mock.givenMethodRevert(exchangeWithTrackingABI);
        
        await expect(poolManagerLogicManagerProxy.execTransaction(mock.address, exchangeWithTrackingABI))
            .to.be.revertedWith("failed to execute exchange");

        await mock.givenMethodReturnUint(exchangeWithTrackingABI, 1e18.toString())
        await poolManagerLogicManagerProxy.execTransaction(mock.address, exchangeWithTrackingABI);

        let event = await exchangeEvent;
        expect(event.sourceKey).to.equal(susdKey);
        expect(event.sourceAmount).to.equal(100e18.toString());
        expect(event.destinationKey).to.equal(sethKey);
        expect(event.destinationAmount).to.equal(1e18.toString());
    });

    it('should be able to upgrade/set implementation logic', async function() {
        await poolFactory.setLogic(ZERO_ADDRESS, ZERO_ADDRESS)

        let poolManagerLogicAddress = await poolFactory.getLogic(1)
        expect(poolManagerLogicAddress).to.equal(ZERO_ADDRESS);

        let poolLogicAddress = await poolFactory.getLogic(2)
        expect(poolLogicAddress).to.equal(ZERO_ADDRESS);
    });

});

