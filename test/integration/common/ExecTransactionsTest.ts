import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { IERC20, IERC20__factory, PoolLogic } from "../../../types";
import { createFund } from "../utils/createFund";
import { deployContracts, NETWORK } from "../utils/deployContracts/deployContracts";
import { getAccountToken } from "../utils/getAccountTokens";
import { getOneInchSwapTransaction } from "../utils/oneInchHelpers";
import { utils } from "../utils/utils";
import { units } from "../../testHelpers";
import { expect } from "chai";

interface IexecTransactionsTestParams {
  oneInchRouterAddress: string;
  network: NETWORK;
  usdc: {
    address: string;
  };
  usdt: {
    address: string;
    balanceOfSlot: number;
  };
  weth: {
    address: string;
  };
}

const networkToChainIdMap: Record<NETWORK, 137 | 10> = {
  polygon: 137,
  ovm: 10,
};

export const execTransactionsTest = ({
  oneInchRouterAddress,
  network,
  usdc,
  usdt,
  weth,
}: IexecTransactionsTestParams) => {
  describe("execTransactions Test", () => {
    const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
    const usdcAddress = usdc.address;
    const usdtAddress = usdt.address;
    const amount = units(4200, 6);
    const approveTxData = iERC20.encodeFunctionData("approve", [oneInchRouterAddress, amount]);

    let snapId: string;
    let USDC: IERC20;
    let USDT: IERC20;
    let WETH: IERC20;
    let signer: SignerWithAddress;
    let manager: SignerWithAddress;
    let poolLogicProxy: PoolLogic;

    before(async () => {
      snapId = await utils.evmTakeSnap();
      [signer, manager] = await ethers.getSigners();
      const deployments = await deployContracts(network);
      const poolFactory = deployments.poolFactory;
      USDC = deployments.assets.USDC;
      USDT = deployments.assets.USDT;
      WETH = deployments.assets.WETH;
      await getAccountToken(amount, signer.address, usdtAddress, usdt.balanceOfSlot);
      const fund = await createFund(poolFactory, signer, manager, [
        { asset: usdcAddress, isDeposit: false },
        { asset: usdtAddress, isDeposit: true },
      ]);
      poolLogicProxy = fund.poolLogicProxy;
      await USDT.approve(poolLogicProxy.address, amount);
      await poolLogicProxy.deposit(usdtAddress, amount);
    });

    after(async () => {
      await utils.evmRestoreSnap(snapId);
    });

    // Approve USDT for 1inch + swap USDT -> USDC via 1inch
    it("Should execute multiple transactions correctly", async () => {
      const oneInchUsdtAllowanceBefore = await USDT.allowance(poolLogicProxy.address, oneInchRouterAddress);
      expect(oneInchUsdtAllowanceBefore).to.equal("0");
      const poolUsdcBalanceBefore = await USDC.balanceOf(poolLogicProxy.address);
      expect(poolUsdcBalanceBefore).to.equal("0");

      const srcAmount = units(1000, 6);
      const amountFromLeft = amount.sub(srcAmount);
      const swapTxData = await getOneInchSwapTransaction({
        srcAsset: usdtAddress,
        dstAsset: usdcAddress,
        srcAmount,
        fromAddress: poolLogicProxy.address,
        toAddress: poolLogicProxy.address,
        chainId: networkToChainIdMap[network],
      });

      await poolLogicProxy.connect(manager).execTransactions([
        { to: usdtAddress, data: approveTxData },
        { to: oneInchRouterAddress, data: swapTxData },
      ]);

      const oneInchUsdtAllowanceAfter = await USDT.allowance(poolLogicProxy.address, oneInchRouterAddress);
      expect(oneInchUsdtAllowanceAfter).to.equal(amountFromLeft);
      const poolUsdtBalanceAfter = await USDT.balanceOf(poolLogicProxy.address);
      expect(poolUsdtBalanceAfter).to.equal(amountFromLeft);
      const poolUsdcBalanceAfter = await USDC.balanceOf(poolLogicProxy.address);
      expect(poolUsdcBalanceAfter).to.be.closeTo(srcAmount, srcAmount.div(1000));
    });

    // Approve USDC for 1inch + swap USDC -> WETH via 1inch
    it("Should revert if one of transactions failed", async () => {
      const oneInchUsdcAllowanceBefore = await USDC.allowance(poolLogicProxy.address, oneInchRouterAddress);
      expect(oneInchUsdcAllowanceBefore).to.equal("0");
      const poolWethBalanceBefore = await WETH.balanceOf(poolLogicProxy.address);
      expect(poolWethBalanceBefore).to.equal("0");

      const swapTxData = await getOneInchSwapTransaction({
        srcAsset: usdcAddress,
        dstAsset: weth.address,
        srcAmount: units(900, 6),
        fromAddress: poolLogicProxy.address,
        toAddress: poolLogicProxy.address,
        chainId: networkToChainIdMap[network],
      });

      await expect(
        poolLogicProxy.connect(manager).execTransactions([
          { to: usdcAddress, data: approveTxData },
          { to: oneInchRouterAddress, data: swapTxData },
        ]),
      ).to.be.revertedWith("unsupported destination asset");
      const oneInchUsdcAllowanceAfter = await USDC.allowance(poolLogicProxy.address, oneInchRouterAddress);
      expect(oneInchUsdcAllowanceAfter).to.equal("0");
      const poolWethBalanceAfter = await WETH.balanceOf(poolLogicProxy.address);
      expect(poolWethBalanceAfter).to.equal("0");
    });
  });
};
