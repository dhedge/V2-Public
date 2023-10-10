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
} from "../../../types";
import { ovmChainData } from "../../../config/chainData/ovmData";
import { checkAlmostSame, units } from "../../testHelpers";
import { getAccountToken } from "../utils/getAccountTokens";
import { createFund } from "../utils/createFund";
import { deployContracts, IDeployments } from "../utils/deployContracts/deployContracts";
import { getMinAmountOut } from "../utils/getMinAmountOut";
import { utils } from "../utils/utils";

const { assets, synthetix: SynthetixData, uniswapV3 } = ovmChainData;

describe("Synthetix Test", function () {
  let deployments: IDeployments;
  let susdProxy: ISynthAddressProxy,
    sethProxy: ISynthAddressProxy,
    synthetix: ISynthetix,
    synthetixGuard: SynthetixGuard;
  let logicOwner: SignerWithAddress, manager: SignerWithAddress;
  let poolFactory: PoolFactory, poolLogicProxy: Contract, poolManagerLogicProxy: Contract;
  const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
  const iSynthetix = new ethers.utils.Interface(ISynthetix__factory.abi);
  const IV3SwapRouter = new ethers.utils.Interface(IV3SwapRouter__factory.abi);

  let snapId: string;

  after(async () => {
    await utils.evmRestoreSnap(snapId);
  });

  before(async function () {
    snapId = await utils.evmTakeSnap();
    [logicOwner, manager] = await ethers.getSigners();
    deployments = await deployContracts("ovm");

    poolFactory = deployments.poolFactory;
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    synthetixGuard = deployments.synthetixGuard!;

    synthetix = <ISynthetix>(
      await ethers.getContractAt("contracts/interfaces/synthetix/ISynthetix.sol:ISynthetix", assets.snxProxy)
    );
    susdProxy = await ethers.getContractAt("ISynthAddressProxy", assets.susd);
    sethProxy = await ethers.getContractAt("ISynthAddressProxy", assets.seth);
  });

  beforeEach(async function () {
    await getAccountToken(
      units(500),
      logicOwner.address,
      SynthetixData.sUSDProxy_target_tokenState,
      ovmChainData.assetsBalanceOfSlot.susd,
    );
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
      SynthetixData.sinrKey,
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

  // TODO: Explore why 2% slippage is not enough for this test.
  it("should be able to swap snx on uniswap.", async () => {
    await deployments.slippageAccumulator.setMaxCumulativeSlippage(10e4); // Setting max cumulative slippage impact to 10%.

    // swap susd -> snx
    let approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(500)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.susd, approveABI);
    let srcAsset: string = assets.susd;
    let sourceAmount = units(300);
    let dstAsset: string = assets.snxProxy;
    let minAmountOut = await getMinAmountOut(deployments.assetHandler, sourceAmount, srcAsset, dstAsset, 96);
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
    minAmountOut = await getMinAmountOut(deployments.assetHandler, sourceAmount, srcAsset, dstAsset, 96);
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
    const approveABI = iERC20.encodeFunctionData("approve", [ethers.Wallet.createRandom().address, units(500)]);
    await expect(poolLogicProxy.connect(manager).execTransaction(uniswapV3.router, approveABI)).to.revertedWith(
      "unsupported spender approval",
    );
  });

  it("try: invalid contract guard & valid asset guard.", async () => {
    const approveABI = iERC20.encodeFunctionData("approve", [uniswapV3.router, units(500)]);
    await poolLogicProxy.connect(manager).execTransaction(assets.snxProxy, approveABI);
  });

  it("should be able to withdraw after synthetix swap", async function () {
    const IERC20 = await artifacts.readArtifact("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");
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
      // adfjsdfslkjl
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
