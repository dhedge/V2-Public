import { ethers } from "hardhat";
import { expect } from "chai";
import { checkAlmostSame, getAmountOut, units } from "../../testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  DHedgePoolAggregator,
  IERC20,
  IERC20__factory,
  IUniswapV2Router__factory,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
} from "../../../types";
import { createFund } from "../utils/createFund";
import { polygonChainData } from "../../../config/chainData/polygonData";
const { quickswap, assets, assetsBalanceOfSlot } = polygonChainData;
import { getAccountToken } from "../utils/getAccountTokens";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { utils } from "../utils/utils";

describe("DHedgePoolAggregator Test", function () {
  let USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory,
    poolLogicProxy: PoolLogic,
    poolManagerLogicProxy: PoolManagerLogic,
    dhedgePoolAggregator: DHedgePoolAggregator;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iQuickswapRouter = new ethers.utils.Interface(IUniswapV2Router__factory.abi);

  let snapId: string;
  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async () => {
    snapId = await utils.evmTakeSnap();

    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;
    USDC = deployments.assets.USDC;

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.usdt, isDeposit: true },
    ]);
    poolLogicProxy = funds.poolLogicProxy;
    poolManagerLogicProxy = funds.poolManagerLogicProxy;

    const DHedgePoolAggregator = await ethers.getContractFactory("DHedgePoolAggregator");
    dhedgePoolAggregator = await DHedgePoolAggregator.deploy(poolLogicProxy.address);
    await dhedgePoolAggregator.deployed();

    let [, answer] = await dhedgePoolAggregator.latestRoundData();
    expect(answer).to.equal(0);

    // Deposit 1000 USDC
    await USDC.approve(poolLogicProxy.address, units(1000, 6));
    await poolLogicProxy.deposit(assets.usdc, units(1000, 6));

    [, answer] = await dhedgePoolAggregator.latestRoundData();
    checkAlmostSame(answer, units(1, 8));
  });

  it("Approve 750 USDC", async () => {
    const approveABI = iERC20.encodeFunctionData("approve", [quickswap.router, units(750, 6).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.usdc, approveABI);
  });

  it("Swap 750 USDC to WETH", async () => {
    await poolManagerLogicProxy.connect(manager).changeAssets([{ asset: assets.weth, isDeposit: false }], []);

    const sourceAmount = units(750, 6);
    const swapABI = iQuickswapRouter.encodeFunctionData("swapExactTokensForTokens", [
      sourceAmount,
      await getAmountOut(quickswap.router, sourceAmount, [assets.usdc, assets.weth]),
      [assets.usdc, assets.weth],
      poolLogicProxy.address,
      Math.floor(Date.now() / 1000 + 100000000),
    ]);
    await poolLogicProxy.connect(manager).execTransaction(quickswap.router, swapABI);

    checkAlmostSame(await USDC.balanceOf(poolLogicProxy.address), units(250, 6));

    const [, answer] = await dhedgePoolAggregator.latestRoundData();
    checkAlmostSame(answer, units(1, 8));
  });

  it("withdraw 20%", async function () {
    const withdrawAmount = units(200);

    await ethers.provider.send("evm_increaseTime", [86400]);
    await poolLogicProxy.withdraw(withdrawAmount);

    const [, answer] = await dhedgePoolAggregator.latestRoundData();
    checkAlmostSame(answer, units(1, 8));
  });
});
