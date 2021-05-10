// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0x242a3DF52c375bEe81b1c668741D7c63aF68FDD2';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

const { expect } = require("chai");

let logicOwner, manager, dao, user1;
let poolFactory, PoolLogic, PoolManagerLogic, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress, synthetixGuard;
let addressResolver, synthetix; // contracts
let susd, seth, slink;
let susdAsset, susdProxy, sethAsset, sethProxy, slinkAsset, slinkProxy;
let usd_price_feed, eth_price_feed, link_price_feed;

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'
const _SYNTHETIX_KEY = "0x53796e7468657469780000000000000000000000000000000000000000000000" // Synthetix
const _EXCHANGE_RATES_KEY = "0x45786368616e6765526174657300000000000000000000000000000000000000"; // ExchangeRates

const susdKey =
    '0x7355534400000000000000000000000000000000000000000000000000000000'
const sethKey =
    '0x7345544800000000000000000000000000000000000000000000000000000000'
const slinkKey =
    '0x734c494e4b000000000000000000000000000000000000000000000000000000'

// from mainnet
// const susd =
//     '0x57ab1ec28d129707052df4df418d58a2d46d5f51'
// const seth =
//     '0x5e74c9036fb86bd7ecdcb084a0673efc32ea31cb'
// const slink =
//     '0xbbc455cb4f1b9e4bfc4b73970d360c8f032efee6'

describe("PoolFactory", function() {
    before(async function(){
        [logicOwner, manager, dao, user1] = await ethers.getSigners();

        const MockContract = await ethers.getContractFactory("MockContract");
        addressResolver = await MockContract.deploy();
        synthetix = await MockContract.deploy();
        susdAsset = await MockContract.deploy();
        susdProxy = await MockContract.deploy();
        sethAsset = await MockContract.deploy();
        sethProxy = await MockContract.deploy();
        slinkAsset = await MockContract.deploy();
        slinkProxy = await MockContract.deploy();
        usd_price_feed = await MockContract.deploy();
        eth_price_feed = await MockContract.deploy();
        link_price_feed = await MockContract.deploy();
        susd = susdProxy.address;
        seth = sethProxy.address;
        slink = slinkProxy.address;

        // mock IAddressResolver
        const IAddressResolver = await hre.artifacts.readArtifact("IAddressResolver");
        const iAddressResolver = new ethers.utils.Interface(IAddressResolver.abi);
        let getAddressABI = iAddressResolver.encodeFunctionData("getAddress", [_SYNTHETIX_KEY]);
        await addressResolver.givenCalldataReturnAddress(getAddressABI, synthetix.address);

        // mock ISynthetix
        const ISynthetix = await hre.artifacts.readArtifact("ISynthetix");
        const iSynthetix = new ethers.utils.Interface(ISynthetix.abi);
        let synthsABI = iSynthetix.encodeFunctionData("synths", [susdKey]);
        await synthetix.givenCalldataReturnAddress(synthsABI, susdAsset.address);
        synthsABI = iSynthetix.encodeFunctionData("synths", [sethKey]);
        await synthetix.givenCalldataReturnAddress(synthsABI, sethAsset.address);
        synthsABI = iSynthetix.encodeFunctionData("synths", [slinkKey]);
        await synthetix.givenCalldataReturnAddress(synthsABI, slinkAsset.address);

        let synthsByAddressABI = iSynthetix.encodeFunctionData("synthsByAddress", [susdAsset.address]);
        await synthetix.givenCalldataReturn(synthsByAddressABI, susdKey);
        synthsByAddressABI = iSynthetix.encodeFunctionData("synthsByAddress", [sethAsset.address]);
        await synthetix.givenCalldataReturn(synthsByAddressABI, sethKey);
        synthsByAddressABI = iSynthetix.encodeFunctionData("synthsByAddress", [slinkAsset.address]);
        await synthetix.givenCalldataReturn(synthsByAddressABI, slinkKey);

        // mock ISynth
        const ISynth = await hre.artifacts.readArtifact("ISynth");
        const iSynth = new ethers.utils.Interface(ISynth.abi);
        const proxyABI = iSynth.encodeFunctionData("proxy", []);
        await susdAsset.givenCalldataReturnAddress(proxyABI, susdProxy.address);
        await sethAsset.givenCalldataReturnAddress(proxyABI, sethProxy.address);
        await slinkAsset.givenCalldataReturnAddress(proxyABI, slinkProxy.address);

        // mock ISynthAddressProxy
        const ISynthAddressProxy = await hre.artifacts.readArtifact("ISynthAddressProxy");
        const iSynthAddressProxy = new ethers.utils.Interface(ISynthAddressProxy.abi);
        const targetABI = iSynthAddressProxy.encodeFunctionData("target", []);
        await susdProxy.givenCalldataReturnAddress(targetABI, susdAsset.address);
        await sethProxy.givenCalldataReturnAddress(targetABI, sethAsset.address);
        await slinkProxy.givenCalldataReturnAddress(targetABI, slinkAsset.address);

        const IERC20 = await hre.artifacts.readArtifact("ERC20UpgradeSafe");
        const iERC20 = new ethers.utils.Interface(IERC20.abi);
        let decimalsABI = iERC20.encodeFunctionData("decimals", []);
        await susdProxy.givenCalldataReturnUint(decimalsABI, "18");
        await sethProxy.givenCalldataReturnUint(decimalsABI, "18");
        await slinkProxy.givenCalldataReturnUint(decimalsABI, "18");

        // Aggregators
        const AggregatorV3 = await hre.artifacts.readArtifact("AggregatorV3Interface");
        const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
        const latestRoundDataABI = iAggregatorV3.encodeFunctionData("latestRoundData", []);
        const current = (await ethers.provider.getBlock()).timestamp;
        await usd_price_feed.givenCalldataReturn(
            latestRoundDataABI,
            ethers.utils.solidityPack(['uint256', 'int256', 'uint256', 'uint256', 'uint256'], [0, 100000000, 0, current, 0])
        ); // $1
        await eth_price_feed.givenCalldataReturn(
            latestRoundDataABI,
            ethers.utils.solidityPack(['uint256', 'int256', 'uint256', 'uint256', 'uint256'], [0, 200000000000, 0, current, 0])
        ); // $2000
        await link_price_feed.givenCalldataReturn(
            latestRoundDataABI,
            ethers.utils.solidityPack(['uint256', 'int256', 'uint256', 'uint256', 'uint256'], [0, 3500000000, 0, current, 0])
        ); // $35

        PoolLogic = await ethers.getContractFactory("PoolLogic");
        poolLogic = await PoolLogic.deploy();

        PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        poolManagerLogic = await PoolManagerLogic.deploy();

        const PoolFactoryLogic = await ethers.getContractFactory("PoolFactory");
        poolFactoryLogic = await PoolFactoryLogic.deploy();

        // Deploy ProxyAdmin
        const ProxyAdmin = await ethers.getContractFactory('ProxyAdmin');
        const proxyAdmin = await ProxyAdmin.deploy();
        await proxyAdmin.deployed();

        // Deploy PoolFactoryProxy
        const PoolFactoryProxy = await ethers.getContractFactory('OZProxy');
        const poolFactoryProxy = await PoolFactoryProxy.deploy(poolFactoryLogic.address, manager.address, "0x");
        await poolFactoryProxy.deployed();

        poolFactory = await PoolFactoryLogic.attach(poolFactoryProxy.address);
        await poolFactory.initialize(
            poolLogic.address, poolManagerLogic.address, dao.address, [susd, seth, slink], [usd_price_feed.address, eth_price_feed.address, link_price_feed.address]
        );
        await poolFactory.deployed();

        const SynthetixGuard = await ethers.getContractFactory("SynthetixGuard");
        synthetixGuard = await SynthetixGuard.deploy(addressResolver.address);
        synthetixGuard.deployed();

        const synthetixGuardPointer = synthetix.address;
        await poolFactory.connect(dao).setGuard(synthetixGuardPointer, synthetixGuard.address);
    });

    it("Should be able to createFund", async function() {
        console.log("Creating Fund...");

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
            }, 60000);
        });

        // await poolManagerLogic.initialize(poolFactory.address, manager.address, "Barren Wuffet", mock.address, [sethKey])

        // console.log("Passed poolManagerLogic Init!")

        // await poolLogic.initialize(poolFactory.address, false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", mock.address)

        // console.log("Passed poolLogic Init!")

        await expect(poolFactory.createFund(
            false, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('6000'), [[susd, true], [seth, true]]
        ))
            .to.be.revertedWith('invalid fraction');

        let tx = await poolFactory.createFund(
            false, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('5000'), [[susd, true], [seth, true]]
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
        expect(await poolManagerLogicProxy.isSupportedAsset(susd)).to.be.true
        expect(await poolManagerLogicProxy.isSupportedAsset(seth)).to.be.true

        //Other assets are not supported
        expect(await poolManagerLogicProxy.isSupportedAsset(slink)).to.be.false

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
            }, 60000);
        });
        // mock IERC20 transferFrom to return true
        const IERC20 = await hre.artifacts.readArtifact("IERC20");
        const iERC20 = new ethers.utils.Interface(IERC20.abi);
        let transferFromABI = iERC20.encodeFunctionData("transferFrom", [logicOwner.address, poolLogicProxy.address, 100e18.toString()]);
        await susdProxy.givenCalldataReturnBool(transferFromABI, true);

        let totalFundValue = await poolLogicProxy.totalFundValue();
        // As default there's susd and seth and each return 1 by IExchangeRates
        expect(totalFundValue.toString()).to.equal('0');

        await expect(poolLogicProxy.deposit(slink, 100e18.toString())).to.be.revertedWith("invalid deposit asset");
        await poolLogicProxy.deposit(susd, 100e18.toString());
        let event = await depositEvent;

        expect(event.fundAddress).to.equal(poolLogicProxy.address);
        expect(event.investor).to.equal(logicOwner.address);
        expect(event.valueDeposited).to.equal(100e8.toString());
        expect(event.fundTokensReceived).to.equal(100e8.toString());
        expect(event.totalInvestorFundTokens).to.equal(100e8.toString());
        expect(event.fundValue).to.equal(100e8.toString());
        expect(event.totalSupply).to.equal(100e8.toString());
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

        // mock IERC20 balance
        const IERC20 = await hre.artifacts.readArtifact("IERC20");
        const iERC20 = new ethers.utils.Interface(IERC20.abi);
        let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
        await susdProxy.givenCalldataReturnUint(balanceOfABI, 100e18.toString());

        // Withdraw 50%
        let withdrawAmount = 50e8
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
        expect(event.totalInvestorFundTokens).to.equal(50e8.toString());
        expect(event.fundValue).to.equal(100e8.toString());
        expect(event.totalSupply).to.equal((100e8 - fundTokensWithdrawn).toString());
    });

    it('should be able to manage pool',async function() {
        await poolFactory.createFund(
            true, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('5000'), [[susd, true], [seth, true]]
        );

        let deployedFundsLength = await poolFactory.deployedFundsLength()
        let fundAddress = await poolFactory.deployedFunds(deployedFundsLength - 1)
        let poolLogicPrivateProxy = await PoolLogic.attach(fundAddress)
        let poolManagerLogicPrivateProxy = await PoolManagerLogic.attach(await poolLogicPrivateProxy.poolManagerLogic())

        const IERC20 = await hre.artifacts.readArtifact("IERC20");
        const iERC20 = new ethers.utils.Interface(IERC20.abi);
        let transferFromABI = iERC20.encodeFunctionData("transferFrom", [logicOwner.address, poolLogicPrivateProxy.address, 100e18.toString()]);
        await susdProxy.givenMethodReturnBool(transferFromABI, true);

        // Can't deposit when not being a member
        await expect(poolLogicPrivateProxy.deposit(susd, 100e18.toString()))
            .to.be.revertedWith('only members allowed');

        await expect(poolManagerLogicPrivateProxy.addMember(logicOwner.address))
            .to.be.revertedWith('only manager');

        let poolLogicPrivateManagerProxy = poolLogicPrivateProxy.connect(manager);
        let poolManagerLogicPrivateManagerProxy = poolManagerLogicPrivateProxy.connect(manager);

        // Can deposit after being a member
        await poolManagerLogicPrivateManagerProxy.addMember(logicOwner.address)

        await poolLogicPrivateProxy.deposit(susd, 100e18.toString())

        // Can't deposit after being removed from a member
        await poolManagerLogicPrivateManagerProxy.removeMember(logicOwner.address)

        await expect(poolLogicPrivateProxy.deposit(susd, 100e18.toString()))
            .to.be.revertedWith('only members allowed');

        // Can set trader
        await expect(poolManagerLogicPrivateProxy.setTrader(user1.address))
            .to.be.revertedWith('only manager');

        await poolManagerLogicPrivateManagerProxy.setTrader(user1.address)

        // Can remove trader
        await expect(poolManagerLogicPrivateProxy.removeTrader())
            .to.be.revertedWith('only manager');

        await poolManagerLogicPrivateManagerProxy.removeTrader()

        // Can change manager
        await poolManagerLogicPrivateManagerProxy.changeManager(user1.address, "User1")

        await expect(poolManagerLogicPrivateProxy.changeManager(logicOwner.address, "Logic Owner"))
            .to.be.revertedWith('only manager');

    });

    it('should be able to manage assets', async function() {
        await expect(poolManagerLogicProxy.changeAssets([[slink, false]], []))
            .to.be.revertedWith('only manager or trader');

        let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);
        let poolManagerLogicUser1Proxy = poolManagerLogicProxy.connect(user1);

        // Can add asset
        await poolManagerLogicManagerProxy.changeAssets([[slink, false]], [])

        let numberOfSupportedAssets = await poolManagerLogicManagerProxy.numberOfSupportedAssets()
        expect(numberOfSupportedAssets).to.eq("3");

        // Can not remove persist asset
        await expect(poolManagerLogicUser1Proxy.changeAssets([], [[slink, false]]))
            .to.be.revertedWith('only manager or trader');

        // Can't add invalid asset
        let invalid_synth_asset = '0x823bE81bbF96BEc0e25CA13170F5AaCb5B79ba83';
        await expect(poolManagerLogicManagerProxy.changeAssets([[invalid_synth_asset, false]], []))
            .to.be.revertedWith('invalid asset');

        // Can't remove asset with non zero balance
        // mock IERC20 balanceOf to return non zero
        const IERC20 = await hre.artifacts.readArtifact("IERC20");
        let iERC20 = new ethers.utils.Interface(IERC20.abi)
        let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address])
        await slinkProxy.givenCalldataReturnUint(balanceOfABI, 1)

        await expect(poolManagerLogicManagerProxy.changeAssets([], [[slink, false]]))
            .to.be.revertedWith("revert cannot remove non-empty asset");

        // Can remove asset
        await slinkProxy.givenCalldataReturnUint(balanceOfABI, 0)
        await poolManagerLogicManagerProxy.changeAssets([], [[slink, false]])

        numberOfSupportedAssets = await poolManagerLogicManagerProxy.numberOfSupportedAssets()
        expect(numberOfSupportedAssets).to.eq("2");

        expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.false;
        expect(await poolManagerLogicProxy.numberOfDepositAssets()).to.be.equal(2);
        await poolManagerLogicManagerProxy.changeAssets([[slink, true]], []);
        expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.true;
        expect(await poolManagerLogicProxy.numberOfDepositAssets()).to.be.equal(3);
        await poolManagerLogicManagerProxy.changeAssets([], [[slink, true]])
        expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.false;
        expect(await poolManagerLogicProxy.numberOfDepositAssets()).to.be.equal(2);
    });

    it('should be able to manage fees', async function() {
        //Can't set manager fee if not manager or if fee too high
        await expect(poolManagerLogicProxy.announceManagerFeeIncrease(4000))
            .to.be.revertedWith('only manager');

        let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

        await expect(poolManagerLogicManagerProxy.announceManagerFeeIncrease(6100))
            .to.be.revertedWith('exceeded allowed increase');

        //Can set manager fee
        await poolManagerLogicManagerProxy.announceManagerFeeIncrease(4000)

        await expect(poolManagerLogicManagerProxy.commitManagerFeeIncrease())
            .to.be.revertedWith('fee increase delay active');

        ethers.provider.send("evm_increaseTime", [3600 * 24 * 7 * 4])   // add 1 day

        await poolManagerLogicManagerProxy.commitManagerFeeIncrease()

        let [managerFeeNumerator, managerFeeDenominator] = await poolManagerLogicManagerProxy.getManagerFee()
        expect(managerFeeNumerator.toString()).to.equal('4000');
        expect(managerFeeDenominator.toString()).to.equal('10000');
    });

    // Synthetix transaction guard
    it("Only manager or trader can execute transaction", async () => {
        await expect(poolManagerLogicProxy.connect(logicOwner).execTransaction(synthetix.address, "0x00"))
            .to.be.revertedWith('only manager or trader');
    });

    it("Should fail with invalid destination", async () => {
        await expect(poolManagerLogicProxy.connect(manager).execTransaction(poolManagerLogicProxy.address, "0x00"))
            .to.be.revertedWith("invalid destination");
    });

    it("Should exec transaction", async () => {
        let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

        let exchangeEvent = new Promise((resolve, reject) => {
            synthetixGuard.on('Exchange', (
                managerLogicAddress,
                sourceAsset,
                sourceAmount,
                destinationAsset,
                time, event) => {
                    event.removeListener();

                    resolve({
                        managerLogicAddress: managerLogicAddress,
                        sourceAsset: sourceAsset,
                        sourceAmount: sourceAmount,
                        destinationAsset: destinationAsset,
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

        await synthetix.givenCalldataRevert(exchangeWithTrackingABI);
        
        await expect(poolManagerLogicManagerProxy.execTransaction(synthetix.address, exchangeWithTrackingABI))
            .to.be.revertedWith("failed to execute the call");

        await synthetix.givenCalldataReturnUint(exchangeWithTrackingABI, 1e18.toString())
        await poolManagerLogicManagerProxy.execTransaction(synthetix.address, exchangeWithTrackingABI);

        let event = await exchangeEvent;
        expect(event.sourceAsset).to.equal(susd);
        expect(event.sourceAmount).to.equal(100e18.toString());
        expect(event.destinationAsset).to.equal(seth);
    });

    it('should be able to upgrade/set implementation logic', async function() {
        await poolFactory.setLogic(ZERO_ADDRESS, ZERO_ADDRESS)

        let poolManagerLogicAddress = await poolFactory.getLogic(1)
        expect(poolManagerLogicAddress).to.equal(ZERO_ADDRESS);

        let poolLogicAddress = await poolFactory.getLogic(2)
        expect(poolLogicAddress).to.equal(ZERO_ADDRESS);
    });

});

