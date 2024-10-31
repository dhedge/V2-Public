import { ovmChainData } from "../../../../config/chainData/ovmData";
import { units } from "../../../testHelpers";
import { runEasySwapperV2Tests, EasySwapperV2TestCase } from "../../common/easySwapperV2/EasySwapperV2Test";
import { runEasySwapperV2GuardsTest } from "../../common/easySwapperV2/EasySwapperV2GuardsTest";

// IMPORTANT: these are real vaults. poolDepositorAddress is not guaranteed to be depositor of testPoolAddress
const withdrawTestCases: EasySwapperV2TestCase[] = [
  {
    poolDepositorAddress: "0x51150f973c2b0537642f5ae8911a49567598808f",
    testPoolAddress: "0xf36f550907872faaa02477f791df3ce33fe38854",
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "OVM Test",
  },
];

runEasySwapperV2Tests({
  ...ovmChainData,
  wrappedNativeToken: ovmChainData.assets.weth,
  swapperAddress: ovmChainData.flatMoney.swapper,
  baseTestPoolAddress: withdrawTestCases[0],
  withdrawTestCases,
  chainId: 10,
  depositsData: {
    poolDepositToken: {
      address: ovmChainData.assets.usdc,
      slot: ovmChainData.assetsBalanceOfSlot.usdc,
      amount: units(800, 6),
    },
    userDepositToken: {
      address: ovmChainData.assets.dai,
      slot: ovmChainData.assetsBalanceOfSlot.dai,
      amount: units(1_000),
    },
    nativeTokenWrapper: {
      address: ovmChainData.assets.weth,
      slot: ovmChainData.assetsBalanceOfSlot.weth,
      amount: units(1),
    },
  },
  poolFactory: "0x5e61a079A178f0E5784107a4963baAe0c5a680c6",
});

runEasySwapperV2GuardsTest({
  ...ovmChainData,
  swapperAddress: ovmChainData.flatMoney.swapper,
  wrappedNativeToken: ovmChainData.assets.weth,
  chainId: 10,
});
