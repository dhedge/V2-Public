import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  depositAssetToPool,
  swapAssetToPoolToken,
  swapPoolTokenToAsset,
  swapPoolTokenToPoolToken,
  getPoolTokenSwapperConfig,
  getAssetToPoolSwapParams,
  getPoolToAssetSwapParams,
  getPoolToPoolSwapParams,
  FEE_DENOMINATOR,
} from "./PoolTokenSwapperHelpers";
import { NETWORK } from "../../utils/deployContracts/deployContracts";
import { utils } from "../../utils/utils";
import { getAccountToken } from "../../utils/getAccountTokens";
import { units } from "../../../testHelpers";
import { PoolTokenSwapper, PoolFactory } from "../../../../types";
import { PTSChainData } from "./PoolTokenSwapperManageTest";

type AssetType = "pool" | "asset";

export interface PoolTokenSwapperTestParameters {
  network: NETWORK;
  chainData: PTSChainData;
  poolFactory: string;
  swapFrom: {
    name: string;
    type: AssetType;
    address: string;
    balanceOfSlot: number;
    decimals: number;
    swapFee?: number;
  };
  swapTo: {
    name: string;
    type: AssetType;
    address: string;
    balanceOfSlot: number;
    decimals: number;
    swapFee?: number;
  };
  swapAmount: BigNumber;
}

let manager: SignerWithAddress, user: SignerWithAddress;
let poolTokenSwapper: PoolTokenSwapper, poolFactoryContract: PoolFactory;

export const testPoolTokenSwapperSwap = (testParams: PoolTokenSwapperTestParameters[]) => {
  for (const params of testParams) {
    const { network, chainData, poolFactory, swapFrom, swapTo, swapAmount } = params;

    const assetsEnabled = [chainData.assets.usdc];
    const poolsEnabled = [swapFrom, swapTo].filter((token) => token.type === "pool").map((token) => token.address);
    const poolSwapFees = [swapFrom, swapTo]
      .filter((token) => token.type === "pool")
      .map((token) => (token.swapFee ? token.swapFee : 0));

    describe(`${network} pool token swapper swap test from ${swapFrom.type} to ${swapTo.type}`, function () {
      utils.beforeAfterReset(before, after);
      utils.beforeAfterReset(beforeEach, afterEach);

      before(async function () {
        [manager, user] = await ethers.getSigners();

        const PoolTokenSwapper = await ethers.getContractFactory("PoolTokenSwapper");
        const { assetConfig, poolConfig } = getPoolTokenSwapperConfig(assetsEnabled, poolsEnabled, poolSwapFees);

        poolTokenSwapper = <PoolTokenSwapper>(
          await upgrades.deployProxy(PoolTokenSwapper, [
            poolFactory,
            manager.address,
            assetConfig,
            poolConfig,
            [{ sender: user.address, status: true }],
          ])
        );
        await poolTokenSwapper.deployed();

        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        poolFactoryContract = PoolFactory.attach(poolFactory);
        const poolFactoryOwner = await utils.impersonateAccount(await poolFactoryContract.owner());
        await poolFactoryContract.connect(poolFactoryOwner).addReceiverWhitelist(poolTokenSwapper.address); // allows for instant pool token transfers after minting
      });

      it(`Get quote from ${swapFrom.name} to ${swapTo.name}`, async function () {
        const quoterAmountOut = await poolTokenSwapper.getSwapQuote(swapFrom.address, swapTo.address, swapAmount);
        await checkSwapQuote(swapFrom, swapTo, swapAmount, quoterAmountOut);
      });

      it(`Invalid swap asset quote should revert`, async function () {
        await expect(
          poolTokenSwapper.getSwapQuote(chainData.assets.weth, swapTo.address, swapAmount),
        ).to.be.revertedWith("invalid quote assets");
        await expect(
          poolTokenSwapper.getSwapQuote(swapFrom.address, chainData.assets.weth, swapAmount),
        ).to.be.revertedWith("invalid quote assets");
      });

      it(`Swap from ${swapFrom.name} to ${swapTo.name}`, async function () {
        await executeSwap(swapFrom, swapTo, swapAmount, chainData);
      });

      it(`Invalid swap asset should revert`, async function () {
        // swap function
        await expect(
          poolTokenSwapper.connect(user).swap(chainData.assets.weth, swapTo.address, swapAmount, 0),
        ).to.be.revertedWith("invalid swap");
        await expect(
          poolTokenSwapper.connect(user).swap(swapFrom.address, chainData.assets.weth, swapAmount, 0),
        ).to.be.revertedWith("invalid swap");

        if (swapFrom.type === "asset" && swapTo.type === "pool") {
          // swap asset to pool function
          await expect(
            poolTokenSwapper.connect(user).swap(chainData.assets.weth, swapTo.address, swapAmount, 0),
          ).to.be.revertedWith("invalid swap");
          await expect(
            poolTokenSwapper.connect(user).swap(swapFrom.address, chainData.assets.weth, swapAmount, 0),
          ).to.be.revertedWith("invalid swap");
        }

        if (swapFrom.type === "pool" && swapTo.type === "asset") {
          // swap pool to asset function
          await expect(
            poolTokenSwapper.connect(user).swap(chainData.assets.weth, swapTo.address, swapAmount, 0),
          ).to.be.revertedWith("invalid swap");
          await expect(
            poolTokenSwapper.connect(user).swap(swapFrom.address, chainData.assets.weth, swapAmount, 0),
          ).to.be.revertedWith("invalid swap");
        }

        if (swapFrom.type === "pool" && swapTo.type === "pool") {
          // swap pool to pool function
          await expect(
            poolTokenSwapper.connect(user).swap(chainData.assets.weth, swapTo.address, swapAmount, 0),
          ).to.be.revertedWith("invalid swap");
          await expect(
            poolTokenSwapper.connect(user).swap(swapFrom.address, chainData.assets.weth, swapAmount, 0),
          ).to.be.revertedWith("invalid swap");
        }
      });
    });
  }
};

const executeSwap = async (
  swapFrom: PoolTokenSwapperTestParameters["swapFrom"],
  swapTo: PoolTokenSwapperTestParameters["swapTo"],
  swapAmount: BigNumber,
  chainData: PoolTokenSwapperTestParameters["chainData"],
) => {
  if (swapFrom.type === "asset" && swapTo.type === "pool") {
    const { fromAsset, toAsset, swapFee } = await getAssetToPoolSwapParams(swapFrom, swapTo);

    // mint asset tokens
    // mint pool tokens
    // transfer pool tokens to swapper contract
    await getAccountToken(swapAmount.mul(4), user.address, swapFrom.address, 0);
    const poolTokenBalance = await depositAssetToPool(user, fromAsset, toAsset, swapAmount.mul(2));
    await toAsset.connect(user).transfer(poolTokenSwapper.address, poolTokenBalance);

    await swapAssetToPoolToken(user, poolTokenSwapper, fromAsset, toAsset, swapAmount, poolFactoryContract, swapFee);
  }

  if (swapFrom.type === "pool" && swapTo.type === "asset") {
    const { fromAsset, toAsset, swapFee } = await getPoolToAssetSwapParams(swapFrom, swapTo);

    // mint asset tokens
    // mint pool tokens
    // transfer asset tokens to swapper contract
    const accountTokenAmount = swapAmount.mul(4).mul(units(1, swapTo.decimals)).div(units(1, swapFrom.decimals));
    await getAccountToken(accountTokenAmount, user.address, swapTo.address, 0);
    await depositAssetToPool(user, toAsset, fromAsset, accountTokenAmount.div(2));
    const remainingAssetTokens = await toAsset.balanceOf(user.address);
    await toAsset.connect(user).transfer(poolTokenSwapper.address, remainingAssetTokens);

    await swapPoolTokenToAsset(user, poolTokenSwapper, fromAsset, toAsset, swapAmount, poolFactoryContract, swapFee);
  }

  if (swapFrom.type === "pool" && swapTo.type === "pool") {
    const { fromAsset, toAsset, swapFee } = await getPoolToPoolSwapParams(swapFrom, swapTo);

    // get USDC to mint both pool tokens
    const usdc = await ethers.getContractAt("IERC20Extended", chainData.assets.usdc);
    const usdcDecimals = await usdc.decimals();
    const accountTokenAmount = swapAmount.mul(4).mul(units(1, usdcDecimals)).div(units(1, 18));
    await getAccountToken(accountTokenAmount, user.address, usdc.address, 0);

    // mint from pool tokens
    // mint to pool tokens
    // transfer asset tokens to swapper contract
    await depositAssetToPool(user, usdc, fromAsset, accountTokenAmount.div(2));
    const toPoolTokenBalance = await depositAssetToPool(user, usdc, toAsset, accountTokenAmount.div(2));
    await toAsset.connect(user).transfer(poolTokenSwapper.address, toPoolTokenBalance);

    await swapPoolTokenToPoolToken(
      user,
      poolTokenSwapper,
      fromAsset,
      toAsset,
      swapAmount,
      poolFactoryContract,
      swapFee,
    );
  }
};

const checkSwapQuote = async (
  swapFrom: PoolTokenSwapperTestParameters["swapFrom"],
  swapTo: PoolTokenSwapperTestParameters["swapTo"],
  swapAmount: PoolTokenSwapperTestParameters["swapAmount"],
  quoterAmountOut: BigNumber,
) => {
  if (swapFrom.type === "asset" && swapTo.type === "pool") {
    const { fromAsset, toAsset, swapFee } = await getAssetToPoolSwapParams(swapFrom, swapTo);
    const fromDecimals = await fromAsset.decimals();
    const fromPrice = await poolFactoryContract.getAssetPrice(fromAsset.address); // 18 decimals
    const toTokenPrice = await toAsset.tokenPrice(); // 18 decimals
    const expectedAmountOut = swapAmount
      .mul(units(1, 18 - fromDecimals))
      .mul(units(1))
      .div(toTokenPrice)
      .mul(fromPrice)
      .div(units(1))
      .mul(FEE_DENOMINATOR - swapFee)
      .div(FEE_DENOMINATOR);
    expect(quoterAmountOut).to.be.closeTo(expectedAmountOut, quoterAmountOut.div(10_000_000)); // 0.00001% delta
  }

  if (swapFrom.type === "pool" && swapTo.type === "asset") {
    const { fromAsset, toAsset, swapFee } = await getPoolToAssetSwapParams(swapFrom, swapTo);
    const toDecimals = await toAsset.decimals();
    const toPrice = await poolFactoryContract.getAssetPrice(toAsset.address); // 18 decimals
    const fromTokenPrice = await fromAsset.tokenPrice(); // 18 decimals
    const expectedAmountOut = swapAmount
      .mul(fromTokenPrice)
      .div(units(1))
      .mul(units(1, toDecimals))
      .div(toPrice)
      .mul(FEE_DENOMINATOR - swapFee)
      .div(FEE_DENOMINATOR);
    expect(quoterAmountOut).to.be.closeTo(expectedAmountOut, quoterAmountOut.div(10_000_000)); // 0.00001% delta
  }

  if (swapFrom.type === "pool" && swapTo.type === "pool") {
    const { fromAsset, toAsset, swapFee } = await getPoolToPoolSwapParams(swapFrom, swapTo);
    const fromTokenPrice = await fromAsset.tokenPrice(); // 18 decimals
    const toTokenPrice = await toAsset.tokenPrice(); // 18 decimals;
    const expectedAmountOut = swapAmount
      .mul(fromTokenPrice)
      .div(toTokenPrice)
      .mul(FEE_DENOMINATOR - swapFee)
      .div(FEE_DENOMINATOR);
    expect(quoterAmountOut).to.be.closeTo(expectedAmountOut, quoterAmountOut.div(10_000_000)); // 0.00001% delta
  }
};
