import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract } from "ethers";
import { artifacts, ethers } from "hardhat";

import { ovmChainData } from "../../../config/chainData/ovmData";
import { IERC20, PoolFactory } from "../../../types";
import { units } from "../../testHelpers";
import { createFund } from "../utils/createFund";
import { deployContracts, IDeployments } from "../utils/deployContracts/deployContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { utils } from "../utils/utils";

const synthRedeemerAddress = ovmChainData.synthetix.synthRedeemer;
const sLINKAddress = ovmChainData.assets.slink;
const depositAmount = units(1000, 18);

describe("SynthRedemeerGuardTest", () => {
  let deployments: IDeployments;
  let manager: SignerWithAddress, logicOwner: SignerWithAddress;
  let poolFactory: PoolFactory;
  let sLINK: IERC20, sUSD: IERC20 | undefined;
  let sUSDAddress: string;
  let synthRedeemerContract: Contract;
  let redeemAllsLINKTxData: string;

  utils.beforeAfterReset(before, after);
  utils.beforeAfterReset(beforeEach, afterEach);

  before(async () => {
    deployments = await deployContracts("ovm");
    manager = deployments.manager;
    logicOwner = deployments.logicOwner;
    poolFactory = deployments.poolFactory;
    sUSD = deployments.assets.SUSD;
    sUSDAddress = sUSD?.address ?? ethers.constants.AddressZero;
    sLINK = <IERC20>await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", sLINKAddress);

    const synthRedeemerArtifact = await artifacts.readArtifact("ISynthRedeemer");
    synthRedeemerContract = await ethers.getContractAt(synthRedeemerArtifact.abi, synthRedeemerAddress);
    redeemAllsLINKTxData = synthRedeemerContract.interface.encodeFunctionData("redeemAll", [[sLINKAddress]]);

    const SynthRedeemerGuard = await ethers.getContractFactory("SynthRedeemerContractGuard");
    const synthRedeemerGuard = await SynthRedeemerGuard.deploy(sUSDAddress);
    await synthRedeemerGuard.deployed();
    await deployments.governance.setContractGuard(synthRedeemerAddress, synthRedeemerGuard.address);
  });

  it("can redeem deprecated synth into sUSD", async () => {
    // Create a pool with sUSD and sLINK enabled
    const { poolLogicProxy } = await createFund(poolFactory, logicOwner, manager, [
      {
        asset: sLINKAddress,
        isDeposit: true,
      },
      {
        asset: sUSDAddress,
        isDeposit: true,
      },
    ]);

    // Deposit sLINK into the pool
    await getAccountToken(depositAmount, logicOwner.address, ovmChainData.synthetix.sLINKProxy_target_tokenState, 3);
    await sLINK.approve(poolLogicProxy.address, depositAmount);
    await poolLogicProxy.deposit(sLINKAddress, depositAmount);

    const sUSDBalanceBefore = await sUSD?.balanceOf(poolLogicProxy.address);
    const sLINKBalanceBefore = await sLINK.balanceOf(poolLogicProxy.address);
    expect(sUSDBalanceBefore).to.equal(0);
    expect(sLINKBalanceBefore).to.equal(depositAmount);

    await poolLogicProxy.connect(manager).execTransaction(synthRedeemerAddress, redeemAllsLINKTxData);

    const sUSDBalanceAfter = await sUSD?.balanceOf(poolLogicProxy.address);
    const sLINKBalanceAfter = await sLINK.balanceOf(poolLogicProxy.address);
    expect(sUSDBalanceAfter).to.be.gt(0);
    expect(sLINKBalanceAfter).to.equal(0);
  });

  it("can't use other functions", async () => {
    const { poolLogicProxy } = await createFund(poolFactory, logicOwner, manager, [
      {
        asset: sLINKAddress,
        isDeposit: true,
      },
    ]);
    await expect(
      poolLogicProxy
        .connect(manager)
        .execTransaction(
          synthRedeemerAddress,
          synthRedeemerContract.interface.encodeFunctionData("redeem", [sLINKAddress]),
        ),
    ).to.be.revertedWith("invalid transaction");
  });

  it("can't redeem when sUSD is not enabled in the pool", async () => {
    const { poolLogicProxy } = await createFund(poolFactory, logicOwner, manager, [
      {
        asset: sLINKAddress,
        isDeposit: true,
      },
    ]);
    await expect(
      poolLogicProxy.connect(manager).execTransaction(synthRedeemerAddress, redeemAllsLINKTxData),
    ).to.be.revertedWith("susd must be enabled asset");
  });

  it("reverts if pool doesn't have deprecated synths' balance in portfolio", async () => {
    const { poolLogicProxy } = await createFund(poolFactory, logicOwner, manager, [
      {
        asset: sLINKAddress,
        isDeposit: true,
      },
      {
        asset: sUSDAddress,
        isDeposit: true,
      },
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction(synthRedeemerAddress, redeemAllsLINKTxData),
    ).to.be.revertedWith("No balance of synth to redeem");
  });
});
