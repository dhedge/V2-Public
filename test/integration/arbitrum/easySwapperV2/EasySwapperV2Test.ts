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
    poolDepositorAddress: "0x885b36cd0d377e4449685a3db168a3d5a1906cc3",
    testPoolAddress: arbitrumChainData.torosPools.BTCBULL3X,
    destToken: arbitrumChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Bitcoin Bull 3X",
  },
  {
    poolDepositorAddress: "0x03d900df5b08346e2a374635beeda15c60121033",
    testPoolAddress: arbitrumChainData.torosPools.BTCBULL2X,
    destToken: arbitrumChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Bitcoin Bull 2X",
  },
  {
    poolDepositorAddress: "0x25ca6760fc0936127a6e34c3cbd63064b8a0de1f",
    testPoolAddress: arbitrumChainData.torosPools.BTCBEAR1X,
    destToken: arbitrumChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Bitcoin Bear 1X",
  },
  {
    poolDepositorAddress: "0x167e0ce5d2fa07203e6e37b466f8cff86760c403",
    testPoolAddress: arbitrumChainData.torosPools.ETHBULL3X,
    destToken: arbitrumChainData.assets.weth,
    slippageTolerance: 10,
    name: "Ethereum Bull 3X",
  },
  {
    poolDepositorAddress: "0xac7d8a2a1a3621dcb5005315d98802150fa65e5a",
    testPoolAddress: arbitrumChainData.torosPools.ETHBULL2X,
    destToken: arbitrumChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Ethereum Bull 2X",
  },
  {
    poolDepositorAddress: "0x253956aedc059947e700071bc6d74bd8e34fe2ab",
    testPoolAddress: arbitrumChainData.torosPools.ETHBEAR1X,
    destToken: arbitrumChainData.assets.weth,
    slippageTolerance: 10,
    name: "Ethereum Bear 1X",
  },
  {
    poolDepositorAddress: "0x26f7cbd49a4dc3321780ae8e7e0cb460f55a7511",
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
  onchainSwapRouter: "0x4AF5FC6930599A1117600817CB7fAE428B15CAf6",
});

runEasySwapperV2GuardsTest({
  ...arbitrumChainData,
  swapperAddress: arbitrumChainData.flatMoney.swapper,
  wrappedNativeToken: arbitrumChainData.assets.weth,
  chainId: 42161,
});
