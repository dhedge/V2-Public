const { expect, use } = require("chai");
const chaiAlmost = require('chai-almost');

use(chaiAlmost());

const checkAlmostSame = (a, b) => {
    expect(ethers.BigNumber.from(a).gt(ethers.BigNumber.from(b).mul(95).div(100))).to.be.true;
    expect(ethers.BigNumber.from(a).lt(ethers.BigNumber.from(b).mul(105).div(100))).to.be.true;
}

const uniswapV2Factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
const uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

// For mainnet
const weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const usdt = "0xdac17f958d2ee523a2206206994597c13d831ec7";
const eth_price_feed = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
const usdt_price_feed = "0x3E7d1eAB13ad0104d2750B8863b489D65364e32D";
const usdc_price_feed = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6";

describe("Uniswap V2 Test", function() {
    let WETH, USDC, USDT, UniswapRouter;
    let logicOwner, manager, dao, user;
    let PoolFactory, PoolLogic, PoolManagerLogic;
    let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;
    
    before(async function(){
        [logicOwner, manager, dao, user] = await ethers.getSigners();

        const AssetHandlerLogic = await ethers.getContractFactory('AssetHandler');
        const assetHandlerLogic = await AssetHandlerLogic.deploy();

        PoolLogic = await ethers.getContractFactory("PoolLogic");
        poolLogic = await PoolLogic.deploy();

        PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
        poolManagerLogic = await PoolManagerLogic.deploy();

        PoolFactory = await ethers.getContractFactory("PoolFactory");
        poolFactory = await PoolFactory.deploy();

        // Deploy ProxyAdmin
        const ProxyAdmin = await ethers.getContractFactory('ProxyAdmin');
        const proxyAdmin = await ProxyAdmin.deploy();
        await proxyAdmin.deployed();

        // Deploy AssetHandlerProxy
        const AssetHandlerProxy = await ethers.getContractFactory('OZProxy');
        const assetHandlerProxy = await AssetHandlerProxy.deploy(assetHandlerLogic.address, proxyAdmin.address, '0x');
        await assetHandlerProxy.deployed();

        const assetHandler = await AssetHandlerLogic.attach(assetHandlerProxy.address);

        // Deploy PoolFactoryProxy
        const PoolFactoryProxy = await ethers.getContractFactory('OZProxy');
        poolFactory = await PoolFactoryProxy.deploy(poolFactory.address, proxyAdmin.address, "0x");
        await poolFactory.deployed();

        // Initialize Asset Price Consumer
        const assetWeth = { asset: weth, assetType: 0, aggregator: eth_price_feed };
        const assetUsdt = { asset: usdt, assetType: 0, aggregator: usdt_price_feed };
        const assetUsdc = { asset: usdc, assetType: 0, aggregator: usdc_price_feed };
        const assetHandlerInitAssets = [assetWeth, assetUsdt, assetUsdc];
    
        await assetHandler.initialize(poolFactory.address, assetHandlerInitAssets);
        await assetHandler.deployed();
        await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year expiry
    
        poolFactory = await PoolFactory.attach(poolFactory.address);
        await poolFactory.initialize(poolLogic.address, poolManagerLogic.address, assetHandlerProxy.address, dao.address);
        await poolFactory.deployed();

        const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
        erc20Guard = await ERC20Guard.deploy();
        erc20Guard.deployed();

        const UniswapV2Guard = await ethers.getContractFactory("UniswapV2Guard");
        uniswapV2Guard = await UniswapV2Guard.deploy();
        uniswapV2Guard.deployed();

        await poolFactory.connect(dao).setAssetGuard(0, erc20Guard.address);
        await poolFactory.connect(dao).setContractGuard(uniswapV2Router, uniswapV2Guard.address);
    });

    it("Should be able to get WETH", async function() {
        const IWETH = await hre.artifacts.readArtifact("IWETH");
        WETH = await ethers.getContractAt(IWETH.abi, weth);
        const IERC20 = await hre.artifacts.readArtifact("@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol:IERC20");
        USDT = await ethers.getContractAt(IERC20.abi, usdt);
        USDC = await ethers.getContractAt(IERC20.abi, usdc);
        const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
        UniswapRouter = await ethers.getContractAt(IUniswapV2Router.abi, uniswapV2Router);
        // deposit ETH -> WETH
        await WETH.deposit({ value: 5e18.toString() });
        // WETH -> USDT
        await WETH.approve(uniswapV2Router, 5e18.toString());
        await UniswapRouter.swapExactTokensForTokens(5e18.toString(), 0, [weth, usdc], logicOwner.address, Math.floor(Date.now() / 1000 + 100000000));
    });

    it("Should be able to createFund", async function() {
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

        await expect(poolFactory.createFund(
            false, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('6000'), [[usdc, true], [weth, true]]
        ))
            .to.be.revertedWith('invalid fraction');

        await poolFactory.createFund(
            false, manager.address, 'Barren Wuffet', 'Test Fund', "DHTF", new ethers.BigNumber.from('5000'), [[usdc, true], [weth, true]]
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

        let deployedFunds = await poolFactory.getDeployedFunds()
        let deployedFundsLength = deployedFunds.length;
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
        let supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
        let numberOfSupportedAssets = supportedAssets.length;
        expect(numberOfSupportedAssets).to.eq(2);
        expect(await poolManagerLogicProxy.isSupportedAsset(usdc)).to.be.true
        expect(await poolManagerLogicProxy.isSupportedAsset(weth)).to.be.true

        //Other assets are not supported
        expect(await poolManagerLogicProxy.isSupportedAsset(usdt)).to.be.false

    });

    it('should be able to deposit', async function() {
        let depositEvent = new Promise((resolve, reject) => {
            poolLogicProxy.on('Deposit', (fundAddress,
                investor,
                assetDeposited,
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
                        assetDeposited: assetDeposited,
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

        let totalFundValue = await poolManagerLogicProxy.totalFundValue();
        expect(totalFundValue.toString()).to.equal('0');

        await expect(poolLogicProxy.deposit(usdt, 100e6.toString())).to.be.revertedWith("invalid deposit asset");

        await USDC.approve(poolLogicProxy.address, 100e6.toString());
        await poolLogicProxy.deposit(usdc, 100e6.toString());
        let event = await depositEvent;

        expect(event.fundAddress).to.equal(poolLogicProxy.address);
        expect(event.investor).to.equal(logicOwner.address);
        checkAlmostSame(event.valueDeposited, 100e18.toString());
        checkAlmostSame(event.fundTokensReceived, 100e18.toString());
        checkAlmostSame(event.totalInvestorFundTokens, 100e18.toString());
        checkAlmostSame(event.fundValue, 100e18.toString());
        checkAlmostSame(event.totalSupply, 100e18.toString());
    });

    it('Should be able to approve', async () => {
        const IERC20 = await hre.artifacts.readArtifact("@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol:IERC20");
        const iERC20 = new ethers.utils.Interface(IERC20.abi);
        let approveABI = iERC20.encodeFunctionData("approve", [usdc, 100e6.toString()]);
        await expect(poolLogicProxy.connect(manager).execTransaction(usdt, approveABI)).to.be.revertedWith("asset not enabled in pool");

        await expect(poolLogicProxy.connect(manager).execTransaction(usdc, approveABI)).to.be.revertedWith("unsupported spender approval");

        approveABI = iERC20.encodeFunctionData("approve", [uniswapV2Router, 100e6.toString()]);
        await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
    });


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

        const sourceAmount = 100e6.toString();
        const IUniswapV2Router = await hre.artifacts.readArtifact("IUniswapV2Router");
        const iUniswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
        let swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [usdc, weth], poolManagerLogicProxy.address, 0]);

        await expect(poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI)).to.be.revertedWith("non-zero address is required");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [usdt, weth], poolLogicProxy.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(usdc, swapABI)).to.be.revertedWith("invalid transaction");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [usdt, weth], poolLogicProxy.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith("unsupported source asset");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [usdc, user.address, weth], poolLogicProxy.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith("invalid routing asset");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [usdc, weth, usdt], poolLogicProxy.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith("unsupported destination asset");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [usdc, weth], user.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith("recipient is not pool");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [usdc, weth], poolLogicProxy.address, 0]);
        await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI)).to.be.revertedWith("failed to execute the call");

        swapABI = iUniswapV2Router.encodeFunctionData("swapExactTokensForTokens", [sourceAmount, 0, [usdc, weth], poolLogicProxy.address, Math.floor(Date.now() / 1000 + 100000000)]);
        await poolLogicProxy.connect(manager).execTransaction(uniswapV2Router, swapABI);

        expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(0);

        let event = await exchangeEvent;
        expect(event.sourceAsset).to.equal(usdc);
        expect(event.sourceAmount).to.equal(100e6.toString());
        expect(event.destinationAsset).to.equal(weth);
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

        await expect(poolLogicProxy.withdraw(withdrawAmount.toString()))
            .to.be.revertedWith('cooldown active');

        ethers.provider.send("evm_increaseTime", [3600 * 24])   // add 1 day

        await poolLogicProxy.withdraw(withdrawAmount.toString())

        let event = await withdrawalEvent;
        expect(event.fundAddress).to.equal(poolLogicProxy.address);
        expect(event.investor).to.equal(logicOwner.address);
        checkAlmostSame(event.valueWithdrawn, 50e18.toString());
        checkAlmostSame(event.fundTokensWithdrawn, 50e18.toString());
        checkAlmostSame(event.totalInvestorFundTokens, 50e18.toString());
        checkAlmostSame(event.fundValue, 50e18.toString());
        checkAlmostSame(event.totalSupply, 50e18.toString());
    });
});
