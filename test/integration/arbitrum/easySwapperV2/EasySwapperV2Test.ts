import { arbitrumChainData } from "../../../../config/chainData/arbitrumData";
import { units } from "../../../testHelpers";
import { runEasySwapperV2Tests, EasySwapperV2TestCase } from "../../common/easySwapperV2/EasySwapperV2Test";
import { runEasySwapperV2GuardsTest } from "../../common/easySwapperV2/EasySwapperV2GuardsTest";

// IMPORTANT: these are real vaults. poolDepositorAddress is not guaranteed to be depositor of testPoolAddress
const withdrawTestCases: EasySwapperV2TestCase[] = [
  {
    poolDepositorAddress: "0x25ca6760fc0936127a6e34c3cbd63064b8a0de1f",
    testPoolAddress: "0x99875d806706888bd525fe123ea1a9982b70b0e2",
    destToken: arbitrumChainData.assets.usdcNative,
    slippageTolerance: 10,
    name: "Arbitrum Test",
  },
  {
    poolDepositorAddress: "0x253956aedc059947e700071bc6d74bd8e34fe2ab",
    testPoolAddress: "0x40d30b13666c55b1f41ee11645b5ea3ea2ca31f8",
    destToken: arbitrumChainData.assets.weth,
    slippageTolerance: 10,
    name: "Ethereum Bear 1X",
  },
  {
    poolDepositorAddress: "0x16743fbb3153f224195435bdfb84ef265b7ed6d9",
    testPoolAddress: "0xad38255febd566809ae387d5be66ecd287947cb9",
    destToken: arbitrumChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Bitcoin Bull 3X",
  },
  {
    poolDepositorAddress: "0x167e0ce5d2fa07203e6e37b466f8cff86760c403",
    testPoolAddress: "0xf715724abba480d4d45f4cb52bef5ce5e3513ccc",
    destToken: arbitrumChainData.assets.weth,
    slippageTolerance: 10,
    name: "Ethereum Bull 3X",
  },
  {
    poolDepositorAddress: "0xb2735ee35725e8d0e4ef684f816ca38684620c0d",
    testPoolAddress: "0x2fca566933baaf3f454d816b7947cb45c7d79102",
    destToken: arbitrumChainData.assets.weth,
    slippageTolerance: 15,
    name: "Atlantic WETH",
  },
];

runEasySwapperV2Tests({
  ...arbitrumChainData,
  wrappedNativeToken: arbitrumChainData.assets.weth,
  swapperAddress: arbitrumChainData.flatMoney.swapper,
  baseTestPoolAddress: withdrawTestCases[0],
  withdrawTestCases,
  chainId: 42161,
  depositsData: {
    poolDepositToken: {
      address: arbitrumChainData.assets.usdc,
      slot: arbitrumChainData.assetsBalanceOfSlot.usdc,
      amount: units(800, 6),
    },
    userDepositToken: {
      address: arbitrumChainData.assets.dai,
      slot: arbitrumChainData.assetsBalanceOfSlot.dai,
      amount: units(1_000),
    },
    nativeTokenWrapper: {
      address: arbitrumChainData.assets.weth,
      slot: arbitrumChainData.assetsBalanceOfSlot.weth,
      amount: units(1),
    },
  },
  poolFactory: "0xffFb5fB14606EB3a548C113026355020dDF27535",
});

runEasySwapperV2GuardsTest({
  ...arbitrumChainData,
  swapperAddress: arbitrumChainData.flatMoney.swapper,
  wrappedNativeToken: arbitrumChainData.assets.weth,
  chainId: 42161,
});
