import { expect } from "chai";
import { Contract, ContractFactory } from "ethers";
import { ethers } from "hardhat";
import { polygonChainData } from "../../../config/chainData/polygon-data";
import { units } from "../../TestHelpers";
import { createFund } from "../utils/createFund";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { utils } from "../utils/utils";
const { assets, assetsBalanceOfSlot } = polygonChainData;

const decimals = 6;

describe("DHedgePoolPriceOracle", function () {
  let dhedgePoolPriceOracle: Contract;
  let poolLogic: Contract;

  let snapId: string;
  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });
  before(async () => {
    snapId = await utils.evmTakeSnap();

    const [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    const poolFactory = deployments.poolFactory;
    const USDC = deployments.assets.USDC;

    await getAccountToken(units(10000, 6), logicOwner.address, assets.usdc, assetsBalanceOfSlot.usdc);

    const funds = await createFund(poolFactory, logicOwner, manager, [
      { asset: assets.usdc, isDeposit: true },
      { asset: assets.usdt, isDeposit: true },
    ]);
    poolLogic = funds.poolLogicProxy;

    // Deposit 1000 USDC
    await USDC.approve(poolLogic.address, units(1000, 6));
    await poolLogic.deposit(assets.usdc, units(1000, 6));

    const BalancerDHedgePoolPriceOracle: ContractFactory = await ethers.getContractFactory(
      "BalancerDHedgePoolPriceOracle",
    );
    dhedgePoolPriceOracle = await BalancerDHedgePoolPriceOracle.deploy(poolLogic.address, decimals);
    await dhedgePoolPriceOracle.deployed();
  });

  // Checks id pool address is set
  it("price should  be the same as token price", async () => {
    const priceFromOracle = await dhedgePoolPriceOracle.getRate();
    console.log("price from oracle ", priceFromOracle.toString());
    const tokenPrice = await poolLogic.tokenPrice();
    console.log("token Price ", tokenPrice.toString());

    expect(priceFromOracle).to.equal(tokenPrice.div(10 ** (18 - decimals)));
  });
});
