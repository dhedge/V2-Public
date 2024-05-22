import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { assert, expect } from "chai";
import { ethers } from "hardhat";

import {
  IBackboneDeployments,
  IBackboneDeploymentsParams,
  deployBackboneContracts,
} from "../../utils/deployContracts/deployBackboneContracts";
import { utils } from "../../utils/utils";
import { units } from "../../../testHelpers";
import { createFund } from "../../utils/createFund";
import { getAccountToken } from "../../utils/getAccountTokens";
import { getZeroExSwapTransactionQuote } from "../../utils/zeroEx/api";
import { getMinAmountOut } from "../../utils/getMinAmountOut";
import {
  PoolLogic,
  IERC20,
  IERC20__factory,
  ITransformERC20Feature__factory,
  PoolManagerLogic,
} from "../../../../types";

import { deployZeroExContractGuard } from "./zeroExTestDeploymentHelpers";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iTransformERC20Feature = new ethers.utils.Interface(ITransformERC20Feature__factory.abi);
const USDC_AMOUNT = units(5000, 6);

type IParams = IBackboneDeploymentsParams & {
  assetsBalanceOfSlot: {
    usdc: number;
  };
  zeroEx: {
    exchangeProxy: string;
    baseURL: string;
    nativeTokenTicker: "ETH" | "MATIC";
  };
  usdtAddress: string;
  usdtPriceFeed: string;
};

export const launchZeroExSwapsTests = (chainData: IParams) => {
  describe("ZeroEx Swaps Test", () => {
    let deployments: IBackboneDeployments;
    let poolLogicProxy: PoolLogic;
    let poolManagerLogicProxy: PoolManagerLogic;
    let poolLogicAddress: string;
    let manager: SignerWithAddress, logicOwner: SignerWithAddress;
    let USDC: IERC20, USDT: IERC20;
    let usdcAddress: string;
    let usdtAddress: string;

    utils.beforeAfterReset(beforeEach, afterEach);
    utils.beforeAfterReset(before, after);

    before(async () => {
      deployments = await deployBackboneContracts(chainData);
      const { tether } = await deployZeroExContractGuard(deployments, {
        zeroExExchangeProxy: chainData.zeroEx.exchangeProxy,
        usdtAddress: chainData.usdtAddress,
        usdtPriceFeed: chainData.usdtPriceFeed,
      });
      manager = deployments.manager;
      logicOwner = deployments.owner;
      USDC = deployments.assets.USDC;
      USDT = tether;
      usdcAddress = USDC.address;
      usdtAddress = USDT.address;
      const supportedAssets = [
        {
          asset: usdcAddress,
          isDeposit: true,
        },
        {
          asset: usdtAddress,
          isDeposit: false,
        },
      ];
      const poolProxies = await createFund(deployments.poolFactory, logicOwner, manager, supportedAssets);
      poolLogicProxy = poolProxies.poolLogicProxy;
      poolManagerLogicProxy = poolProxies.poolManagerLogicProxy;
      poolLogicAddress = poolLogicProxy.address;

      // Fund logic owner with 10_000 USDC
      await getAccountToken(units(10000, 6), logicOwner.address, usdcAddress, chainData.assetsBalanceOfSlot.usdc);

      // Deposit assets into pool
      await USDC.approve(poolLogicAddress, USDC_AMOUNT);
      await poolLogicProxy.deposit(usdcAddress, USDC_AMOUNT);
    });

    const approveZeroExAsSpender = async () => {
      await poolLogicProxy
        .connect(manager)
        .execTransaction(
          usdcAddress,
          iERC20.encodeFunctionData("approve", [chainData.zeroEx.exchangeProxy, USDC_AMOUNT]),
        );
    };

    const getTxDataFromAPI = async (sellAmount: string, buyToken = usdtAddress) => {
      const response = await getZeroExSwapTransactionQuote({
        baseURL: chainData.zeroEx.baseURL,
        sellToken: usdcAddress,
        buyToken,
        sellAmount,
      });
      assert(response !== null, "getting ZeroEx swap transaction failed");
      expect(response.to.toLowerCase()).to.equal(chainData.zeroEx.exchangeProxy.toLowerCase());
      return response;
    };

    it("should be able to approve ZeroEx Exchange Proxy as spender", async () => {
      expect(await USDC.allowance(poolLogicAddress, chainData.zeroEx.exchangeProxy)).to.be.equal(0);
      await approveZeroExAsSpender();
      expect(await USDC.allowance(poolLogicAddress, chainData.zeroEx.exchangeProxy)).to.be.equal(USDC_AMOUNT);
    });

    it("should be able to perform a swap through transformERC20 method", async () => {
      const usdcBalanceBefore = await USDC.balanceOf(poolLogicAddress);
      const usdtBalanceBefore = await USDT.balanceOf(poolLogicAddress);
      const totalFundValueBefore = await poolManagerLogicProxy.totalFundValue();
      expect(usdcBalanceBefore).to.equal(USDC_AMOUNT);
      expect(usdtBalanceBefore).to.equal(0);

      const sellAmount = USDC_AMOUNT.div(2);
      const response = await getTxDataFromAPI(sellAmount.toString());

      await approveZeroExAsSpender();
      await poolLogicProxy.connect(manager).execTransaction(chainData.zeroEx.exchangeProxy, response.data);

      const usdcBalanceAfter = await USDC.balanceOf(poolLogicAddress);
      const usdtBalanceAfter = await USDT.balanceOf(poolLogicAddress);
      const totalFundValueAfter = await poolManagerLogicProxy.totalFundValue();
      expect(usdcBalanceAfter).to.be.equal(sellAmount);
      expect(usdtBalanceAfter).to.be.closeTo(sellAmount, sellAmount.div(100)); // this is 1% delta
      expect(totalFundValueBefore).to.be.closeTo(totalFundValueAfter, totalFundValueBefore.div(1_000)); // this is 0.1% delta
    });

    it("should not be able to call different method on ZeroEx Exchange Proxy", async () => {
      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(
            chainData.zeroEx.exchangeProxy,
            iTransformERC20Feature.encodeFunctionData("getTransformerDeployer", []),
          ),
      ).to.be.revertedWith("invalid transaction");
    });

    it("doesn't allow to make trades with slippage more than allowed in SlippageAccumulator", async () => {
      const response = await getTxDataFromAPI(USDC_AMOUNT.toString());
      await approveZeroExAsSpender();

      const decodedData = iTransformERC20Feature.decodeFunctionData("transformERC20", response.data);
      const { inputToken, outputToken, inputTokenAmount, minOutputTokenAmount, transformations } = decodedData;
      const editedminOutputTokenAmount = minOutputTokenAmount.mul(95).div(100); // set minOutputTokenAmount to 95% of original
      const encodedData = iTransformERC20Feature.encodeFunctionData("transformERC20", [
        inputToken,
        outputToken,
        inputTokenAmount,
        editedminOutputTokenAmount,
        transformations,
      ]);

      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainData.zeroEx.exchangeProxy, encodedData),
      ).to.be.revertedWith("slippage impact exceeded");
    });

    it("can't make trades to native token", async () => {
      const response = await getTxDataFromAPI(USDC_AMOUNT.toString(), chainData.zeroEx.nativeTokenTicker); // getting tx data to swap to native token
      const decodedData = iTransformERC20Feature.decodeFunctionData("transformERC20", response.data);
      const { outputToken } = decodedData;
      assert(outputToken === "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
      await approveZeroExAsSpender();
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainData.zeroEx.exchangeProxy, response.data),
      ).to.be.revertedWith("unsupported destination asset");
    });

    it("can't make a trade to a disabled asset", async () => {
      const responseToWeth = await getTxDataFromAPI(USDC_AMOUNT.toString(), deployments.assets.WETH.address);
      await approveZeroExAsSpender();
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainData.zeroEx.exchangeProxy, responseToWeth.data),
      ).to.be.revertedWith("unsupported destination asset");
      const responseToDai = await getTxDataFromAPI(USDC_AMOUNT.toString(), deployments.assets.DAI.address);
      await expect(
        poolLogicProxy.connect(manager).execTransaction(chainData.zeroEx.exchangeProxy, responseToDai.data),
      ).to.be.revertedWith("unsupported destination asset");
    });

    it("should revert if invalid transformations were passed to transformERC20 method", async () => {
      await approveZeroExAsSpender();

      const minOutputTokenAmount = await getMinAmountOut(
        deployments.assetHandler,
        USDC_AMOUNT,
        usdcAddress,
        usdtAddress,
        99,
      );

      const realInvalidTransformations = [
        {
          deploymentNonce: 15,
          data: "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f5c764cbc14f9669b88837ca1490cca17c316070000000000000000000000002e3d870790dc77a83dd1d18184acc7439a53f47500000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000f4240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e697377617056330000000000000000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000dca179d88e2cf84000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002b7f5c764cbc14f9669b88837ca1490cca17c316070001f42e3d870790dc77a83dd1d18184acc7439a53f475000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        },
        {
          deploymentNonce: 11,
          data: "0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000007f5c764cbc14f9669b88837ca1490cca17c31607000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000",
        },
      ];

      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(
            chainData.zeroEx.exchangeProxy,
            iTransformERC20Feature.encodeFunctionData("transformERC20", [
              usdcAddress,
              usdtAddress,
              USDC_AMOUNT,
              minOutputTokenAmount,
              realInvalidTransformations,
            ]),
          ),
      ).to.be.reverted;

      const invalidTransformations = [
        {
          deploymentNonce: 1,
          data: "0x",
        },
      ];

      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(
            chainData.zeroEx.exchangeProxy,
            iTransformERC20Feature.encodeFunctionData("transformERC20", [
              usdcAddress,
              usdtAddress,
              USDC_AMOUNT,
              minOutputTokenAmount,
              invalidTransformations,
            ]),
          ),
      ).to.be.reverted;
    });

    it("should revert if cut transformations were passed to transformERC20 method", async () => {
      const response = await getTxDataFromAPI(USDC_AMOUNT.toString());
      await approveZeroExAsSpender();

      const decodedData = iTransformERC20Feature.decodeFunctionData("transformERC20", response.data);
      const { inputToken, outputToken, inputTokenAmount, minOutputTokenAmount, transformations } = decodedData;
      const cutTransformations = [transformations[1]]; // drop first (FillQuoteTransformation) from the list and leave only second (PayTakerTransformation)
      const encodedDataWithCutTransformations = iTransformERC20Feature.encodeFunctionData("transformERC20", [
        inputToken,
        outputToken,
        inputTokenAmount,
        minOutputTokenAmount,
        cutTransformations,
      ]);

      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(chainData.zeroEx.exchangeProxy, encodedDataWithCutTransformations),
      ).to.be.reverted;

      const encodedDataWithEmptyTransformations = iTransformERC20Feature.encodeFunctionData("transformERC20", [
        inputToken,
        outputToken,
        inputTokenAmount,
        minOutputTokenAmount,
        [], // pass empty array instead of transformations
      ]);

      await expect(
        poolLogicProxy
          .connect(manager)
          .execTransaction(chainData.zeroEx.exchangeProxy, encodedDataWithEmptyTransformations),
      ).to.be.reverted;
    });

    it("should revert if corrupted transformations were passed to transformERC20 method", async () => {
      const response = await getTxDataFromAPI(USDC_AMOUNT.toString());
      await approveZeroExAsSpender();

      const decodedData = iTransformERC20Feature.decodeFunctionData("transformERC20", response.data);
      const { inputToken, outputToken, inputTokenAmount, minOutputTokenAmount, transformations } = decodedData;
      // PayTakerTransformer transformation data looks like: https://github.com/0xProject/protocol/blob/development/contracts/zero-ex/contracts/src/transformers/PayTakerTransformer.sol#L50
      const corruptedPayTakerTransformationData = [
        [
          [usdtAddress, usdcAddress],
          [units(1, 6), "1"],
        ],
      ]; // putting wrong amounts and addresses to amounts array
      const encodedCorruptedData = ethers.utils.defaultAbiCoder.encode(
        ["(address[],uint256[])"],
        corruptedPayTakerTransformationData,
      );
      const corruptedTransformations = [transformations[0], [transformations[1][0], encodedCorruptedData]]; // create corrupted transformations array with proper FillQuoteTransformation and corrupted PayTakerTransformation
      const encodedData = iTransformERC20Feature.encodeFunctionData("transformERC20", [
        inputToken,
        outputToken,
        inputTokenAmount,
        minOutputTokenAmount,
        corruptedTransformations,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(chainData.zeroEx.exchangeProxy, encodedData)).to.be
        .reverted;
    });

    it("should revert if extra valid transformations were passed to transformERC20 method which bit off tokenOut amount", async () => {
      const response = await getTxDataFromAPI(USDC_AMOUNT.toString());
      await approveZeroExAsSpender();

      const decodedData = iTransformERC20Feature.decodeFunctionData("transformERC20", response.data);
      const { inputToken, outputToken, inputTokenAmount, minOutputTokenAmount, transformations } = decodedData;
      // AffiliateFee transformation data looks like https://github.com/0xProject/protocol/blob/development/contracts/zero-ex/contracts/src/transformers/AffiliateFeeTransformer.sol#L49
      const affiliateFeeTransformationData = ethers.utils.defaultAbiCoder.encode(
        ["(address,uint256,address)[]"],
        [[[usdtAddress, units(10, 6), manager.address]]],
      );
      // crafting AffiliateFee transformation data with 10 USDT to be sent to manager "like a fee".
      // we allow only 0.1% slippage while building API request for swap data, so 10 USDT bit off should revert
      const affiliateFeeTransformation = [10, affiliateFeeTransformationData];
      const extraValidTransformations = [transformations[0], affiliateFeeTransformation, transformations[1]]; // pass extra AffiliateFee transformation in between
      const encodedData = iTransformERC20Feature.encodeFunctionData("transformERC20", [
        inputToken,
        outputToken,
        inputTokenAmount,
        minOutputTokenAmount,
        extraValidTransformations,
      ]);

      await expect(poolLogicProxy.connect(manager).execTransaction(chainData.zeroEx.exchangeProxy, encodedData)).to.be
        .reverted;
    });
  });
};
