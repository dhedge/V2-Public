const { expect, use } = require('chai');
const chaiAlmost = require('chai-almost');

use(chaiAlmost());

const checkAlmostSame = (a, b) => {
  expect(ethers.BigNumber.from(a).gt(ethers.BigNumber.from(b).mul(99).div(100))).to.be.true;
  expect(ethers.BigNumber.from(a).lt(ethers.BigNumber.from(b).mul(101).div(100))).to.be.true;
};

const units = (value) => ethers.utils.parseUnits(value.toString());

const sushiswapV2Router = '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506';

// For mumbai testnet
const weth = '0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa';
const usdc = '0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e';
const usdt = '0x3813e82e6f7098b9583FC0F33a962D02018B6803';
const eth_price_feed = '0x0715A7794a1dc8e42615F059dD6e406A6594651A';
const usdc_price_feed = '0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0';
const usdt_price_feed = '0x92C09849638959196E976289418e5973CC96d645';

describe('Sushiswap V2 Test Mumbai', function () {
  let WMatic, WETH, USDC, USDT;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory('AssetHandler');
    const assetHandlerLogic = await AssetHandlerLogic.deploy();

    PoolLogic = await ethers.getContractFactory('PoolLogic');
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory('PoolManagerLogic');
    poolManagerLogic = await PoolManagerLogic.deploy();

    PoolFactory = await ethers.getContractFactory('PoolFactory');
    poolFactory = await PoolFactory.deploy();

    // Deploy ProxyAdmin
    const ProxyAdmin = await ethers.getContractFactory('ProxyAdmin');
    const proxyAdmin = await ProxyAdmin.deploy();
    await proxyAdmin.deployed();

    // Deploy AssetHandlerProxy
    const AssetHandlerProxy = await ethers.getContractFactory('OZProxy');
    const assetHandlerProxy = await AssetHandlerProxy.deploy(assetHandlerLogic.address, manager.address, '0x');
    await assetHandlerProxy.deployed();

    const assetHandler = await AssetHandlerLogic.attach(assetHandlerProxy.address);

    // Deploy PoolFactoryProxy
    const PoolFactoryProxy = await ethers.getContractFactory('OZProxy');
    poolFactory = await PoolFactoryProxy.deploy(poolFactory.address, manager.address, '0x');
    await poolFactory.deployed();

    // Initialize Asset Price Consumer
    const assetWeth = { asset: weth, assetType: 0, aggregator: eth_price_feed };
    const assetUsdt = { asset: usdt, assetType: 0, aggregator: usdt_price_feed };
    const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
    const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];

    await assetHandler.initialize(poolFactory.address, assetHandlerInitAssets);
    await assetHandler.deployed();

    //set higher timeout value for testnet
    await assetHandler.setChainlinkTimeout(10000000);

    poolFactory = await PoolFactory.attach(poolFactory.address);
    await poolFactory.initialize(poolLogic.address, poolManagerLogic.address, assetHandlerProxy.address, dao.address);
    await poolFactory.deployed();

    const ERC20Guard = await ethers.getContractFactory('ERC20Guard');
    erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    const UniswapV2Guard = await ethers.getContractFactory('UniswapV2Guard');
    uniswapV2Guard = await UniswapV2Guard.deploy();
    uniswapV2Guard.deployed();

    await poolFactory.connect(dao).setAssetGuard(0, erc20Guard.address);
    await poolFactory.connect(dao).setContractGuard(sushiswapV2Router, uniswapV2Guard.address);
  });

  it('Should be able to createFund', async function () {
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
        reject(new Error('timeout'));
      }, 60000);
    });

    await expect(
      poolFactory.createFund(
        false,
        manager.address,
        'Barren Wuffet',
        'Test Fund',
        'DHTF',
        new ethers.BigNumber.from('6000'),
        [
          [usdc, true],
          [weth, true],
        ],
      ),
    ).to.be.revertedWith('invalid fraction');

    let tx = await poolFactory.createFund(
      false,
      manager.address,
      'Barren Wuffet',
      'Test Fund',
      'DHTF',
      new ethers.BigNumber.from('5000'),
      [
        [usdc, true],
        [weth, true],
      ],
    );

    let event = await fundCreatedEvent;

    fundAddress = event.fundAddress;
    expect(event.isPoolPrivate).to.be.false;
    expect(event.fundName).to.equal('Test Fund');
    // expect(event.fundSymbol).to.equal("DHTF");
    expect(event.managerName).to.equal('Barren Wuffet');
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
    expect(await poolManagerLogicProxy.numberOfSupportedAssets()).to.equal('2');
    expect(await poolManagerLogicProxy.isSupportedAsset(usdc)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(weth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(usdt)).to.be.false;
  });

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

    let totalFundValue = await poolLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal('0');

    await expect(poolLogicProxy.deposit(usdt, (10e6).toString())).to.be.revertedWith('invalid deposit asset');

    const IERC20 = await hre.artifacts.readArtifact(
      '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol:IERC20',
    );
    USDC = await ethers.getContractAt(IERC20.abi, usdc);
    await USDC.approve(poolLogicProxy.address, (10e6).toString());
    await poolLogicProxy.deposit(usdc, (10e6).toString());
    let event = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, units(10));
    checkAlmostSame(event.fundTokensReceived, units(10));
    checkAlmostSame(event.totalInvestorFundTokens, units(10));
    checkAlmostSame(event.fundValue, units(10));
    checkAlmostSame(event.totalSupply, units(10));
  });

  it('Should be able to approve', async () => {
    const IERC20 = await hre.artifacts.readArtifact(
      '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol:IERC20',
    );
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData('approve', [usdc, (10e6).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(usdt, approveABI)).to.be.revertedWith(
      'asset not enabled in pool',
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, approveABI)).to.be.revertedWith(
      'unsupported spender approval',
    );

    approveABI = iERC20.encodeFunctionData('approve', [sushiswapV2Router, (10e6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
  });

  it('should be able to swap tokens on sushiswap.', async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      uniswapV2Guard.on('Exchange', (managerLogicAddress, sourceAsset, sourceAmount, destinationAsset, time, event) => {
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

    const sourceAmount = (10e6).toString();
    const IUniswapV2Router = await hre.artifacts.readArtifact('IUniswapV2Router');
    const iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
    let swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
      sourceAmount,
      0,
      [usdc, weth],
      poolManagerLogicProxy.address,
      0,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction('0x0000000000000000000000000000000000000000', swapABI),
    ).to.be.revertedWith('non-zero address is required');

    swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
      sourceAmount,
      0,
      [usdt, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(usdc, swapABI)).to.be.revertedWith(
      'invalid transaction',
    );

    swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
      sourceAmount,
      0,
      [usdt, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      'unsupported source asset',
    );

    swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
      sourceAmount,
      0,
      [usdc, user.address, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      'invalid routing asset',
    );

    swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
      sourceAmount,
      0,
      [usdc, weth, usdt],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      'unsupported destination asset',
    );

    swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
      sourceAmount,
      0,
      [usdc, weth],
      user.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      'recipient is not pool',
    );

    swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
      sourceAmount,
      0,
      [usdc, weth],
      poolLogicProxy.address,
      0,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
      'failed to execute the call',
    );

    swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
      sourceAmount,
      0,
      [usdc, weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI);

    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(0);

    let event = await exchangeEvent;
    expect(event.sourceAsset).to.equal(usdc);
    expect(event.sourceAmount).to.equal((10e6).toString());
    expect(event.destinationAsset).to.equal(weth);
  });

  it('should be able to withdraw', async function () {
    let withdrawalEvent = new Promise((resolve, reject) => {
      poolLogicProxy.on(
        'Withdrawal',
        (
          fundAddress,
          investor,
          valueWithdrawn,
          fundTokensWithdrawn,
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

    // Withdraw 50%
    let withdrawAmount = units(5);

    await expect(poolLogicProxy.withdraw(withdrawAmount)).to.be.revertedWith('cooldown active');

    ethers.provider.send('evm_increaseTime', [3600 * 24]); // add 1 day

    await poolLogicProxy.withdraw(withdrawAmount);

    let event = await withdrawalEvent;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueWithdrawn, units(5));
    checkAlmostSame(event.fundTokensWithdrawn, units(5));
    checkAlmostSame(event.totalInvestorFundTokens, units(5));
    checkAlmostSame(event.fundValue, units(5));
    checkAlmostSame(event.totalSupply, units(5));
  });
});
