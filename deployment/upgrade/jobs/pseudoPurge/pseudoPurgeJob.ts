import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IJob, IAddresses, IUpgradeConfig, IVersions, IFileNames } from "../../../types";
import { proposeTransactions } from "../../../deploymentHelpers";
import type { MetaTransactionData } from "../../../deploymentHelpers";

const DHT_POLYGON_ADDRESS = "0x8C92e38eCA8210f4fcBf17F0951b198Dd7668292";
const USDCe_BRIDGED_POLYGON_ADDRESS = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const USDC_NATIVE_POLYGON_ADDRESS = "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359";
const POLYGON_POOL_FACTORY_ADDRESS = "0xfdc7b8bFe0DD3513Cc669bB8d601Cb83e2F69cB0";

const VAULTS_CONTAINING_DHT_POLYGON: string[] = [
  "0xf6707FF531d0d0B7f2228693dE46f04b4A387AD1",
  "0x6d0E4986377CE0296dB8381cF1f33D5356409fA1",
  "0xFB3A577c8e35830A51CFfAB8fB4E6B0C514351Ca",
  "0x16FF9d530B040fB19fC9ed22FB84E3dc5456cD1C",
  "0x00c22A22099b3c7C92F34CDaAa72FCdF9Ea1dB62",
  "0x9Cf63fd0324a353bbb60958fa21C617e3CC5533d",
  "0x7314F0cc07e245F950EDf3BDc4c3ff4cB7b9f967",
  "0xb97b78ED6aDC6c73B0B01E0b8C2db0b99BfC90e1",
  "0xf758bB0b354c4a4CA641d49B12C6D048df050242",
  "0xD102531Bc3E363e4eB2df9dEd41ECaCe2D467A59",
  "0xC2Ff45D0233F83025a53150ebdE11cb64Db03557",
  "0xC4719ffb9F3DA1e9A76A2d818EC38e79867173eF",
  "0x65c433DFA00D6219Bd94B66628530970c8a5A45B",
  "0xb51C0BD85f2F1617D83082E48D7F6fea7487B52B",
  "0x301C1DD7490e680467062e6B9ae59817afDE6631",
  "0x641478410e0c002Cb078708d4755633Fc45209d0",
  "0xa29346b34F6BcDf27678892703C680065F4bf277",
  "0x20a0A3a96f441864DCac14172aD72c963b615BB3",
  "0x01D062C37B64e181b403A5F4E18D9BBCb3491a91",
  "0x59E19A65c8eC541a352D662e0Bdb27E12C4aEba5",
  "0xDB271aDA1dd90d0979b549f073C8c9d28E2152Ab",
  "0x4B3c0E09baB20B9BbdCcD9b203100e4AE5312199",
  "0x67a47d14754909f1d2645919C79E3cFa23F439a2",
  "0x3C9703a33b52B792de05E1312D7eB0Ba53b6FD18",
  "0x5aa455edE504711DfefdD6811d6646f683874f1E",
  "0x502143702b0094FFE5ce1E11E1e642831f5B74e6",
  "0x3456105Cd7de22c494a3569EA78364C57BE5aD05",
  "0x89c47A06aba1aBf432A354e07Dd44C3a9d0DE055",
  "0x1eB4aE5f3e738E6FCf93fC55d2B09B985EeB9faF",
  "0xD2FF730e5c0fF7B2795E7cE9542D5fa0d05A444c",
  "0x7341D6bE91f23a3928e75486e2F08eB338808669",
  "0x1326145E6cb4F5c37E30c29487017e6422dF88b3",
  "0xceac05E35d9d928168B8a9c990Baeb3b921B0c97",
  "0x005F75bA549AA50D9fefB00961937649cc46d0ac",
  "0x230fcf85a7BA9C66ff754d5708b972285D57D08b",
  "0x2A09812DbbA5dD84a4a63038b1cc65F5f7e9229D",
  "0xCA9b305378359c2df2AD3406706BA28a3e00D454",
  "0x03f4BB2A158F84B9c028f60803e7b0DdCF697859",
  "0xc883A793C30C85367724C36762E90CcD6D218f3A",
  "0x44aE588Da95057b3033B94b552674fd1260f24c2",
  "0xcaeF1050bc9623d02D644F5335a5A6Db178cF362",
  "0x289FfCCaE2540e6DF149d0ED6D73793D1Fb53852",
  "0x97B7De1bC7Ee676A13737910e209Cc49B2D7d5B6",
  "0x4ad9448De5A3062a9C8BCdA753c9d1e5e2b7d110",
  "0x7A8f635B56916163901665D8dcf63E6Bd2FBF05C",
  "0x34358e00aAcAF1071C832266859B64B085A1C1ae",
  "0x0693Ef3A503c3653538963cC0A58E897a3CB0501",
  "0x0EF9975eb648CEe69246bBD0114ADd9aD307F6bB",
  "0xeB0B19E60a023f8118A287d30702944271b705d2",
  "0x705Ad85c3c3A065bC87C49598E1Dd2F1B9324663",
  "0xcd2E1179dBBb98Dd89F0Cd008eb2D59848300793",
  "0x1B1f4C10de7F6C365fc87937582832057Fa12726",
  "0x11D847c1089c28B81Cb953b05040448dc951C6b1",
];

export const pseudoPurgeJob: IJob<void> = async (
  config: IUpgradeConfig,
  hre: HardhatRuntimeEnvironment,
  _: IVersions,
  __: IFileNames,
  addresses: IAddresses,
) => {
  console.log("Running Pseudo Purge Job...");

  if (!VAULTS_CONTAINING_DHT_POLYGON.length) return console.warn("No vaults provided!");

  const ethers = hre.ethers;

  const DHT_BALANCE_THRESHOLD = ethers.BigNumber.from(10).mul(ethers.BigNumber.from(10).pow(18)); // 10 DHT ~ around 80 cents

  const dhtContract = await ethers.getContractAt("IERC20", DHT_POLYGON_ADDRESS);
  const poolFactoryContract = await ethers.getContractAt("PoolFactory", POLYGON_POOL_FACTORY_ADDRESS);
  const dhtPriceD18 = await poolFactoryContract.getAssetPrice(DHT_POLYGON_ADDRESS);
  const usdcPriceD18 = await poolFactoryContract.getAssetPrice(USDC_NATIVE_POLYGON_ADDRESS);

  let totalUsdceToTransfer = ethers.BigNumber.from(0);
  let totalUsdcToTransfer = ethers.BigNumber.from(0);

  const transactionsList = await Promise.all(
    VAULTS_CONTAINING_DHT_POLYGON.map<Promise<MetaTransactionData[] | MetaTransactionData | undefined>>(
      async (vaultAddress) => {
        const balanceD18 = await dhtContract.balanceOf(vaultAddress);

        // Do nothing if vault contains less that threshold amount, it's negligible
        if (balanceD18.lte(DHT_BALANCE_THRESHOLD)) return;

        const poolLogicContract = await ethers.getContractAt("PoolLogic", vaultAddress);
        const poolManagerLogicContractAddress = await poolLogicContract.poolManagerLogic();
        const poolManagerLogicContract = await ethers.getContractAt(
          "PoolManagerLogic",
          poolManagerLogicContractAddress,
        );

        const usdAmountToTransferD6 = balanceD18
          .mul(dhtPriceD18)
          .div(usdcPriceD18)
          .div(ethers.BigNumber.from(10).pow(12));

        const usdcBridgedSupported = await poolManagerLogicContract.isSupportedAsset(USDCe_BRIDGED_POLYGON_ADDRESS);

        if (usdcBridgedSupported) {
          totalUsdceToTransfer = totalUsdceToTransfer.add(usdAmountToTransferD6);
          return {
            to: USDCe_BRIDGED_POLYGON_ADDRESS,
            value: "0",
            data: dhtContract.interface.encodeFunctionData("transfer", [vaultAddress, usdAmountToTransferD6]),
          };
        }

        const usdcNativeSupported = await poolManagerLogicContract.isSupportedAsset(USDC_NATIVE_POLYGON_ADDRESS);

        if (usdcNativeSupported) {
          totalUsdcToTransfer = totalUsdcToTransfer.add(usdAmountToTransferD6);
          return {
            to: USDC_NATIVE_POLYGON_ADDRESS,
            value: "0",
            data: dhtContract.interface.encodeFunctionData("transfer", [vaultAddress, usdAmountToTransferD6]),
          };
        }

        totalUsdcToTransfer = totalUsdcToTransfer.add(usdAmountToTransferD6);
        // If neither USDCe nor USDC is supported, we need to add USDC before transferring it so vault can account for it
        return [
          {
            to: poolManagerLogicContractAddress,
            value: "0",
            data: poolManagerLogicContract.interface.encodeFunctionData("changeAssets", [
              [{ asset: USDC_NATIVE_POLYGON_ADDRESS, isDeposit: false }],
              [],
            ]),
          },
          {
            to: USDC_NATIVE_POLYGON_ADDRESS,
            value: "0",
            data: dhtContract.interface.encodeFunctionData("transfer", [vaultAddress, usdAmountToTransferD6]),
          },
        ];
      },
    ),
  );

  const safeTransactionData = transactionsList
    .flat()
    .filter((txData): txData is MetaTransactionData => txData !== undefined);

  console.log("Total USDCe required: ", totalUsdceToTransfer);
  console.log("Total USDC required: ", totalUsdcToTransfer);

  if (config.execute && safeTransactionData.length !== 0) {
    await proposeTransactions(safeTransactionData, "Pseudo Purge", config, addresses);
  }
};
