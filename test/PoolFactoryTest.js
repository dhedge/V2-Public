// Place holder addresses
const KOVAN_ADDRESS_RESOLVER = '0x242a3DF52c375bEe81b1c668741D7c63aF68FDD2';
const TESTNET_DAO = '0xab0c25f17e993F90CaAaec06514A2cc28DEC340b';

const { expect } = require('chai');

let logicOwner, manager, dao, user1;
let poolFactory,
  priceConsumer,
  PriceConsumerLogic,
  priceConsumerLogic,
  PoolLogic,
  PoolManagerLogic,
  poolLogic,
  poolManagerLogic,
  poolLogicProxy,
  poolManagerLogicProxy,
  fundAddress,
  synthetixGuard;
let poolFactory, PoolLogic, PoolManagerLogic, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress, synthetixGuard, erc20Guard, uniswapV2Guard;
let addressResolver, synthetix, uniswapV2Router; // contracts
let susd, seth, slink;
let susdAsset, susdProxy, sethAsset, sethProxy, slinkAsset, slinkProxy;
let usd_price_feed, eth_price_feed, link_price_feed;

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const _SYNTHETIX_KEY = '0x53796e7468657469780000000000000000000000000000000000000000000000'; // Synthetix
const _EXCHANGE_RATES_KEY = '0x45786368616e6765526174657300000000000000000000000000000000000000'; // ExchangeRates

const susdKey = '0x7355534400000000000000000000000000000000000000000000000000000000';
const sethKey = '0x7345544800000000000000000000000000000000000000000000000000000000';
const slinkKey = '0x734c494e4b000000000000000000000000000000000000000000000000000000';

// from mainnet
// const susd =
//     '0x57ab1ec28d129707052df4df418d58a2d46d5f51'
// const seth =
//     '0x5e74c9036fb86bd7ecdcb084a0673efc32ea31cb'
// const slink =
//     '0xbbc455cb4f1b9e4bfc4b73970d360c8f032efee6'

describe('PoolFactory', function () {
  before(async function () {
    [logicOwner, manager, dao, user1] = await ethers.getSigners();

    slinkAsset = await MockContract.deploy();
        const MockContract = await ethers.getContractFactory("MockContract");
        addressResolver = await MockContract.deploy();
        synthetix = await MockContract.deploy();
        uniswapV2Router = await MockContract.deploy();
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
    const IAddressResolver = await hre.artifacts.readArtifact('IAddressResolver');
    const iAddressResolver = new ethers.utils.Interface(IAddressResolver.abi);
    let getAddressABI = iAddressResolver.encodeFunctionData('getAddress', [_SYNTHETIX_KEY]);
    await addressResolver.givenCalldataReturnAddress(getAddressABI, synthetix.address);

    // mock ISynthetix
    const ISynthetix = await hre.artifacts.readArtifact('ISynthetix');
    const iSynthetix = new ethers.utils.Interface(ISynthetix.abi);
    let synthsABI = iSynthetix.encodeFunctionData('synths', [susdKey]);
    await synthetix.givenCalldataReturnAddress(synthsABI, susdAsset.address);
    synthsABI = iSynthetix.encodeFunctionData('synths', [sethKey]);
    await synthetix.givenCalldataReturnAddress(synthsABI, sethAsset.address);
    synthsABI = iSynthetix.encodeFunctionData('synths', [slinkKey]);
    await synthetix.givenCalldataReturnAddress(synthsABI, slinkAsset.address);

    let synthsByAddressABI = iSynthetix.encodeFunctionData('synthsByAddress', [susdAsset.address]);
    await synthetix.givenCalldataReturn(synthsByAddressABI, susdKey);
    synthsByAddressABI = iSynthetix.encodeFunctionData('synthsByAddress', [sethAsset.address]);
    await synthetix.givenCalldataReturn(synthsByAddressABI, sethKey);
    synthsByAddressABI = iSynthetix.encodeFunctionData('synthsByAddress', [slinkAsset.address]);
    await synthetix.givenCalldataReturn(synthsByAddressABI, slinkKey);

    // mock ISynth
    const ISynth = await hre.artifacts.readArtifact('ISynth');
    const iSynth = new ethers.utils.Interface(ISynth.abi);
    const proxyABI = iSynth.encodeFunctionData('proxy', []);
    await susdAsset.givenCalldataReturnAddress(proxyABI, susdProxy.address);
    await sethAsset.givenCalldataReturnAddress(proxyABI, sethProxy.address);
    await slinkAsset.givenCalldataReturnAddress(proxyABI, slinkProxy.address);

    // mock ISynthAddressProxy
    const ISynthAddressProxy = await hre.artifacts.readArtifact('ISynthAddressProxy');
    const iSynthAddressProxy = new ethers.utils.Interface(ISynthAddressProxy.abi);
    const targetABI = iSynthAddressProxy.encodeFunctionData('target', []);
    await susdProxy.givenCalldataReturnAddress(targetABI, susdAsset.address);
    await sethProxy.givenCalldataReturnAddress(targetABI, sethAsset.address);
    await slinkProxy.givenCalldataReturnAddress(targetABI, slinkAsset.address);

    const IERC20 = await hre.artifacts.readArtifact('ERC20UpgradeSafe');
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let decimalsABI = iERC20.encodeFunctionData('decimals', []);
    await susdProxy.givenCalldataReturnUint(decimalsABI, '18');
    await sethProxy.givenCalldataReturnUint(decimalsABI, '18');
    await slinkProxy.givenCalldataReturnUint(decimalsABI, '18');

    // Aggregators
    const AggregatorV3 = await hre.artifacts.readArtifact('AggregatorV3Interface');
    const iAggregatorV3 = new ethers.utils.Interface(AggregatorV3.abi);
    const latestRoundDataABI = iAggregatorV3.encodeFunctionData('latestRoundData', []);
    const current = (await ethers.provider.getBlock()).timestamp;
    await usd_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(['uint256', 'int256', 'uint256', 'uint256', 'uint256'], [0, 100000000, 0, current, 0]),
    ); // $1
    await eth_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(
        ['uint256', 'int256', 'uint256', 'uint256', 'uint256'],
        [0, 200000000000, 0, current, 0],
      ),
    ); // $2000
    await link_price_feed.givenCalldataReturn(
      latestRoundDataABI,
      ethers.utils.solidityPack(['uint256', 'int256', 'uint256', 'uint256', 'uint256'], [0, 3500000000, 0, current, 0]),
    ); // $35

    PriceConsumerLogic = await ethers.getContractFactory('PriceConsumer');
    priceConsumerLogic = await PriceConsumerLogic.deploy();

    PoolLogic = await ethers.getContractFactory('PoolLogic');
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory('PoolManagerLogic');
    poolManagerLogic = await PoolManagerLogic.deploy();

    const PoolFactoryLogic = await ethers.getContractFactory('PoolFactory');
    poolFactoryLogic = await PoolFactoryLogic.deploy();

    // Deploy ProxyAdmin
    const ProxyAdmin = await ethers.getContractFactory('ProxyAdmin');
    const proxyAdmin = await ProxyAdmin.deploy();
    await proxyAdmin.deployed();

    // Deploy PriceConsumerProxy
    const PriceConsumerProxy = await ethers.getContractFactory('OZProxy');
    const priceConsumerProxy = await PriceConsumerProxy.deploy(priceConsumerLogic.address, manager.address, '0x');
    await priceConsumerProxy.deployed();

    priceConsumer = await PriceConsumerLogic.attach(priceConsumerProxy.address);

        const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
        erc20Guard = await ERC20Guard.deploy();
        erc20Guard.deployed();

        const UniswapV2Guard = await ethers.getContractFactory("UniswapV2Guard");
        uniswapV2Guard = await UniswapV2Guard.deploy();
        uniswapV2Guard.deployed();

        await poolFactory.connect(dao).setERC20Guard(erc20Guard.address);
        await poolFactory.connect(dao).setGuard(synthetix.address, synthetixGuard.address);
        await poolFactory.connect(dao).setGuard(uniswapV2Router.address, uniswapV2Guard.address);
    });

    poolFactory = await PoolFactoryLogic.attach(poolFactoryProxy.address);

    // Initialize Asset Price Consumer
    const assetSusd = { asset: susd, assetType: 0, aggregator: usd_price_feed.address };
    const assetSeth = { asset: seth, assetType: 0, aggregator: eth_price_feed.address };
    const assetSlink = { asset: slink, assetType: 0, aggregator: link_price_feed.address };
    const priceConsumerInitAssets = [assetSusd, assetSeth, assetSlink];

    await priceConsumer.initialize(poolFactoryProxy.address, priceConsumerInitAssets);
    await priceConsumer.deployed();

    // Initialise pool factory
    await poolFactory.initialize(poolLogic.address, poolManagerLogic.address, priceConsumerProxy.address, dao.address);
    await poolFactory.deployed();

    const SynthetixGuard = await ethers.getContractFactory('SynthetixGuard');
    synthetixGuard = await SynthetixGuard.deploy(addressResolver.address);
    synthetixGuard.deployed();

    const synthetixGuardPointer = synthetix.address;
    await poolFactory.connect(dao).setGuard(synthetixGuardPointer, synthetixGuard.address);
  });

  it('Should be able to createFund', async function () {
    console.log('Creating Fund...');

    let fundCreatedEvent = new Promise((resolve, reject) => {
      poolFactory.on(
        'FundCreated',
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

        await expect(poolFactory.createFund(
            false, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('6000'), [[susd, true], [seth, true]]
        ))
            .to.be.revertedWith('invalid fraction');

        let tx = await poolFactory.createFund(
            false, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('5000'), [[susd, true], [seth, true]]
        );

    // await poolManagerLogic.initialize(poolFactory.address, manager.address, "Barren Wuffet", mock.address, [sethKey])

    // console.log("Passed poolManagerLogic Init!")

    // await poolLogic.initialize(poolFactory.address, false, manager.address, "Barren Wuffet", "Test Fund", "DHTF", mock.address)

    // console.log("Passed poolLogic Init!")

    await expect(
      poolFactory.createFund(
        false,
        manager.address,
        'Barren Wuffet',
        'Test Fund',
        'DHTF',
        new ethers.BigNumber.from('6000'),
        [susd, seth],
      ),
    ).to.be.revertedWith('invalid fraction');

    let tx = await poolFactory.createFund(
      false,
      manager.address,
      'Barren Wuffet',
      'Test Fund',
      'DHTF',
      new ethers.BigNumber.from('5000'),
      [susd, seth],
    );

    let event = await fundCreatedEvent;

        //default assets are supported
        expect(await poolManagerLogicProxy.numberOfSupportedAssets()).to.equal("2");
        expect(await poolManagerLogicProxy.isSupportedAsset(susd)).to.be.true
        expect(await poolManagerLogicProxy.isSupportedAsset(seth)).to.be.true

        //Other assets are not supported
        expect(await poolManagerLogicProxy.isSupportedAsset(slink)).to.be.false

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
    expect(await poolManagerLogicProxy.numberOfSupportedAssets()).to.equal('2');
    expect(await poolManagerLogicProxy.isAssetSupported(susd)).to.be.true;
    expect(await poolManagerLogicProxy.isAssetSupported(seth)).to.be.true;

        await expect(poolLogicProxy.deposit(slink, 100e18.toString())).to.be.revertedWith("invalid deposit asset");
        await poolLogicProxy.deposit(susd, 100e18.toString());
        let event = await depositEvent;

  it('should be able to deposit', async function () {
    let depositEvent = new Promise((resolve, reject) => {
      poolLogicProxy.on(
        'Deposit',
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
        reject(new Error('timeout'));
      }, 60000);
    });
    // mock IERC20 transferFrom to return true
    const IERC20 = await hre.artifacts.readArtifact('IERC20');
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let transferFromABI = iERC20.encodeFunctionData('transferFrom', [
      logicOwner.address,
      poolLogicProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenCalldataReturnBool(transferFromABI, true);

    let totalFundValue = await poolLogicProxy.totalFundValue();
    // As default there's susd and seth and each return 1 by IExchangeRates
    expect(totalFundValue.toString()).to.equal('0');

    await poolLogicProxy.deposit(susd, (100e18).toString());
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    expect(event.valueDeposited).to.equal((100e18).toString());
    expect(event.fundTokensReceived).to.equal((100e18).toString());
    expect(event.totalInvestorFundTokens).to.equal((100e18).toString());
    expect(event.fundValue).to.equal((100e18).toString());
    expect(event.totalSupply).to.equal((100e18).toString());
  });

        // mock IERC20 balance
        const IERC20 = await hre.artifacts.readArtifact("IERC20");
        const iERC20 = new ethers.utils.Interface(IERC20.abi);
        let balanceOfABI = iERC20.encodeFunctionData("balanceOf", [poolLogicProxy.address]);
        await susdProxy.givenCalldataReturnUint(balanceOfABI, 100e18.toString());

          resolve({
            fundAddress: fundAddress,
            investor: investor,
            valueWithdrawn: valueWithdrawn,
            fundTokensWithdrawn: fundTokensWithdrawn,
            totalInvestorFundTokens: totalInvestorFundTokens,
            fundValue: fundValue,
            totalSupply: totalSupply,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error('timeout'));
      }, 60000);
    });

    // mock IERC20 balance
    const IERC20 = await hre.artifacts.readArtifact('IERC20');
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let balanceOfABI = iERC20.encodeFunctionData('balanceOf', [poolManagerLogicProxy.address]);
    await susdProxy.givenCalldataReturnUint(balanceOfABI, (100e18).toString());

    // Withdraw 50%
    let withdrawAmount = 50e18;
    let totalSupply = await poolLogicProxy.totalSupply();
    let totalFundValue = await poolLogicProxy.totalFundValue();

    await expect(poolLogicProxy.withdraw(withdrawAmount.toString())).to.be.revertedWith('cooldown active');

    // await poolFactory.setExitCooldown(0);
    ethers.provider.send('evm_increaseTime', [3600 * 24]); // add 1 day

    await poolLogicProxy.withdraw(withdrawAmount.toString());

    it('should be able to manage pool',async function() {
        await poolFactory.createFund(
            true, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('5000'), [[susd, true], [seth, true]]
        );

    let event = await withdrawalEvent;

    let fundTokensWithdrawn = withdrawAmount;
    let valueWithdrawn = (fundTokensWithdrawn / totalSupply) * totalFundValue;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    expect(event.valueWithdrawn).to.equal(valueWithdrawn.toString());
    expect(event.fundTokensWithdrawn).to.equal(fundTokensWithdrawn.toString());
    expect(event.totalInvestorFundTokens).to.equal((50e18).toString());
    expect(event.fundValue).to.equal((100e18).toString());
    expect(event.totalSupply).to.equal((100e18 - fundTokensWithdrawn).toString());
  });

  it('should be able to manage pool', async function () {
    await poolFactory.createFund(
      true,
      manager.address,
      'Barren Wuffet',
      'Test Fund',
      'DHTF',
      new ethers.BigNumber.from('5000'),
      [susd, seth],
    );

    let deployedFundsLength = await poolFactory.deployedFundsLength();
    let fundAddress = await poolFactory.deployedFunds(deployedFundsLength - 1);
    let poolLogicPrivateProxy = await PoolLogic.attach(fundAddress);
    let poolManagerLogicPrivateProxy = await PoolManagerLogic.attach(await poolLogicPrivateProxy.poolManagerLogic());

    const IERC20 = await hre.artifacts.readArtifact('IERC20');
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let transferFromABI = iERC20.encodeFunctionData('transferFrom', [
      logicOwner.address,
      poolLogicPrivateProxy.address,
      (100e18).toString(),
    ]);
    await susdProxy.givenMethodReturnBool(transferFromABI, true);

    // Can't deposit when not being a member
    await expect(poolLogicPrivateProxy.deposit(susd, (100e18).toString())).to.be.revertedWith('only members allowed');

    await expect(poolManagerLogicPrivateProxy.addMember(logicOwner.address)).to.be.revertedWith('only manager');

    let poolLogicPrivateManagerProxy = poolLogicPrivateProxy.connect(manager);
    let poolManagerLogicPrivateManagerProxy = poolManagerLogicPrivateProxy.connect(manager);

    // Can deposit after being a member
    await poolManagerLogicPrivateManagerProxy.addMember(logicOwner.address);

    await poolLogicPrivateProxy.deposit(susd, (100e18).toString());

    // Can't deposit after being removed from a member
    await poolManagerLogicPrivateManagerProxy.removeMember(logicOwner.address);

    await expect(poolLogicPrivateProxy.deposit(susd, (100e18).toString())).to.be.revertedWith('only members allowed');

    // Can set trader
    await expect(poolManagerLogicPrivateProxy.setTrader(user1.address)).to.be.revertedWith('only manager');

    await poolManagerLogicPrivateManagerProxy.setTrader(user1.address);

    // Can remove trader
    await expect(poolManagerLogicPrivateProxy.removeTrader()).to.be.revertedWith('only manager');

    await poolManagerLogicPrivateManagerProxy.removeTrader();

    it('should be able to manage assets', async function() {
        await expect(poolManagerLogicProxy.changeAssets([[slink, false]], []))
            .to.be.revertedWith('only manager or trader');

    await expect(poolManagerLogicPrivateProxy.changeManager(logicOwner.address, 'Logic Owner')).to.be.revertedWith(
      'only manager',
    );
  });

        // Can add asset
        await poolManagerLogicManagerProxy.changeAssets([[slink, false]], [])

    let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);
    let poolManagerLogicUser1Proxy = poolManagerLogicProxy.connect(user1);

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

    await expect(poolManagerLogicManagerProxy.removeFromSupportedAssets(slink)).to.be.revertedWith(
      'revert cannot remove non-empty asset',
    );

        expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.false;
        expect(await poolManagerLogicProxy.numberOfDepositAssets()).to.be.equal(2);
        await poolManagerLogicManagerProxy.changeAssets([[slink, true]], []);
        expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.true;
        expect(await poolManagerLogicProxy.numberOfDepositAssets()).to.be.equal(3);
        await poolManagerLogicManagerProxy.changeAssets([], [[slink, true]])
        expect(await poolManagerLogicProxy.isDepositAsset(slink)).to.be.false;
        expect(await poolManagerLogicProxy.numberOfDepositAssets()).to.be.equal(2);
        await poolManagerLogicManagerProxy.changeAssets([], [[slink, false]])
    });

    it('should be able to manage fees', async function() {
        //Can't set manager fee if not manager or if fee too high
        await expect(poolManagerLogicProxy.announceManagerFeeIncrease(4000))
            .to.be.revertedWith('only manager');

  it('should be able to manage fees', async function () {
    //Can't set manager fee if not manager or if fee too high
    await expect(poolManagerLogicProxy.announceManagerFeeIncrease(fundAddress, 4000)).to.be.revertedWith(
      'only manager',
    );

        await expect(poolManagerLogicManagerProxy.announceManagerFeeIncrease(6100))
            .to.be.revertedWith('exceeded allowed increase');

        //Can set manager fee
        await poolManagerLogicManagerProxy.announceManagerFeeIncrease(4000)

        await expect(poolManagerLogicManagerProxy.commitManagerFeeIncrease())
            .to.be.revertedWith('fee increase delay active');

    await expect(poolManagerLogicManagerProxy.commitManagerFeeIncrease(fundAddress)).to.be.revertedWith(
      'fee increase delay active',
    );

        await poolManagerLogicManagerProxy.commitManagerFeeIncrease()

        let [managerFeeNumerator, managerFeeDenominator] = await poolManagerLogicManagerProxy.getManagerFee()
        expect(managerFeeNumerator.toString()).to.equal('4000');
        expect(managerFeeDenominator.toString()).to.equal('10000');
    });

    // Synthetix transaction guard
    it("Only manager or trader can execute transaction", async () => {
        await expect(poolLogicProxy.connect(logicOwner).execTransaction(synthetix.address, "0x00000000"))
            .to.be.revertedWith('only manager or trader');
    });

    it("Should fail with invalid destination", async () => {
        await expect(poolLogicProxy.connect(manager).execTransaction(poolManagerLogicProxy.address, "0x00000000"))
            .to.be.revertedWith("invalid destination");
    });

    it("Should exec transaction", async () => {
        let poolLogicManagerProxy = poolLogicProxy.connect(manager);

  it('Should exec transaction', async () => {
    let poolManagerLogicManagerProxy = poolManagerLogicProxy.connect(manager);

    let exchangeEvent = new Promise((resolve, reject) => {
      synthetixGuard.on('Exchange', (managerLogicAddress, sourceAsset, sourceAmount, destinationAsset, time, event) => {
        event.removeListener();

        resolve({
          managerLogicAddress: managerLogicAddress,
          sourceAsset: sourceAsset,
          sourceAmount: sourceAmount,
          destinationAsset: destinationAsset,
          time: time,
        });
      });

      setTimeout(() => {
        reject(new Error('timeout'));
      }, 60000);
    });

    const sourceKey = susdKey;
    const sourceAmount = (100e18).toString();
    const destinationKey = sethKey;
    const daoAddress = await poolFactory.getDaoAddress();
    const trackingCode = await poolFactory.getTrackingCode();

        await synthetix.givenCalldataRevert(exchangeWithTrackingABI);
        
        await expect(poolLogicManagerProxy.execTransaction(synthetix.address, exchangeWithTrackingABI))
            .to.be.revertedWith("failed to execute the call");

        await synthetix.givenCalldataReturnUint(exchangeWithTrackingABI, 1e18.toString())
        await poolLogicManagerProxy.execTransaction(synthetix.address, exchangeWithTrackingABI);

    await expect(
      poolManagerLogicManagerProxy.execTransaction(synthetix.address, exchangeWithTrackingABI),
    ).to.be.revertedWith('failed to execute the call');

    it('Should be able to approve', async () => {
        const IERC20 = await hre.artifacts.readArtifact("IERC20");
        const iERC20 = new ethers.utils.Interface(IERC20.abi);
        let approveABI = iERC20.encodeFunctionData("approve", [susd, 100e18.toString()]);
        await expect(poolLogicProxy.connect(manager).execTransaction(slink, approveABI)).to.be.revertedWith("invalid destination or asset not supported");

        await expect(poolLogicProxy.connect(manager).execTransaction(susd, approveABI)).to.be.revertedWith("unsupported spender approval");

        approveABI = iERC20.encodeFunctionData("approve", [uniswapV2Router.address, 100e18.toString()]);
        await susdAsset.givenCalldataReturnBool(approveABI, true);
        await poolLogicProxy.connect(manager).execTransaction(susd, approveABI);
    })

    it("should be able to swap tokens on uniswap.", async () => {
        let exchangeEvent = new Promise((resolve, reject) => {
            uniswapV2Guard.on('Exchange', (
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

        const sourceAmount = 100e18.toString();
        const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
        const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
        let swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [susd, seth], poolManagerLogicProxy.address, 0]);

        await expect(poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI)).to.be.revertedWith("non-zero address is required");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [slink, seth], poolLogicProxy.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(susd, swapABI)).to.be.revertedWith("invalid transaction");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [slink, seth], poolLogicProxy.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith("unsupported source asset");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [susd, user1.address, seth], poolLogicProxy.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith("invalid routing asset");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [susd, seth, slink], poolLogicProxy.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith("unsupported destination asset");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [susd, seth], user1.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith("recipient is not pool");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [susd, seth], poolLogicProxy.address, 0]);
        await uniswapV2Router.givenCalldataRevert(swapABI);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI)).to.be.revertedWith("failed to execute the call");

        await uniswapV2Router.givenCalldataReturn(swapABI, []);
        await poolLogicProxy.connect(manager).execTransaction(uniswapV2Router.address, swapABI);

        let event = await exchangeEvent;
        expect(event.sourceAsset).to.equal(susd);
        expect(event.sourceAmount).to.equal(100e18.toString());
        expect(event.destinationAsset).to.equal(seth);
    });
    
    it("should be able to pause deposit, exchange/execute and withdraw", async function() {
        let poolLogicManagerProxy = poolLogicProxy.connect(manager);

        await expect(poolFactory.pause()).to.be.revertedWith("only dao");
        await poolFactory.connect(dao).pause();
        expect(await poolFactory.isPaused()).to.be.true;

        await expect(poolLogicProxy.deposit(susd, 100e18.toString())).to.be.revertedWith("contracts paused");
        await expect(poolLogicProxy.withdraw(100e18.toString())).to.be.revertedWith("contracts paused");
        await expect(poolLogicManagerProxy.execTransaction(synthetix.address, "0x00")).to.be.revertedWith("contracts paused");

        await expect(poolFactory.unpause()).to.be.revertedWith("only dao");
        await poolFactory.connect(dao).unpause();
        expect(await poolFactory.isPaused()).to.be.false;

        await expect(poolLogicProxy.deposit(susd, 100e18.toString())).to.not.be.revertedWith("contracts paused");
        await expect(poolLogicProxy.withdraw(100e18.toString())).to.not.be.revertedWith("contracts paused");
        await expect(poolLogicManagerProxy.execTransaction(synthetix.address, "0x00")).to.not.be.revertedWith("contracts paused");
    })

    it('should be able to upgrade/set implementation logic', async function() {
        await poolFactory.setLogic(ZERO_ADDRESS, ZERO_ADDRESS)

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(susd);
    expect(event.sourceAmount).to.equal((100e18).toString());
    expect(event.destinationAsset).to.equal(seth);
  });

  it('should be able to upgrade/set implementation logic', async function () {
    await poolFactory.setLogic(ZERO_ADDRESS, ZERO_ADDRESS);

    let poolManagerLogicAddress = await poolFactory.getLogic(1);
    expect(poolManagerLogicAddress).to.equal(ZERO_ADDRESS);

    let poolLogicAddress = await poolFactory.getLogic(2);
    expect(poolLogicAddress).to.equal(ZERO_ADDRESS);
  });
});
