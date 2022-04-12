import { ethers, artifacts } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";

import {
  IERC20__factory,
  ISynthAddressProxy,
  ISynthetix,
  ISynthetix__factory,
  IV3SwapRouter__factory,
  PoolFactory,
  SynthetixGuard,
  UniswapV3RouterGuard,
} from "../../../types";
import { assets, synthetix as SynthetixData, uniswapV3 } from "../../../config/chainData/ovm-data";
import { checkAlmostSame, units } from "../../TestHelpers";
import { getAccountToken } from "../utils/getAccountTokens";
import { createFund } from "../utils/createFund";
import { deployContracts, IDeployments } from "../utils/deployContracts";
import { getMinAmountOut } from "../utils/getMinAmountOut";

describe("Synthetix Test", function () {
  let deployments: IDeployments;
  let susdProxy: ISynthAddressProxy,
    sethProxy: ISynthAddressProxy,
    synthetix: ISynthetix,
    synthetixGuard: SynthetixGuard,
    uniswapV3RouterGuard: UniswapV3RouterGuard;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: Contract, poolManagerLogicProxy: Contract;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iSynthetix = new ethers.utils.Interface(ISynthetix__factory.abi);
  const IV3SwapRouter = new ethers.utils.Interface(IV3SwapRouter__factory.abi);

  before(async function () {
    [logicOwner, manager] = await ethers.getSigners();
    deployments = await deployContracts("ovm");

    poolFactory = deployments.poolFactory;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    synthetixGuard = deployments.synthetixGuard!;
    uniswapV3RouterGuard = deployments.uniswapV3RouterGuard;

    synthetix = await ethers.getContractAt("ISynthetix", assets.snxProxy);
    susdProxy = await ethers.getContractAt("ISynthAddressProxy", assets.susd);
    sethProxy = await ethers.getContractAt("ISynthAddressProxy", assets.seth);
  });

  beforeEach(async function () {
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
        { asset: assets.snxProxy, isDeposit: false },
      ],
      {
        performance: ethers.BigNumber.from("0"),
        management: ethers.BigNumber.from("0"),
      },
    );
    poolLogicProxy = fund.poolLogicProxy;
    poolManagerLogicProxy = fund.poolManagerLogicProxy;

    await susdProxy.approve(poolLogicProxy.address, units(500));
    await poolLogicProxy.deposit(assets.susd, units(500));
  });

  it("should be able to swap tokens on synthetix.", async () => {
    const approveABI = iERC20.encodeFunctionData("approve", [synthetix.address, units(100)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.susd, approveABI);

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
    const sourceAmount = units(100);
    const destinationKey = SynthetixData.sethKey;
    const daoAddress = await poolFactory.owner();
    const trackingCode = "0x4448454447450000000000000000000000000000000000000000000000000000"; // DHEDGE

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
    expect(event.sourceAmount).to.equal(units(100));
    expect(event.destinationAsset).to.equal(assets.seth);
  });

  it("should be able to swap snx on uniswap.", async () => {
    await uniswapV3RouterGuard.setSlippageLimit(500, 1000);

    // swap susd -> snx
    let approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(500)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.susd, approveABI);
    let srcAsset = assets.susd;
    let sourceAmount = units(300);
    let dstAsset = assets.snxProxy;
    let minAmountOut = await getMinAmountOut(deployments.assetHandler, sourceAmount, srcAsset, dstAsset, 60);
    let exactInputSingleCalldata = IV3SwapRouter.encodeFunctionData("exactInputSingle", [
      [
        srcAsset, // from
        dstAsset, // to
        10000, // 1% fee
        poolLogicProxy.address,
        sourceAmount,
        minAmountOut,
        0,
      ],
    ]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactInputSingleCalldata);

    // swap snx -> susd
    approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(500)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.snxProxy, approveABI);
    srcAsset = assets.snxProxy;
    sourceAmount = minAmountOut;
    dstAsset = assets.susd;
    minAmountOut = await getMinAmountOut(deployments.assetHandler, sourceAmount, srcAsset, dstAsset, 60);
    exactInputSingleCalldata = IV3SwapRouter.encodeFunctionData("exactInputSingle", [
      [
        srcAsset, // from
        dstAsset, // to
        10000, // 1% fee
        poolLogicProxy.address,
        sourceAmount,
        minAmountOut,
        0,
      ],
    ]);
    await poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, exactInputSingleCalldata);
  });

  it("try: invalid contract guard & no asset guard.", async () => {
    const approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(500)]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, approveABI)).to.revertedWith(
      "invalid transaction",
    );
  });

  it("try: invalid contract guard & valid asset guard.", async () => {
    const approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(500)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.snxProxy, approveABI);
  });

  it("should be able to withdraw after synthetix swap", async function () {
    const IERC20 = await artifacts.readArtifact("IERC20");
    const iERC20 = new ethers.utils.Interface(IERC20.abi);
    const approveABI = iERC20.encodeFunctionData("approve", [synthetix.address, units(100)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.susd, approveABI);
    const sourceKey = SynthetixData.susdKey;
    const sourceAmount = units(100);
    const destinationKey = SynthetixData.sethKey;
    const daoAddress = await poolFactory.owner();
    const trackingCode = "0x4448454447450000000000000000000000000000000000000000000000000000"; // DHEDGE
    const swapABI = iSynthetix.encodeFunctionData("exchangeWithTracking", [
      sourceKey,
      sourceAmount,
      destinationKey,
      daoAddress,
      trackingCode,
    ]);
    await poolLogicProxy.connect(manager).execTransaction(synthetix.address, swapABI);

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
