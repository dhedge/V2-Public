import { ethers, artifacts } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";

import { PoolFactory } from "../../../types";
import { assets, synthetix as SynthetixData } from "../../../config/chainData/ovm-data";
import { checkAlmostSame, units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";
import { createFund } from "../utils/createFund";
import { deployContracts, IDeployments } from "../utils/deployContracts";

describe("Synthetix Test", function () {
  let deployments: IDeployments;
  let susdProxy: Contract, sethProxy: Contract, synthetix: Contract, synthetixGuard: Contract;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: Contract, poolManagerLogicProxy: Contract;

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    deployments = await deployContracts("ovm");

    poolFactory = deployments.poolFactory;
    synthetixGuard = deployments.synthetixGuard!;

    const ISynthetix = await artifacts.readArtifact("ISynthetix");
    synthetix = await ethers.getContractAt(ISynthetix.abi, assets.snxProxy);

    const ISynthAddressProxy = await artifacts.readArtifact("ISynthAddressProxy");
    susdProxy = await ethers.getContractAt(ISynthAddressProxy.abi, assets.susd);
    sethProxy = await ethers.getContractAt(ISynthAddressProxy.abi, assets.seth);

    const sUSDProxy_target_tokenState = "0x92bac115d89ca17fd02ed9357ceca32842acb4c2";
    await getAccountToken(units(500), logicOwner.address, sUSDProxy_target_tokenState, 3);
    expect(await susdProxy.balanceOf(logicOwner.address)).to.equal(units(500));
    const fund = await createFund(
      poolFactory,
      logicOwner,
      manager,
      [
        { asset: assets.susd, isDeposit: true },
        { asset: assets.seth, isDeposit: true },
      ],
      0,
    );
    poolLogicProxy = fund.poolLogicProxy;
    poolManagerLogicProxy = fund.poolManagerLogicProxy;

    await susdProxy.approve(poolLogicProxy.address, units(500));
    await poolLogicProxy.deposit(assets.susd, units(500));
  });

  it("Should be able to approve", async () => {
    const IERC20 = await artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [assets.susd, units(100)]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.slink, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.susd, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [synthetix.address, units(100)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.susd, approveABI);
  });

  it("should be able to swap tokens on synthetix.", async () => {
    let exchangeEvent = new Promise((resolve, reject) => {
      synthetixGuard.on(
        "ExchangeFrom",
        (managerLogicAddress, sourceAsset, sourceAmount, destinationAsset, time, event) => {
          event.removeListener();

          resolve({
            managerLogicAddress: managerLogicAddress,
            sourceAsset: sourceAsset,
            sourceAmount: sourceAmount,
            destinationAsset: destinationAsset,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 600000);
    });

    const sourceKey = SynthetixData.susdKey;
    const sourceAmount = units(100);
    const destinationKey = SynthetixData.sethKey;
    const daoAddress = await poolFactory.owner();
    const trackingCode = "0x4448454447450000000000000000000000000000000000000000000000000000"; // DHEDGE

    const ISynthetix = await artifacts.readArtifact("ISynthetix");
    const iSynthetix = new ethers.utils.Interface(ISynthetix.abi);
    let swapABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      destinationKey,
      daoAddress,
      trackingCode,
    ]);

    await expect(
      poolLogicProxy.connect(manager).execTransaction("0x0000000000000000000000000000000000000000", swapABI),
    ).to.be.revertedWith("non-zero address is required");

    await expect(poolLogicProxy.connect(manager).execTransaction(synthetix.address, "0xaaaaaaaa")).to.be.revertedWith(
      "invalid transaction",
    );

    swapABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      SynthetixData.slinkKey,
      daoAddress,
      trackingCode,
    ]);
    await expect(poolLogicProxy.connect(manager).execTransaction(synthetix.address, swapABI)).to.be.revertedWith(
      "unsupported destination asset",
    );

    swapABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      destinationKey,
      daoAddress,
      trackingCode,
    ]);

    await poolLogicProxy.connect(manager).execTransaction(synthetix.address, swapABI);
    expect(await sethProxy.balanceOf(poolLogicProxy.address)).to.be.gt(0);

    let event: any = await exchangeEvent;
    expect(event.sourceAsset).to.equal(assets.susd);
    expect(event.sourceAmount).to.equal(units(100));
    expect(event.destinationAsset).to.equal(assets.seth);
  });

  it("should be able to withdraw", async function () {
    let withdrawalEvent = new Promise((resolve, reject) => {
      poolLogicProxy.on(
        "Withdrawal",
        (
          fundAddress,
          investor,
          valueWithdrawn,
          fundTokensWithdrawn,
          totalInvestorFundTokens,
          fundValue,
          totalSupply,
          withdrawnAssets,
          time,
          event,
        ) => {
          event.removeListener();

          resolve({
            fundAddress: fundAddress,
            investor: investor,
            valueWithdrawn: valueWithdrawn,
            fundTokensWithdrawn: fundTokensWithdrawn,
            totalInvestorFundTokens: totalInvestorFundTokens,
            fundValue: fundValue,
            totalSupply: totalSupply,
            withdrawnAssets: withdrawnAssets,
            time: time,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    // Withdraw 50%
    let withdrawAmount = (await poolLogicProxy.totalSupply()).div(2);
    const totalFundValue = await poolManagerLogicProxy.totalFundValue();

    await ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day
    await ethers.provider.send("evm_mine", []);

    await poolLogicProxy.withdraw(withdrawAmount.toString());

    let event: any = await withdrawalEvent;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueWithdrawn, totalFundValue.div(2));
    checkAlmostSame(event.fundTokensWithdrawn, withdrawAmount);
    checkAlmostSame(event.totalInvestorFundTokens, withdrawAmount);
    checkAlmostSame(event.fundValue, totalFundValue.div(2));
    checkAlmostSame(event.totalSupply, withdrawAmount);
  });
});
