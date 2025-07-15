import { baseChainData } from "../../../../config/chainData/baseData";
import { units } from "../../../testHelpers";
import { runEasySwapperV2Tests, EasySwapperV2TestCase } from "../../common/easySwapperV2/EasySwapperV2Test";
import { runEasySwapperV2GuardsTest } from "../../common/easySwapperV2/EasySwapperV2GuardsTest";

// IMPORTANT: these are real vaults. poolDepositorAddress is not guaranteed to be depositor of testPoolAddress
const withdrawTestCases: EasySwapperV2TestCase[] = [
  // Toros yield vaults
  {
    poolDepositorAddress: "0x5C45506F96d4809FE96655a4BDEEddaB0FE5E095",
    testPoolAddress: baseChainData.torosPools.USDMNY,
    destToken: baseChainData.assets.usdc,
    slippageTolerance: 10,
    name: "USDmny",
  },
  {
    poolDepositorAddress: "0x6fcd83743ebe17f20cf7f5186301f82951f7242d",
    testPoolAddress: baseChainData.torosPools.ETHy,
    destToken: baseChainData.assets.weth,
    slippageTolerance: 10,
    name: "ETHy",
  },
  // Toros leveraged vaults
  {
    poolDepositorAddress: "0x5619AD05b0253a7e647Bd2E4C01c7f40CEaB0879",
    testPoolAddress: baseChainData.torosPools.STETHBULL4X,
    destToken: baseChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Staked Ethereum Bull 4X",
  },
  {
    poolDepositorAddress: "0x5619AD05b0253a7e647Bd2E4C01c7f40CEaB0879",
    testPoolAddress: baseChainData.torosPools.STETHBULL3X,
    destToken: baseChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Staked Ethereum Bull 3X",
  },
  {
    poolDepositorAddress: "0x5619AD05b0253a7e647Bd2E4C01c7f40CEaB0879",
    testPoolAddress: baseChainData.torosPools.STETHBULL2X,
    destToken: baseChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Staked Ethereum Bull 2X",
  },
  {
    poolDepositorAddress: "0xb4774db68ea5eeab8d2fb6f930e1735bc7d113e5",
    testPoolAddress: baseChainData.torosPools.BTCBULL3X,
    destToken: baseChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Bitcoin Bull 3X",
  },
  {
    poolDepositorAddress: "0x253956aedc059947e700071bc6d74bd8e34fe2ab",
    testPoolAddress: baseChainData.torosPools.BTCBULL2X,
    destToken: baseChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Bitcoin Bull 2X",
  },
  {
    poolDepositorAddress: "0x25ca6760fc0936127a6e34c3cbd63064b8a0de1f",
    testPoolAddress: baseChainData.torosPools.BTCBEAR1X,
    destToken: baseChainData.assets.usdc,
    slippageTolerance: 10,
    name: "Bitcoin Bear 1X",
  },
  // Other test vaults
  {
    poolDepositorAddress: "0x222d4c9ad24eee3f44ecd21e40ad0b4ac998a2f2",
    testPoolAddress: "0xca11502ce240905688c9d8b2a7d4fbd42b5a11f5",
    destToken: baseChainData.assets.weth,
    slippageTolerance: 10,
    name: "Apollo Partners Base Fund I",
  },
  {
    poolDepositorAddress: "0x25ca6760fC0936127a6E34c3CBD63064b8A0DE1f",
    testPoolAddress: "0x3b5cdaf7e04f0ca3e987d44aa97ed835f61dd59a",
    destToken: baseChainData.assets.dai,
    slippageTolerance: 10,
    name: "Ethereum Bull 3X (Test)",
  },
  {
    poolDepositorAddress: "0x25ca6760fC0936127a6E34c3CBD63064b8A0DE1f",
    testPoolAddress: "0x582516de68d01b946defdf667a3e5a8366c207c7",
    destToken: baseChainData.assets.weth,
    slippageTolerance: 10,
    name: "EasySwapperV2 Test",
  },
  {
    poolDepositorAddress: "0x25ca6760fC0936127a6E34c3CBD63064b8A0DE1f",
    testPoolAddress: "0xcc4d4e673046e843c0e41ed150ad7a4be95b62ea",
    destToken: baseChainData.assets.snx,
    slippageTolerance: 10,
    name: "SwapperTest",
  },
];

runEasySwapperV2Tests({
  ...baseChainData,
  wrappedNativeToken: baseChainData.assets.weth,
  swapperAddress: baseChainData.flatMoney.swapper,
  baseTestPoolAddress: withdrawTestCases[0],
  withdrawTestCases,
  chainId: 8453,
  depositsData: {
    poolDepositToken: {
      address: baseChainData.assets.usdc,
      slot: baseChainData.assetsBalanceOfSlot.usdc,
      amount: units(800, 6),
    },
    userDepositToken: {
      address: baseChainData.assets.dai,
      slot: baseChainData.assetsBalanceOfSlot.dai,
      amount: units(1_000),
    },
    nativeTokenWrapper: {
      address: baseChainData.assets.weth,
      slot: baseChainData.assetsBalanceOfSlot.weth,
      amount: units(1),
    },
  },
  poolFactory: "0x49Afe3abCf66CF09Fab86cb1139D8811C8afe56F",
  onchainSwapRouter: "0x9bE950d8bff36F09E5D460271859F94C7C58344C",
});

runEasySwapperV2GuardsTest({
  ...baseChainData,
  swapperAddress: baseChainData.flatMoney.swapper,
  wrappedNativeToken: baseChainData.assets.weth,
  chainId: 8453,
});
