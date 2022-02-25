import { ethers, artifacts, upgrades } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract, ContractFactory } from "ethers";

import { assets, price_feeds, synthetix as SynthetixData } from "./ovm-data";
import { checkAlmostSame, units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";
import { createFund } from "../utils/createFund";
import { PoolFactory, PoolFactory__factory } from "../../../types";

describe("Synthetix Test", function () {
  let susdProxy: Contract, sethProxy: Contract, synthetix: Contract, synthetixGuard: Contract;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress, dao: SignerWithAddress, user: SignerWithAddress;
  let PoolFactory: PoolFactory__factory, PoolLogic: ContractFactory, PoolManagerLogic: ContractFactory;
  let poolFactory: PoolFactory,
    poolLogic: Contract,
    poolManagerLogic: Contract,
    poolLogicProxy: Contract,
    poolManagerLogicProxy: Contract,
    fundAddress: string;

  before(async function () {
    [logicOwner, manager, dao, user] = await ethers.getSigners();

    const AssetHandlerLogic = await ethers.getContractFactory("AssetHandler");

    const Governance = await ethers.getContractFactory("Governance");
    let governance = await Governance.deploy();
    console.log("governance deployed to:", governance.address);

    const PoolPerformance = await ethers.getContractFactory("PoolPerformance");
    const poolPerformance = await upgrades.deployProxy(PoolPerformance);
    await poolPerformance.deployed();

    PoolLogic = await ethers.getContractFactory("PoolLogic");
    poolLogic = await PoolLogic.deploy();

    PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
    poolManagerLogic = await PoolManagerLogic.deploy();

    const USDPriceAggregator = await ethers.getContractFactory("USDPriceAggregator");
    const usdPriceAggregator = await USDPriceAggregator.deploy();
    console.log("USDPriceAggregator deployed at ", usdPriceAggregator.address);

    // Initialize Asset Price Consumer
    const assetSusd = { asset: assets.susd, assetType: 1, aggregator: usdPriceAggregator.address };
    const assetSeth = { asset: assets.seth, assetType: 1, aggregator: price_feeds.eth };
    const assetSlink = { asset: assets.slink, assetType: 1, aggregator: price_feeds.link };
    const assetHandlerInitAssets = [assetSusd, assetSeth, assetSlink];

    const assetHandler = await upgrades.deployProxy(AssetHandlerLogic, [assetHandlerInitAssets]);
    await assetHandler.deployed();
    await assetHandler.setChainlinkTimeout((3600 * 24 * 365).toString()); // 1 year

    PoolFactory = await ethers.getContractFactory("PoolFactory");
    poolFactory = <PoolFactory>(
      await upgrades.deployProxy(PoolFactory, [
        poolLogic.address,
        poolManagerLogic.address,
        assetHandler.address,
        dao.address,
        governance.address,
      ])
    );
    await poolFactory.deployed();
    await poolFactory.setPoolPerformanceAddress(poolPerformance.address);

    const ISynthetix = await artifacts.readArtifact("ISynthetix");
    synthetix = await ethers.getContractAt(ISynthetix.abi, assets.snxProxy);

    const SynthetixGuard = await ethers.getContractFactory("SynthetixGuard");
    synthetixGuard = await SynthetixGuard.deploy(SynthetixData.addressResolver);
    synthetixGuard.deployed();

    const ERC20Guard = await ethers.getContractFactory("ERC20Guard");
    const erc20Guard = await ERC20Guard.deploy();
    erc20Guard.deployed();

    await governance.setAssetGuard(0, erc20Guard.address);
    await governance.setAssetGuard(1, erc20Guard.address);
    await governance.setContractGuard(synthetix.address, synthetixGuard.address);

    await poolFactory.setExitFee(5, 1000); // 0.5%

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
  });

  it("should be able to deposit", async function () {
    let depositEvent = new Promise((resolve, reject) => {
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

    let totalFundValue = await poolManagerLogicProxy.totalFundValue();
    expect(totalFundValue.toString()).to.equal("0");

    await expect(poolLogicProxy.deposit(assets.slink, (100e18).toString())).to.be.revertedWith("invalid deposit asset");

    await susdProxy.approve(poolLogicProxy.address, (100e18).toString());
    await poolLogicProxy.deposit(assets.susd, (100e18).toString());
    let event: any = await depositEvent;

    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueDeposited, (100e18).toString());
    checkAlmostSame(event.fundTokensReceived, (100e18).toString());
    checkAlmostSame(event.totalInvestorFundTokens, (100e18).toString());
    checkAlmostSame(event.fundValue, (100e18).toString());
    checkAlmostSame(event.totalSupply, (100e18).toString());
  });

  it("Should be able to approve", async () => {
    const IERC20 = await artifacts.readArtifact("IERC20");
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
    const sourceAmount = (100e18).toString();
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
    expect(event.sourceAmount).to.equal((100e18).toString());
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
    console.log(event);
    expect(event.fundAddress).to.equal(poolLogicProxy.address);
    expect(event.investor).to.equal(logicOwner.address);
    checkAlmostSame(event.valueWithdrawn, totalFundValue.div(2));
    checkAlmostSame(event.fundTokensWithdrawn, withdrawAmount);
    checkAlmostSame(event.totalInvestorFundTokens, withdrawAmount);
    checkAlmostSame(event.fundValue, totalFundValue.div(2));
    checkAlmostSame(event.totalSupply, withdrawAmount);
  });
});
