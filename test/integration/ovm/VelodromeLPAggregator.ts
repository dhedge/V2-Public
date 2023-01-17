import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";

import { ovmChainData } from "../../../config/chainData/ovm-data";
const { assets, assetsBalanceOfSlot, velodrome } = ovmChainData;
import { utils } from "../utils/utils";
import { units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";
import { PoolFactory } from "../../../types";
import { deployContracts } from "../utils/deployContracts/deployContracts";

use(solidity);

describe("Velodrome LP aggregator Test", function () {
  let snapId: string;
  let poolFactory: PoolFactory;
  before(async () => {
    snapId = await utils.evmTakeSnap();
    const deployment = await deployContracts("ovm");
    poolFactory = deployment.poolFactory;
  });

  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  it("Check lp price after huge swap (stable lp): VelodromeStableLPAggregator", async () => {
    const [owner] = await ethers.getSigners();

    const VelodromeStableLPAggregator = await ethers.getContractFactory("VelodromeStableLPAggregator");
    const velodromeLPAggregator = await VelodromeStableLPAggregator.deploy(
      velodrome.STABLE_USDC_DAI.poolAddress,
      poolFactory.address,
    ); // 5% slippage
    await velodromeLPAggregator.deployed();

    let priceBefore = (await velodromeLPAggregator.latestRoundData())[1];

    const velodromeRouter = await ethers.getContractAt("IVelodromeRouter", velodrome.router);
    const dai = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.dai);
    const usdc = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);

    // USDC/DAI stable pool has around 10M liquidity, try to swap 200K first
    let swapAmount = units(200000, 6);
    await getAccountToken(swapAmount, owner.address, usdc.address, assetsBalanceOfSlot.usdc);

    await usdc.approve(velodromeRouter.address, swapAmount);

    await velodromeRouter.swapExactTokensForTokens(
      swapAmount,
      0,
      [
        {
          from: usdc.address,
          to: dai.address,
          stable: true,
        },
      ],
      owner.address,
      ethers.constants.MaxUint256,
    );

    expect(await dai.balanceOf(owner.address)).to.gt(0);

    let priceAfter = (await velodromeLPAggregator.latestRoundData())[1];

    expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(100)); // 1% diff

    // try to swap 4M
    priceBefore = priceAfter;
    swapAmount = units(4000000, 6);
    await getAccountToken(swapAmount, owner.address, usdc.address, assetsBalanceOfSlot.usdc);
    await usdc.approve(velodromeRouter.address, swapAmount);
    await velodromeRouter.swapExactTokensForTokens(
      swapAmount,
      0,
      [
        {
          from: usdc.address,
          to: dai.address,
          stable: true,
        },
      ],
      owner.address,
      ethers.constants.MaxUint256,
    );

    priceAfter = (await velodromeLPAggregator.latestRoundData())[1];

    expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(100)); // 1% diff
  });

  it("Check lp price after huge swap (variable lp): VelodromeVariableLPAggregator", async () => {
    const [owner] = await ethers.getSigners();

    const VelodromeVariableLPAggregator = await ethers.getContractFactory("VelodromeVariableLPAggregator");
    const velodromeLPAggregator = await VelodromeVariableLPAggregator.deploy(
      velodrome.VARIABLE_VELO_USDC.poolAddress,
      poolFactory.address,
    ); // 5% slippage
    await velodromeLPAggregator.deployed();

    let priceBefore = (await velodromeLPAggregator.latestRoundData())[1];

    const velodromeRouter = await ethers.getContractAt("IVelodromeRouter", velodrome.router);
    const velo = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", velodrome.velo);
    const usdc = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", assets.usdc);

    // VELO/DAI stable pool has around 2.5M liquidity, try to swap 200K first
    let swapAmount = units(200000, 6);
    await getAccountToken(swapAmount, owner.address, usdc.address, assetsBalanceOfSlot.usdc);

    await usdc.approve(velodromeRouter.address, swapAmount);
    await velodromeRouter.swapExactTokensForTokens(
      swapAmount,
      0,
      [
        {
          from: usdc.address,
          to: velo.address,
          stable: false,
        },
      ],
      owner.address,
      ethers.constants.MaxUint256,
    );

    expect(await velo.balanceOf(owner.address)).to.gt(0);

    let priceAfter = (await velodromeLPAggregator.latestRoundData())[1];

    expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(100)); // 1% diff

    // try to swap 1M
    priceBefore = priceAfter;
    swapAmount = units(1000000, 6);
    await getAccountToken(swapAmount, owner.address, usdc.address, assetsBalanceOfSlot.usdc);
    await usdc.approve(velodromeRouter.address, swapAmount);
    await velodromeRouter.swapExactTokensForTokens(
      swapAmount,
      0,
      [
        {
          from: usdc.address,
          to: velo.address,
          stable: true,
        },
      ],
      owner.address,
      ethers.constants.MaxUint256,
    );

    priceAfter = (await velodromeLPAggregator.latestRoundData())[1];

    expect(priceBefore).to.closeTo(priceAfter, priceAfter.div(100)); // 1% diff
  });
});
