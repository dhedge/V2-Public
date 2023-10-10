import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract, ContractFactory } from "ethers";
import fs from "fs";
import { artifacts, ethers } from "hardhat";
import { units } from "../../testHelpers";
import { getAccountToken } from "../utils/getAccountTokens";
import { ovmChainData } from "../../../config/chainData/ovmData";

import { checkAlmostSame } from "../../testHelpers";
import { IVersions } from "../../../deployment/types";
import { utils } from "../utils/utils";

const { assets, synthetix: SynthetixData } = ovmChainData;

const versions: IVersions = JSON.parse(fs.readFileSync("./publish/ovm/prod/versions.json", "utf-8"));

describe("Synthetix Test", function () {
  let susdProxy: Contract, sethProxy: Contract, synthetix: Contract, synthetixGuard: Contract;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let PoolFactory: ContractFactory, PoolLogic: ContractFactory, PoolManagerLogic: ContractFactory;
  let poolFactory: Contract, poolLogicProxy: Contract, poolManagerLogicProxy: Contract, fundAddress: string;

  let snapId: string;

  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async function () {
    snapId = await utils.evmTakeSnap();
    [logicOwner, manager] = await ethers.getSigners();
    const ISynthAddressProxy = await artifacts.readArtifact("ISynthAddressProxy");
    susdProxy = await ethers.getContractAt(ISynthAddressProxy.abi, assets.susd);
    sethProxy = await ethers.getContractAt(ISynthAddressProxy.abi, assets.seth);

    await getAccountToken(
      units(500),
      logicOwner.address,
      SynthetixData.sUSDProxy_target_tokenState,
      ovmChainData.assetsBalanceOfSlot.susd,
    );
    expect(await susdProxy.balanceOf(logicOwner.address)).to.equal(units(500));

    const ISynthetix = await artifacts.readArtifact("contracts/interfaces/synthetix/ISynthetix.sol:ISynthetix");
    synthetix = await ethers.getContractAt(ISynthetix.abi, assets.snxProxy);

    PoolFactory = await ethers.getContractFactory("PoolFactory");
    PoolLogic = await ethers.getContractFactory("PoolLogic");
    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");

    const firstVersion = versions[Object.keys(versions)[0]];

    const poolFactoryProxyAddress = firstVersion.contracts.PoolFactoryProxy;
    const synthetixGuardAddress = firstVersion.contracts.SynthetixGuard;
    if (!poolFactoryProxyAddress || !synthetixGuardAddress) {
      throw Error("Missing Address");
    }
    const ISynthetixGuard = await artifacts.readArtifact("SynthetixGuard");
    synthetixGuard = await ethers.getContractAt(ISynthetixGuard.abi, synthetixGuardAddress);

    poolFactory = PoolFactory.attach(poolFactoryProxyAddress);
  });

  it("Should be able to createFund", async function () {
    const fundCreatedEvent = new Promise((resolve, reject) => {
      poolFactory.on(
        "FundCreated",
        (
          fundAddress,
          isPoolPrivate,
          fundName,
          managerName,
          manager,
          time,
          performanceFeeNumerator,
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
            performanceFeeNumerator: performanceFeeNumerator,
            managerFeeNumerator: managerFeeNumerator,
            managerFeeDenominator: managerFeeDenominator,
          });
        },
      );

      setTimeout(() => {
        reject(new Error("timeout"));
      }, 60000);
    });

    await poolFactory.createFund(
      false,
      manager.address,
      "Barren Wuffet",
      "Test Fund",
      "DHTF",
      ethers.BigNumber.from("5000"),
      ethers.constants.Zero,
      [
        [assets.susd, true],
        [assets.seth, true],
      ],
    );

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await fundCreatedEvent;

    fundAddress = event.fundAddress;
    expect(event.isPoolPrivate).to.be.false;
    expect(event.fundName).to.equal("Test Fund");

    expect(event.managerName).to.equal("Barren Wuffet");
    expect(event.manager).to.equal(manager.address);
    expect(event.performanceFeeNumerator.toString()).to.equal("5000");
    expect(event.managerFeeDenominator.toString()).to.equal("10000");

    const deployedFunds = await poolFactory.getDeployedFunds();
    const deployedFundsLength = deployedFunds.length;
    expect(deployedFundsLength.toString()).to.equal("1");

    const isPool = await poolFactory.isPool(fundAddress);
    expect(isPool).to.be.true;

    poolLogicProxy = PoolLogic.attach(fundAddress);
    const poolManagerLogicProxyAddress = await poolLogicProxy.poolManagerLogic();
    poolManagerLogicProxy = PoolManagerLogic.attach(poolManagerLogicProxyAddress);

    //default assets are supported
    const supportedAssets = await poolManagerLogicProxy.getSupportedAssets();
    const numberOfSupportedAssets = supportedAssets.length;
    expect(numberOfSupportedAssets).to.eq(2);
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.susd)).to.be.true;
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.seth)).to.be.true;

    //Other assets are not supported
    expect(await poolManagerLogicProxy.isSupportedAsset(assets.slink)).to.be.false;
  });

  it("should be able to deposit", async function () {
    const depositEvent = new Promise((resolve, reject) => {
      poolLogicProxy.on(
        "Deposit",
        (
          fundAddress,
          investor,
          assetDeposited,
          amountDeposited,
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
            assetDeposited: assetDeposited,
            amountDeposited: amountDeposited,
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
        reject(new Error("timeout"));
      }, 60000);
    });

    const totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(assets.slink, (100e18).toString())).to.be.revertedWith("invalid deposit asset");

    await susdProxy.approve(poolLogicProxy.address, (100e18).toString());
    await poolLogicProxy.deposit(assets.susd, (100e18).toString());

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, (100e18).toString());
    checkAlmostSame(event.fundTokensReceived, (100e18).toString());
    checkAlmostSame(event.totalInvestorFundTokens, (100e18).toString());
    checkAlmostSame(event.fundValue, (100e18).toString());
    checkAlmostSame(event.totalSupply, (100e18).toString());
  });

  it("Should be able to approve", async () => {
    const IERC20 = await artifacts.readArtifact("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    let approveABI = iERC20.encodeFunctionData("approve", [assets.susd, (100e18).toString()]);
    await expect(poolLogicProxy.connect(manager).execTransaction(assets.slink, approveABI)).to.be.revertedWith(
      "asset not enabled in pool",
    );

    await expect(poolLogicProxy.connect(manager).execTransaction(assets.susd, approveABI)).to.be.revertedWith(
      "unsupported spender approval",
    );

    approveABI = iERC20.encodeFunctionData("approve", [synthetix.address, (100e18).toString()]);
    await poolLogicProxy.connect(manager).execTransaction(assets.susd, approveABI);
  });

  it("should be able to swap tokens on synthetix.", async () => {
    const exchangeEvent = new Promise((resolve, reject) => {
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
    const sourceAmount = (100e18).toString();
    const destinationKey = SynthetixData.sethKey;
    const daoAddress = await poolFactory.owner();
    const trackingCode = "0x4448454447450000000000000000000000000000000000000000000000000000"; // DHEDGE

    const ISynthetix = await artifacts.readArtifact("contracts/interfaces/synthetix/ISynthetix.sol:ISynthetix");
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

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await exchangeEvent;
    expect(event.sourceAsset).to.equal(assets.susd);
    expect(event.sourceAmount).to.equal((100e18).toString());
    expect(event.destinationAsset).to.equal(assets.seth);
  });

  it("should be able to withdraw", async function () {
    const withdrawalEvent = new Promise((resolve, reject) => {
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
    const withdrawAmount = (await poolLogicProxy.totalSupply()).div(2);
    const totalFundValue = await poolManagerLogicProxy.totalFundValue();

    await ethers.provider.send("evm_increaseTime", [3600 * 24]); // add 1 day
    await ethers.provider.send("evm_mine", []);

    await poolLogicProxy.withdraw(withdrawAmount.toString());

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const event: any = await withdrawalEvent;
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueWithdrawn, totalFundValue.div(2));
    checkAlmostSame(event.fundTokensWithdrawn, withdrawAmount);
    checkAlmostSame(event.totalInvestorFundTokens, withdrawAmount);
    checkAlmostSame(event.fundValue, totalFundValue.div(2));
    checkAlmostSame(event.totalSupply, withdrawAmount);
  });
});
