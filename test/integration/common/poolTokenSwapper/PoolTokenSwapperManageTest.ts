import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";

import { depositAssetToPool, getPoolTokenSwapperConfig } from "./PoolTokenSwapperHelpers";
import { NETWORK } from "../../utils/deployContracts/deployContracts";
import { utils, ChainIds } from "../../utils/utils";
import { getAccountToken } from "../../utils/getAccountTokens";
import { getOneInchSwapTransaction } from "../../utils/oneInchHelpers";
import { units } from "../../../testHelpers";
import {
  PoolTokenSwapper,
  PoolFactory,
  IERC20Extended,
  IERC20__factory,
  DhedgeEasySwapper__factory,
  PoolLogic__factory,
} from "../../../../types";

type AssetType = "pool" | "asset";

export interface PTSChainData {
  assets: {
    usdc: string;
    weth: string;
    dai: string;
  };
  oneinch: {
    v5Router: string;
  };
}

export interface PoolTokenSwapperManageTestParameters {
  network: NETWORK;
  chainData: PTSChainData;
  poolFactory: string;
  easySwapper: string;
  assetHandler: string;
  assets: {
    name: string;
    type: AssetType;
    address: string;
    balanceOfSlot: number;
    decimals: number;
    swapFee?: number;
  }[];
}

let manager: SignerWithAddress, user: SignerWithAddress;
let poolTokenSwapper: PoolTokenSwapper, poolFactoryContract: PoolFactory;
let assetsEnabled: string[], poolsEnabled: string[], poolSwapFees: number[];
let usdc: IERC20Extended, dai: IERC20Extended;
let chainId: ChainIds;
const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iEasySwapper = new ethers.utils.Interface(DhedgeEasySwapper__factory.abi);
const iPoolLogic = new ethers.utils.Interface(PoolLogic__factory.abi);

const USDC_AMOUNT = units(10_000, 6);

export const testPoolTokenSwapperManage = (testParams: PoolTokenSwapperManageTestParameters[]) => {
  for (const params of testParams) {
    const { network, chainData, poolFactory, easySwapper, assetHandler, assets } = params;
    chainId = utils.networkToChainIdMap[network];
    const usdcAddress = chainData.assets.usdc;
    const oneInchRouter = chainData.oneinch.v5Router;
    assetsEnabled = [usdcAddress];
    poolsEnabled = assets.filter((token) => token.type === "pool").map((token) => token.address);
    poolSwapFees = assets.filter((token) => token.type === "pool").map((token) => (token.swapFee ? token.swapFee : 0));

    describe(`${network} pool token swapper manage test`, function () {
      utils.beforeAfterReset(before, after);
      utils.beforeAfterReset(beforeEach, afterEach);

      before(async function () {
        [manager, user] = await ethers.getSigners();
        usdc = await ethers.getContractAt("IERC20Extended", usdcAddress);
        dai = await ethers.getContractAt("IERC20Extended", chainData.assets.dai);

        // deploy pool token swapper
        const PoolTokenSwapper = await ethers.getContractFactory("PoolTokenSwapper");
        const { assetConfig, poolConfig } = getPoolTokenSwapperConfig(assetsEnabled, poolsEnabled, poolSwapFees);
        poolTokenSwapper = <PoolTokenSwapper>(
          await upgrades.deployProxy(PoolTokenSwapper, [poolFactory, manager.address, assetConfig, poolConfig, []])
        );
        await poolTokenSwapper.deployed();
        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        poolFactoryContract = PoolFactory.attach(poolFactory);
        const poolFactoryOwner = await utils.impersonateAccount(await poolFactoryContract.owner());
        await poolFactoryContract.connect(poolFactoryOwner).addReceiverWhitelist(poolTokenSwapper.address); // allows for instant pool token transfers after minting
      });

      it(`Can liquidate pool: regular pool withdrawal`, async function () {
        const PoolLogic = await ethers.getContractFactory("PoolLogic");
        const pool1 = PoolLogic.attach(poolsEnabled[0]);

        // mint asset tokens
        // mint pool tokens
        // transfer pool tokens to swapper contract
        await getAccountToken(USDC_AMOUNT, user.address, usdc.address, 0);
        const poolTokenBalance = await depositAssetToPool(user, usdc, pool1, USDC_AMOUNT);
        await pool1.connect(user).transfer(poolTokenSwapper.address, poolTokenBalance);

        const poolTokenBalanceBefore = await pool1.balanceOf(poolTokenSwapper.address);

        const withdrawUsdcData = iPoolLogic.encodeFunctionData("withdraw", [poolTokenBalance]);
        await poolTokenSwapper.connect(manager).execTransaction(pool1.address, withdrawUsdcData);

        const poolTokenBalanceAfter = await pool1.balanceOf(poolTokenSwapper.address);

        expect(poolTokenBalanceBefore).to.be.gt(poolTokenBalanceAfter);
        expect(poolTokenBalanceAfter).to.be.eq(0);
      });

      it(`Can't liquidate pool using 'withdrawTo'`, async function () {
        const PoolLogic = await ethers.getContractFactory("PoolLogic");
        const pool1 = PoolLogic.attach(poolsEnabled[0]);

        // mint asset tokens
        // mint pool tokens
        // transfer pool tokens to swapper contract
        await getAccountToken(USDC_AMOUNT, user.address, usdc.address, 0);
        const poolTokenBalance = await depositAssetToPool(user, usdc, pool1, USDC_AMOUNT);
        await pool1.connect(user).transfer(poolTokenSwapper.address, poolTokenBalance);

        const withdrawUsdcData = iPoolLogic.encodeFunctionData("withdrawTo", [user.address, poolTokenBalance]);
        await expect(
          poolTokenSwapper.connect(manager).execTransaction(pool1.address, withdrawUsdcData),
        ).to.be.revertedWith("invalid transaction");
      });

      it(`Can liquidate pool: single asset withdrawal to USDC`, async function () {
        const PoolLogic = await ethers.getContractFactory("PoolLogic");
        const pool1 = PoolLogic.attach(poolsEnabled[0]);
        // const swapFee = poolSwapFees[0];

        // mint asset tokens
        // mint pool tokens
        // transfer pool tokens to swapper contract
        await getAccountToken(USDC_AMOUNT, user.address, usdc.address, 0);
        const poolTokenBalance = await depositAssetToPool(user, usdc, pool1, USDC_AMOUNT);
        await pool1.connect(user).transfer(poolTokenSwapper.address, poolTokenBalance);

        // withdraw pool token to USDC using EasySwapper
        const approveData = iERC20.encodeFunctionData("approve", [easySwapper, poolTokenBalance]);
        await poolTokenSwapper.connect(manager).execTransaction(pool1.address, approveData);

        const withdrawUsdcData = iEasySwapper.encodeFunctionData("withdraw", [
          pool1.address,
          poolTokenBalance,
          usdc.address,
          0,
        ]);
        await poolTokenSwapper.connect(manager).execTransaction(easySwapper, withdrawUsdcData);
      });

      it(`Can swap USDC to DAI`, async function () {
        await getAccountToken(USDC_AMOUNT, user.address, usdc.address, 0);
        await usdc.connect(user).transfer(poolTokenSwapper.address, USDC_AMOUNT);
        // approve 1inch router
        const approveData = iERC20.encodeFunctionData("approve", [oneInchRouter, USDC_AMOUNT]);
        await poolTokenSwapper.connect(manager).execTransaction(usdc.address, approveData);

        // swap USDC -> DAI
        const swapTx = await getOneInchSwapTransaction({
          src: usdc.address,
          dst: dai.address,
          amount: USDC_AMOUNT,
          from: poolTokenSwapper.address,
          receiver: poolTokenSwapper.address,
          chainId,
        });

        const usdcBalanceBefore = await usdc.balanceOf(poolTokenSwapper.address);
        const daiBalanceBefore = await dai.balanceOf(poolTokenSwapper.address);

        await poolTokenSwapper.connect(manager).execTransaction(oneInchRouter, swapTx);

        const usdcBalanceAfter = await usdc.balanceOf(poolTokenSwapper.address);
        const daiBalanceAfter = await dai.balanceOf(poolTokenSwapper.address);

        expect(usdcBalanceAfter).to.be.lt(usdcBalanceBefore);
        expect(daiBalanceAfter).to.be.gt(daiBalanceBefore);
      });

      it(`Can't swap USDC to DAI and send tokens to user`, async function () {
        await getAccountToken(USDC_AMOUNT, user.address, usdc.address, 0);
        await usdc.connect(user).transfer(poolTokenSwapper.address, USDC_AMOUNT);
        // approve 1inch router
        const approveData = iERC20.encodeFunctionData("approve", [oneInchRouter, USDC_AMOUNT]);
        await poolTokenSwapper.connect(manager).execTransaction(usdc.address, approveData);

        // swap USDC -> DAI
        const swapTx = await getOneInchSwapTransaction({
          src: usdc.address,
          dst: dai.address,
          amount: USDC_AMOUNT,
          from: poolTokenSwapper.address,
          receiver: user.address, // send to user after swap
          chainId,
        });

        await expect(poolTokenSwapper.connect(manager).execTransaction(oneInchRouter, swapTx)).to.be.revertedWith(
          "recipient is not pool",
        );
      });

      it(`Can't swap USDC to unsupported token`, async function () {
        // Uses WETH as an unsupported asset to swap to

        // Remove WETH as an asset from the system
        const AssetHandler = await ethers.getContractFactory("AssetHandler");
        const assetHandlerContract = AssetHandler.attach(assetHandler);
        const assetHandlerOwner = await utils.impersonateAccount(await assetHandlerContract.owner());
        await assetHandlerContract.connect(assetHandlerOwner).removeAsset(chainData.assets.weth);

        // get USDC and send to token swapper
        await getAccountToken(USDC_AMOUNT, user.address, usdc.address, 0);
        await usdc.connect(user).transfer(poolTokenSwapper.address, USDC_AMOUNT);

        // approve 1inch router
        const approveData = iERC20.encodeFunctionData("approve", [oneInchRouter, USDC_AMOUNT]);
        await poolTokenSwapper.connect(manager).execTransaction(usdc.address, approveData);

        // swap USDC -> unsupported token
        const swapTx = await getOneInchSwapTransaction({
          src: usdc.address,
          dst: chainData.assets.weth,
          amount: USDC_AMOUNT,
          from: poolTokenSwapper.address,
          receiver: poolTokenSwapper.address,
          chainId,
        });
        await expect(poolTokenSwapper.connect(manager).execTransaction(oneInchRouter, swapTx)).to.be.revertedWith(
          "unsupported destination asset",
        );
      });

      it(`Can't send USDC to manager`, async function () {
        await getAccountToken(USDC_AMOUNT, user.address, usdc.address, 0);
        await usdc.connect(user).transfer(poolTokenSwapper.address, USDC_AMOUNT);
        const transferTxData = iERC20.encodeFunctionData("transfer", [manager.address, USDC_AMOUNT]);
        await expect(
          poolTokenSwapper.connect(manager).execTransaction(usdc.address, transferTxData),
        ).to.be.revertedWith("invalid transaction");
      });
    });
  }
};
