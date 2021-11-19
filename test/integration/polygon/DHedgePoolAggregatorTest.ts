import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { checkAlmostSame, getAmountOut, units } from "../../TestHelpers";
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
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";
import { createFund } from "../utils/createFund";
import { getUSDC } from "../utils/getAccountTokens/polygon";
import { assets, quickswap } from "../polygon-data";

use(solidity);

describe("DHedgePoolAggregator Test", function () {
  let WMATIC: IERC20, USDC: IERC20;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress;
  let poolFactory: PoolFactory,
    poolLogicProxy: PoolLogic,
    poolManagerLogicProxy: PoolManagerLogic,
    dhedgePoolAggregator: DHedgePoolAggregator;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iQuickswapRouter = new ethers.utils.Interface(IUniswapV2Router__factory.abi);

  before(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();
    const deployments = await deployPolygonContracts();
    poolFactory = deployments.poolFactory;
    USDC = deployments.assets.USDC;
    WMATIC = deployments.assets.WMATIC;

    await getUSDC(units(10000, 6));

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

    await poolFactory.setExitCooldown(0);
    await poolLogicProxy.withdraw(withdrawAmount);

    const [, answer] = await dhedgePoolAggregator.latestRoundData();
    checkAlmostSame(answer, units(1, 8));
  });
});
