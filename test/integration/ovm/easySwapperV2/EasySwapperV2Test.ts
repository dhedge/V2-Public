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
  {
    poolDepositorAddress: "0xd857e322351dc56592e3d9181fbf65034ef4aef2",
    testPoolAddress: ovmChainData.torosPools.SOLBULL2X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "SOLBULL2X",
  },
  {
    poolDepositorAddress: "0xd857e322351dc56592e3d9181fbf65034ef4aef2",
    testPoolAddress: ovmChainData.torosPools.USDY,
    destToken: ovmChainData.assets.usdcNative,
    slippageTolerance: 10,
    name: "USDY",
  },
  {
    poolDepositorAddress: "0xd857e322351dc56592e3d9181fbf65034ef4aef2",
    testPoolAddress: ovmChainData.torosPools.BTCBULL4X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "BTCBULL4X",
  },
  {
    poolDepositorAddress: "0xd857e322351dc56592e3d9181fbf65034ef4aef2",
    testPoolAddress: ovmChainData.torosPools.SOLBULL3X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "SOLBULL3X",
  },
  {
    poolDepositorAddress: "0x813123a13d01d3f07d434673fdc89cbba523f14d",
    testPoolAddress: ovmChainData.torosPools.USDpy,
    destToken: ovmChainData.assets.usdcNative,
    slippageTolerance: 10,
    name: "USDpy",
  },
  {
    poolDepositorAddress: "0xd857e322351dc56592e3d9181fbf65034ef4aef2",
    testPoolAddress: ovmChainData.torosPools.ETHY,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "ETHY",
  },
  {
    poolDepositorAddress: "0xd857e322351dc56592e3d9181fbf65034ef4aef2",
    testPoolAddress: ovmChainData.torosPools.BTCBULL3X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "BTCBULL3X",
  },
  {
    poolDepositorAddress: "0x813123a13d01d3f07d434673fdc89cbba523f14d",
    testPoolAddress: ovmChainData.torosPools.USDMNY,
    destToken: ovmChainData.assets.usdcNative,
    slippageTolerance: 10,
    name: "USDMNY",
  },
  {
    poolDepositorAddress: "0xd857e322351dc56592e3d9181fbf65034ef4aef2",
    testPoolAddress: ovmChainData.torosPools.ETHBULL3X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "ETHBULL3X",
  },
  {
    poolDepositorAddress: "0xd857e322351dc56592e3d9181fbf65034ef4aef2",
    testPoolAddress: ovmChainData.torosPools.BTCBULL2X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "BTCBULL2X",
  },
  {
    poolDepositorAddress: "0x0ac06e4d75dfbc630910be7ae98736a127d24c58",
    testPoolAddress: ovmChainData.torosPools.SUIBULL2X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "SUIBULL2X",
  },
  {
    poolDepositorAddress: "0xe9355f9ed880741086690719d525b31ec1845aa4",
    testPoolAddress: ovmChainData.torosPools.DOGEBULL2X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "DOGEBULL2X",
  },
  {
    poolDepositorAddress: "0xd857e322351dc56592e3d9181fbf65034ef4aef2",
    testPoolAddress: ovmChainData.torosPools.ETHBULL2X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "ETHBULL2X",
  },
  {
    poolDepositorAddress: "0x813123a13d01d3f07d434673fdc89cbba523f14d",
    testPoolAddress: ovmChainData.torosPools.BTCBEAR1X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "BTCBEAR1X",
  },
  {
    poolDepositorAddress: "0x813123a13d01d3f07d434673fdc89cbba523f14d",
    testPoolAddress: ovmChainData.torosPools.ETHBEAR1X,
    destToken: ovmChainData.assets.weth,
    slippageTolerance: 10,
    name: "ETHBEAR1X",
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
  onchainSwapRouter: "0x64a9c356bc131eDF1430C24F47e9dC735Ed237Ef",
});

runEasySwapperV2GuardsTest({
  ...ovmChainData,
  swapperAddress: ovmChainData.flatMoney.swapper,
  wrappedNativeToken: ovmChainData.assets.weth,
  chainId: 10,
});
