import { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame, units } from "../../../testHelpers";
import { polygonChainData } from "../../../../config/chainData/polygonData";
const { aaveV2, assets, assetsBalanceOfSlot, aaveV3 } = polygonChainData;

import {
  IAaveV3Pool__factory,
  IERC20,
  IERC20__factory,
  ILendingPool__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { deployContracts, IDeployments } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";

describe("Aave V2 & V3 Test", function () {
  let USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic, poolManagerLogicProxy: PoolManagerLogic;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iLendingPool = new ethers.utils.Interface(ILendingPool__factory.abi);
  const iAaveV3Pool = new ethers.utils.Interface(IAaveV3Pool__factory.abi);
  let deployments: IDeployments;

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();

    deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    USDC = deployments.assets.USDC;

    await getAccountToken(units(10000000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);
  });
  let snapId: string;

  afterEach(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  beforeEach(async function () {
    snapId = await utils.evmTakeSnap();
    await ethers.provider.send("evm_mine", []);
    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.weth, isDeposit: true },
      { asset: assets.usdt, isDeposit: false },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    // Deposit 3000000 USDC
    await USDC.approve(poolLogicProxy.address, units(3000000, 6));
    await poolLogicProxy.deposit(assets.usdc, units(3000000, 6));

    // add supported assets
    await poolManagerLogicProxy.connect(manager).changeAssets(
      [
        { asset: aaveV2.lendingPool, isDeposit: false },
        { asset: aaveV3.lendingPool, isDeposit: false },
        { asset: assets.dai, isDeposit: false },
      ],
      [],
    );
  });

  it("Should be able to deposit usdc: both V2, V3", async () => {
    const amount = units(1000000, 6);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    // Aave V2 Deposit (1M USDC)
    let approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    let depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    // Aave V3 Deposit (1M USDC)
    approveABI = iERC20.encodeFunctionData("approve", [aaveV3.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    depositABI = iAaveV3Pool.encodeFunctionData("supply", [assets.usdc, amount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV3.lendingPool, depositABI);

    // Check USDC balance
    expect(await USDC.balanceOf(poolLogicProxy.address)).to.be.equal(amount);
    // Check total fund value
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);
    // Check aToken balances
    const V2AMUSDC = await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
      aaveV2.aTokens.usdc,
    );
    checkAlmostSame(await V2AMUSDC.balanceOf(poolLogicProxy.address), amount);
    const V3AMUSDC = await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
      aaveV3.aTokens.usdc,
    );
    checkAlmostSame(await V3AMUSDC.balanceOf(poolLogicProxy.address), amount);
  });

  it("Should be able to borrow dai/usdc: both V2, V3", async () => {
    const amount = units(1000000, 6);

    // Aave V2 Deposit (1M USDC)
    let approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    let depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    // Aave V3 Deposit (1M USDC)
    approveABI = iERC20.encodeFunctionData("approve", [aaveV3.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    depositABI = iAaveV3Pool.encodeFunctionData("supply", [assets.usdc, amount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV3.lendingPool, depositABI);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    // Aave V2 Borrow (0.5M DAI)
    let borrowABI = iLendingPool.encodeFunctionData("borrow", [
      assets.dai,
      amount.div(2),
      2,
      0,
      poolLogicProxy.address,
    ]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI);

    // Aave V3 Borrow (0.5M USDC)
    borrowABI = iAaveV3Pool.encodeFunctionData("borrow", [assets.usdc, amount.div(2), 2, 0, poolLogicProxy.address]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV3.lendingPool, borrowABI);

    // Check total fund value
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

    // Check debtTokens balances
    const V2VariableDebtDai = await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
      aaveV2.variableDebtTokens.dai,
    );
    checkAlmostSame(await V2VariableDebtDai.balanceOf(poolLogicProxy.address), amount.div(2));
    const V3VariableDebtUsdc = await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
      aaveV3.variableDebtTokens.usdc,
    );
    checkAlmostSame(await V3VariableDebtUsdc.balanceOf(poolLogicProxy.address), amount.div(2));
  });

  it("Should be able to repay dai: both V2, V3", async () => {
    const amount = units(1000000, 6);

    // Aave V2 Deposit (1M USDC)
    let approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    let depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    // Aave V3 Deposit (1M USDC)
    approveABI = iERC20.encodeFunctionData("approve", [aaveV3.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    depositABI = iAaveV3Pool.encodeFunctionData("supply", [assets.usdc, amount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV3.lendingPool, depositABI);

    // Aave V2 Borrow (0.5M DAI)
    let borrowABI = iLendingPool.encodeFunctionData("borrow", [
      assets.dai,
      amount.div(2),
      2,
      0,
      poolLogicProxy.address,
    ]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI);

    // Aave V3 Borrow (0.5M USDC)
    borrowABI = iAaveV3Pool.encodeFunctionData("borrow", [assets.usdc, amount.div(2), 2, 0, poolLogicProxy.address]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV3.lendingPool, borrowABI);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    // Aave V2 Repay (0.25M DAI)
    approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount.div(4)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);
    let repayABI = iLendingPool.encodeFunctionData("repay", [assets.dai, amount.div(4), 2, poolLogicProxy.address]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, repayABI);

    // Aave V3 Repay (0.25M USDC)
    approveABI = iERC20.encodeFunctionData("approve", [aaveV3.lendingPool, amount.div(4)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    repayABI = iAaveV3Pool.encodeFunctionData("repay", [assets.usdc, amount.div(4), 2, poolLogicProxy.address]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV3.lendingPool, repayABI);

    // Check total fund value
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore);

    // Check debtTokens balances
    const V2VariableDebtDai = await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
      aaveV2.variableDebtTokens.dai,
    );
    checkAlmostSame(await V2VariableDebtDai.balanceOf(poolLogicProxy.address), amount.div(4));
    const V3VariableDebtUsdc = await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
      aaveV3.variableDebtTokens.usdc,
    );
    checkAlmostSame(await V3VariableDebtUsdc.balanceOf(poolLogicProxy.address), amount.div(4));
  });

  it("Should be able to withdraw after borrow/repay: both V2, V3", async () => {
    const amount = units(1000000, 6);

    // Aave V2 Deposit (1M USDC)
    let approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    let depositABI = iLendingPool.encodeFunctionData("deposit", [assets.usdc, amount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, depositABI);

    // Aave V3 Deposit (1M USDC)
    approveABI = iERC20.encodeFunctionData("approve", [aaveV3.lendingPool, amount]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    depositABI = iAaveV3Pool.encodeFunctionData("supply", [assets.usdc, amount, poolLogicProxy.address, 0]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV3.lendingPool, depositABI);

    // Aave V2 Borrow (0.5M DAI)
    let borrowABI = iLendingPool.encodeFunctionData("borrow", [
      assets.dai,
      amount.div(2),
      2,
      0,
      poolLogicProxy.address,
    ]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, borrowABI);

    // Aave V3 Borrow (0.5M USDC)
    borrowABI = iAaveV3Pool.encodeFunctionData("borrow", [assets.usdc, amount.div(2), 2, 0, poolLogicProxy.address]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV3.lendingPool, borrowABI);

    // Aave V2 Repay (0.25M DAI)
    approveABI = iERC20.encodeFunctionData("approve", [aaveV2.lendingPool, amount.div(4)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.dai, approveABI);
    let repayABI = iLendingPool.encodeFunctionData("repay", [assets.dai, amount.div(4), 2, poolLogicProxy.address]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV2.lendingPool, repayABI);

    // Aave V3 Repay (0.25M USDC)
    approveABI = iERC20.encodeFunctionData("approve", [aaveV3.lendingPool, amount.div(4)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
    repayABI = iAaveV3Pool.encodeFunctionData("repay", [assets.usdc, amount.div(4), 2, poolLogicProxy.address]);
    await poolLogicProxy.connect(manager).execTransaction(aaveV3.lendingPool, repayABI);

    const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();

    // Withdraw 50%
    const withdrawAmount = units(1500000);
    await ethers.provider.send("evm_increaseTime", [86400]);
    await poolLogicProxy.withdraw(withdrawAmount);

    // Check total fund value
    checkAlmostSame(await poolManagerLogicProxy.totalFundValue(), totalFundValueBefore.div(2));

    // Check debtTokens balances
    const V2VariableDebtDai = await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
      aaveV2.variableDebtTokens.dai,
    );
    checkAlmostSame(await V2VariableDebtDai.balanceOf(poolLogicProxy.address), amount.div(8));
    const V3VariableDebtUsdc = await ethers.getContractAt(
      "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20",
      aaveV3.variableDebtTokens.usdc,
    );
    checkAlmostSame(await V3VariableDebtUsdc.balanceOf(poolLogicProxy.address), amount.div(8));
  });
});
