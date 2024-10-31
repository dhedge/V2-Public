import { baseChainData } from "../../../../config/chainData/baseData";
import { units } from "../../../testHelpers";
import { runEasySwapperV2Tests, EasySwapperV2TestCase } from "../../common/easySwapperV2/EasySwapperV2Test";
import { runEasySwapperV2GuardsTest } from "../../common/easySwapperV2/EasySwapperV2GuardsTest";

// IMPORTANT: these are real vaults. poolDepositorAddress is not guaranteed to be depositor of testPoolAddress
const withdrawTestCases: EasySwapperV2TestCase[] = [
  {
    poolDepositorAddress: "0x25ca6760fC0936127a6E34c3CBD63064b8A0DE1f",
    testPoolAddress: "0x582516de68d01b946defdf667a3e5a8366c207c7",
    destToken: baseChainData.assets.weth,
    slippageTolerance: 8,
    name: "EasySwapperV2 Test",
  },
  {
    poolDepositorAddress: "0x25ca6760fC0936127a6E34c3CBD63064b8A0DE1f",
    testPoolAddress: "0x3b5cdaf7e04f0ca3e987d44aa97ed835f61dd59a",
    destToken: baseChainData.assets.dai,
    slippageTolerance: 8,
    name: "Ethereum Bull 3X (Test)",
  },
  {
    poolDepositorAddress: "0x25ca6760fC0936127a6E34c3CBD63064b8A0DE1f",
    testPoolAddress: "0x1d5e96535647280bbb117dec05a375e1de592e0c",
    destToken: baseChainData.assets.dai,
    slippageTolerance: 8,
    name: "Ethereum Bear 2X (Test)",
  },
  {
    poolDepositorAddress: "0x25ca6760fC0936127a6E34c3CBD63064b8A0DE1f",
    testPoolAddress: "0xcc4d4e673046e843c0e41ed150ad7a4be95b62ea",
    destToken: baseChainData.assets.snx,
    slippageTolerance: 8,
    name: "SwapperTest",
  },
  {
    poolDepositorAddress: "0x5C45506F96d4809FE96655a4BDEEddaB0FE5E095",
    testPoolAddress: "0xede61eefa4850b459e3b09fe6d8d371480d6ff00",
    destToken: baseChainData.assets.usdc,
    slippageTolerance: 10,
    name: "USDmny",
  },
  {
    poolDepositorAddress: "0x222d4c9ad24eee3f44ecd21e40ad0b4ac998a2f2",
    testPoolAddress: "0xca11502ce240905688c9d8b2a7d4fbd42b5a11f5",
    destToken: baseChainData.assets.weth,
    slippageTolerance: 20,
    name: "Apollo Partners Base Fund I",
  },
  {
    poolDepositorAddress: "0x97020c9ec66e0f59231918b1d2f167a66026aff2",
    testPoolAddress: "0x53a4716a8f7dbc9543ebf9cd711952033cc64d43",
    destToken: baseChainData.assets.weth,
    slippageTolerance: 10,
    name: "ETHy",
  },
  {
    poolDepositorAddress: "0xcf64286650ec39e9545b1f2402c592a6f00a04e2",
    testPoolAddress: "0xba5f6a0d2ac21a3fec7a6c40facd23407aa84663",
    destToken: baseChainData.assets.usdc,
    slippageTolerance: 5,
    name: "Staked Ethereum Bull 4X",
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
});

runEasySwapperV2GuardsTest({
  ...baseChainData,
  swapperAddress: baseChainData.flatMoney.swapper,
  wrappedNativeToken: baseChainData.assets.weth,
  chainId: 8453,
});
