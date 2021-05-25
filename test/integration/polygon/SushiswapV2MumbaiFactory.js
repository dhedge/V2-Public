const { expect, use } = require('chai');
const chaiAlmost = require('chai-almost');

use(chaiAlmost());

const checkAlmostSame = (a, b) => {
  expect(ethers.BigNumber.from(a).gt(ethers.BigNumber.from(b).mul(99).div(100))).to.be.true;
  expect(ethers.BigNumber.from(a).lt(ethers.BigNumber.from(b).mul(101).div(100))).to.be.true;
};

const units = (value) => ethers.utils.parseUnits(value.toString());

const sushiswapV2Router = '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506';

// For Mumbai
const wmatic = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270';
const weth = '0x8e07dAfa396B1b2B226367D0266e009cA1B3248d';
const usdc = '0x624429a012a8A935cc1110A9880B2d698587a744';
const usdt = '0x5C03614553fF7b57C7dd583377c2e756D0408940';
const eth_price_feed = '0xF9680D99D6C9589e2a93a78A04A279e509205945';
const usdc_price_feed = '0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7';
const usdt_price_feed = '0x0A6513e40db6EB1b165753AD52E80663aeA50545';
const poolFactoryAddress = '0x91956c1098B047721686Bd831185ddB042b08684';

describe('Sushiswap V2 Test Mumbai Fork', function () {
  let WMatic, WETH, USDC, USDT;
  let logicOwner, manager, dao, user;
  let PoolFactory, PoolLogic, PoolManagerLogic;
  let poolFactory, poolLogic, poolManagerLogic, poolLogicProxy, poolManagerLogicProxy, fundAddress;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    PoolFactory = await ethers.getContractFactory('PoolFactory');
    poolFactory = await PoolFactory.attach(poolFactoryAddress);

    PoolLogic = await ethers.getContractFactory('PoolLogic');
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

    await poolFactory.createFund(
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
    console.log('deployed fund length', deployedFundsLength);

    console.log('pool address', fundAddress);
    let isPool = await poolFactory.isPool(fundAddress);
    poolLogicProxy = await PoolLogic.attach(fundAddress);
    expect(isPool).to.be.true;
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

    // let totalFundValue = await poolLogicProxy.totalFundValue();
    // expect(totalFundValue.toString()).to.equal('0');

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

  //   it('Should be able to approve', async () => {
  //     const IERC20 = await hre.artifacts.readArtifact(
  //       '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol:IERC20',
  //     );
  //     const iERC20 = new ethers.utils.Interface(IERC20.abi);
  //     let approveABI = iERC20.encodeFunctionData('approve', [usdc, (10e6).toString()]);
  //     await expect(poolLogicProxy.connect(manager).execTransaction(usdt, approveABI)).to.be.revertedWith(
  //       'asset not enabled in pool',
  //     );

  //     await expect(poolLogicProxy.connect(manager).execTransaction(usdc, approveABI)).to.be.revertedWith(
  //       'unsupported spender approval',
  //     );

  //     approveABI = iERC20.encodeFunctionData('approve', [sushiswapV2Router, (10e6).toString()]);
  //     await poolLogicProxy.connect(manager).execTransaction(usdc, approveABI);
  //   });

  //   it('should be able to swap tokens on sushiswap.', async () => {
  //     let exchangeEvent = new Promise((resolve, reject) => {
  //       uniswapV2Guard.on('Exchange', (managerLogicAddress, sourceAsset, sourceAmount, destinationAsset, time, event) => {
  //         event.removeListener();

  //         resolve({
  //           managerLogicAddress: managerLogicAddress,
  //           sourceAsset: sourceAsset,
  //           sourceAmount: sourceAmount,
  //           destinationAsset: destinationAsset,
  //           time: time,
  //         });
  //       });

  //       setTimeout(() => {
  //         reject(new Error('timeout'));
  //       }, 60000);
  //     });

  //     const sourceAmount = (10e6).toString();
  //     const IUniswapV2Router = await hre.artifacts.readArtifact('IUniswapV2Router');
  //     const iSushiswapV2Router = new ethers.utils.Interface(IUniswapV2Router.abi);
  //     let swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
  //       sourceAmount,
  //       0,
  //       [usdc, weth],
  //       poolManagerLogicProxy.address,
  //       0,
  //     ]);

  //     await expect(
  //       poolLogicProxy.connect(manager).execTransaction('0x0000000000000000000000000000000000000000', swapABI),
  //     ).to.be.revertedWith('non-zero address is required');

  //     swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
  //       sourceAmount,
  //       0,
  //       [usdt, weth],
  //       poolLogicProxy.address,
  //       0,
  //     ]);
  //     await expect(poolLogicProxy.connect(manager).execTransaction(usdc, swapABI)).to.be.revertedWith(
  //       'invalid transaction',
  //     );

  //     swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
  //       sourceAmount,
  //       0,
  //       [usdt, weth],
  //       poolLogicProxy.address,
  //       0,
  //     ]);
  //     await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
  //       'unsupported source asset',
  //     );

  //     swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
  //       sourceAmount,
  //       0,
  //       [usdc, user.address, weth],
  //       poolLogicProxy.address,
  //       0,
  //     ]);
  //     await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
  //       'invalid routing asset',
  //     );

  //     swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
  //       sourceAmount,
  //       0,
  //       [usdc, weth, usdt],
  //       poolLogicProxy.address,
  //       0,
  //     ]);
  //     await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
  //       'unsupported destination asset',
  //     );

  //     swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
  //       sourceAmount,
  //       0,
  //       [usdc, weth],
  //       user.address,
  //       0,
  //     ]);
  //     await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
  //       'recipient is not pool',
  //     );

  //     swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
  //       sourceAmount,
  //       0,
  //       [usdc, weth],
  //       poolLogicProxy.address,
  //       0,
  //     ]);
  //     await expect(poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI)).to.be.revertedWith(
  //       'failed to execute the call',
  //     );

  //     swapABI = iSushiswapV2Router.encodeFunctionData('swapExactTokensForTokens', [
  //       sourceAmount,
  //       0,
  //       [usdc, weth],
  //       poolLogicProxy.address,
  //       Math.floor(Date.now() / 1000 + 100000000),
  //     ]);
  //     await poolLogicProxy.connect(manager).execTransaction(sushiswapV2Router, swapABI);

  //     expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(0);

  //     let event = await exchangeEvent;
  //     expect(event.sourceAsset).to.equal(usdc);
  //     expect(event.sourceAmount).to.equal((10e6).toString());
  //     expect(event.destinationAsset).to.equal(weth);
  //   });

  //   it('should be able to withdraw', async function () {
  //     let withdrawalEvent = new Promise((resolve, reject) => {
  //       poolLogicProxy.on(
  //         'Withdrawal',
  //         (
  //           fundAddress,
  //           investor,
  //           valueWithdrawn,
  //           fundTokensWithdrawn,
  //           totalInvestorFundTokens,
  //           fundValue,
  //           totalSupply,
  //           time,
  //           event,
  //         ) => {
  //           event.removeListener();

  //           resolve({
  //             fundAddress: fundAddress,
  //             investor: investor,
  //             valueWithdrawn: valueWithdrawn,
  //             fundTokensWithdrawn: fundTokensWithdrawn,
  //             totalInvestorFundTokens: totalInvestorFundTokens,
  //             fundValue: fundValue,
  //             totalSupply: totalSupply,
  //             time: time,
  //           });
  //         },
  //       );

  //       setTimeout(() => {
  //         reject(new Error('timeout'));
  //       }, 60000);
  //     });

  //     // Withdraw 50%
  //     let withdrawAmount = units(5);

  //     await expect(poolLogicProxy.withdraw(withdrawAmount)).to.be.revertedWith('cooldown active');

  //     ethers.provider.send('evm_increaseTime', [3600 * 24]); // add 1 day

  //     await poolLogicProxy.withdraw(withdrawAmount);

  //     let event = await withdrawalEvent;
  //     expect(event.fundAddress).to.equal(poolLogicProxy.address);
  //     expect(event.investor).to.equal(logicOwner.address);
  //     checkAlmostSame(event.valueWithdrawn, units(5));
  //     checkAlmostSame(event.fundTokensWithdrawn, units(5));
  //     checkAlmostSame(event.totalInvestorFundTokens, units(5));
  //     checkAlmostSame(event.fundValue, units(5));
  //     checkAlmostSame(event.totalSupply, units(5));
  //   });
});
