import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import { expect, use } from "chai";
import { units } from "../../TestHelpers";
import { assets } from "../../../config/chainData/polygon-data";
import { IWETH, PoolFactory, PoolLogic, PoolLogic__factory } from "../../../types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployPolygonContracts } from "../utils/deployContracts/deployPolygonContracts";

use(solidity);

const oneDollar = units(1);

describe.skip("Early Exit Fee", function () {
  let WMATIC: IWETH;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: PoolLogic;

  beforeEach(async function () {
    [logicOwner, manager, dao] = await ethers.getSigners();
    const deployments = await deployPolygonContracts();
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
    const managerFee = ethers.BigNumber.from("0"); // 0%;
    // Create the fund we're going to use for testing
    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      managerFee,
      ethers.BigNumber.from("0"),
      [{ asset: assets.wmatic, isDeposit: true }],
    );

    const funds = await poolFactory.getDeployedFunds();
    poolLogicProxy = await PoolLogic__factory.connect(funds[0], logicOwner);
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
