import { polygonChainData } from "../../../../config/chainData/polygonData";
import { units } from "../../../testHelpers";
import { runEasySwapperV2Tests, EasySwapperV2TestCase } from "../../common/easySwapperV2/EasySwapperV2Test";
import { runEasySwapperV2GuardsTest } from "../../common/easySwapperV2/EasySwapperV2GuardsTest";

// IMPORTANT: these are real vaults. poolDepositorAddress is not guaranteed to be depositor of testPoolAddress
const withdrawTestCases: EasySwapperV2TestCase[] = [
  {
    poolDepositorAddress: "0x4cbbf420fb8ae7f94452e5a30f361195a99b243c",
    testPoolAddress: polygonChainData.torosPools.BTCBEAR1X,
    destToken: polygonChainData.assets.usdcNative,
    slippageTolerance: 10,
    name: "Bitcoin Bear 1X",
  },
  {
    poolDepositorAddress: "0x6f005cbcec52ffb28af046fd48cb8d6d19fd25e3",
    testPoolAddress: polygonChainData.torosPools.BTCBULL3X,
    destToken: polygonChainData.assets.usdcNative,
    slippageTolerance: 10,
    name: "Bitcoin Bull 3X",
  },
  {
    poolDepositorAddress: "0x3a19a49aa38aba674ce1407d86c611143da4cb9f",
    testPoolAddress: polygonChainData.torosPools.ETHBEAR1X,
    destToken: polygonChainData.assets.usdcNative,
    slippageTolerance: 10,
    name: "Ethereum Bear 1X",
  },
  {
    poolDepositorAddress: "0x7b2dd278e8bb3b9481678ac91f19152fec398e42",
    testPoolAddress: polygonChainData.torosPools.ETHBULL3X,
    destToken: polygonChainData.assets.usdcNative,
    slippageTolerance: 10,
    name: "Ethereum Bull 3X",
  },
];

runEasySwapperV2Tests({
  ...polygonChainData,
  wrappedNativeToken: polygonChainData.assets.wmatic,
  swapperAddress: polygonChainData.flatMoney.swapper,
  baseTestPoolAddress: withdrawTestCases[0],
  withdrawTestCases,
  chainId: 137,
  depositsData: {
    poolDepositToken: {
      address: polygonChainData.assets.usdcNative,
      slot: polygonChainData.assetsBalanceOfSlot.usdcNative,
      amount: units(800, 6),
    },
    userDepositToken: {
      address: polygonChainData.assets.dai,
      slot: polygonChainData.assetsBalanceOfSlot.dai,
      amount: units(1_000),
    },
    nativeTokenWrapper: {
      address: polygonChainData.assets.wmatic,
      slot: polygonChainData.assetsBalanceOfSlot.wmatic,
      amount: units(1),
    },
  },
  poolFactory: "0xfdc7b8bFe0DD3513Cc669bB8d601Cb83e2F69cB0",
  onchainSwapRouter: "0xd4A9Fd5925bD85554D22C6359B83B4501A3ABa76",
});

runEasySwapperV2GuardsTest({
  ...polygonChainData,
  swapperAddress: polygonChainData.flatMoney.swapper,
  wrappedNativeToken: polygonChainData.assets.wmatic,
  chainId: 137,
});
