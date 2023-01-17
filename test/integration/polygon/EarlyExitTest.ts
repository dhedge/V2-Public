import { ethers } from "hardhat";
import { expect } from "chai";
import { units } from "../../TestHelpers";
import { polygonChainData } from "../../../config/chainData/polygon-data";
import { IWETH, PoolFactory, PoolLogic } from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployContracts } from "../utils/deployContracts/deployContracts";
import { createFund } from "../utils/createFund";

const { assets } = polygonChainData;

const oneDollar = units(1);

describe.skip("Early Exit Fee", function () {
  let WMATIC: IWETH;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic;

  beforeEach(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    const deployments = await deployContracts("polygon");
    poolFactory = deployments.poolFactory;

    WMATIC = await ethers.getContractAt("IWETH", assets.wmatic);

    // deposit Matic -> WMATIC
    await WMATIC.deposit({ value: units(1000) });
  });

  // Checks to make sure early exit of 100% drains all assets and does not incur fee
  // we make a conventional deposit and immediately withdraw 100% of the issued tokens
  // we then deposit again and check the token price is $1 to confirm not left over assets from previous withdraw
  // Skipped because this behaviour was backed out
  it("early 100% withdrawal should not incur fee when there is a fee", async () => {
    const funds = await createFund(poolFactory, logicOwner, manager, [{ asset: assets.wmatic, isDeposit: true }]);
    poolLogicProxy = funds.poolLogicProxy;
    // Deposit $1 conventional way
    await WMATIC.approve(poolLogicProxy.address, units(500));
    await poolLogicProxy.deposit(assets.wmatic, units(500));

    // Check token price is $1
    expect((await poolLogicProxy.tokenPrice()).toString()).to.equal(oneDollar.toString());

    await poolFactory.setExitCooldown(6000000);
    await poolFactory.setExitFee(10, 100); // 10%

    // 100% withdrawal
    const withdrawalAmount = await poolLogicProxy.totalSupply();

    await poolLogicProxy.withdraw(withdrawalAmount.toString());

    // Check token price has increased by the fee kept by the pool
    expect((await poolLogicProxy.tokenPrice()).toString()).to.equal("0");

    // We deposit again to make sure everything is reset
    await WMATIC.approve(poolLogicProxy.address, units(500));
    await poolLogicProxy.deposit(assets.wmatic, units(500));

    // Check token price is $1
    expect((await poolLogicProxy.tokenPrice()).toString()).to.equal(oneDollar.toString());
  });
});
