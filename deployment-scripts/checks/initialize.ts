import ProxyAdmin from "@openzeppelin/contracts/build/contracts/ProxyAdmin.json";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import fs from "fs";

import { IVersions } from "../types";
import { getTag } from "../Helpers";
import { polygonProdFileNames, polygonStagingFileNames } from "../polygon/deployment-data";
import { ovmProdFileNames } from "../ovm/deployment-data";

type Awaited<T> = T extends PromiseLike<infer U> ? U : T;
export type InitType = Awaited<ReturnType<typeof init>>;

export const init = async (environment: string, deployedVersion = "", hre: HardhatRuntimeEnvironment) => {
  const { ethers, artifacts } = hre;
  console.log("Initializing contracts and variables..", environment);

  const { versionsFileName, assetsFileName, namesFileName, assetGuardsFileName, contractGuardsFileName } =
    await getEnvironmentFiles(environment);

  const { proxyAdminOwner, proxyAdminAddress, protocolDao, protocolTreasury, balancerV2VaultAddress } =
    await getEnvironmentContracts(environment);

  const versions: IVersions = JSON.parse(fs.readFileSync(versionsFileName, "utf-8"));
  let version;
  const signer = (await ethers.getSigners())[0];
  if (!deployedVersion) {
    version = await getTag();
  } else {
    version = deployedVersion;
  }

  const PoolFactoryProxy = await ethers.getContractFactory("PoolFactory");
  const PoolFactory = PoolFactoryProxy;
  const Governance = await ethers.getContractFactory("Governance");
  const AssetHandlerProxy = await ethers.getContractFactory("AssetHandler");
  const AssetHandler = AssetHandlerProxy;
  const SushiLPAssetGuard = await ethers.getContractFactory("SushiLPAssetGuard");
  const PoolLogic = await ethers.getContractFactory("PoolLogic");
  const PoolManagerLogic = await ethers.getContractFactory("PoolManagerLogic");
  const OpenAssetGuard = await ethers.getContractFactory("OpenAssetGuard");
  const QuickLPAssetGuard = await ethers.getContractFactory("QuickLPAssetGuard");

  let contracts;
  try {
    contracts = versions[version].contracts;
  } catch (error) {
    throw `Couldn't get version ${version} from the published versions JSON file. Try using "--v v2.X.Y" in the command to specify existing deployed version.`;
  }

  // create contract instances
  const proxyAdmin = new ethers.Contract(proxyAdminAddress, ProxyAdmin.abi, signer);
  contracts["ProxyAdmin"] = proxyAdminAddress;

  const poolFactoryProxy = PoolFactoryProxy.attach(contracts.PoolFactoryProxy);
  const poolFactoryAddress = await proxyAdmin.getProxyImplementation(poolFactoryProxy.address);
  const poolFactory = PoolFactory.attach(poolFactoryAddress);
  contracts["PoolFactory"] = poolFactoryAddress;

  const assetHandlerProxy = AssetHandler.attach(contracts.AssetHandlerProxy);
  const assetHandlerAddress = await proxyAdmin.getProxyImplementation(assetHandlerProxy.address);
  const assetHandler = AssetHandler.attach(assetHandlerAddress);
  contracts["AssetHandler"] = assetHandlerAddress;

  const governance = Governance.attach(contracts.Governance);
  const sushiLPAssetGuard = contracts.SushiLPAssetGuard && SushiLPAssetGuard.attach(contracts.SushiLPAssetGuard);
  let quickLPAssetGuard;
  if (contracts.QuickLPAssetGuard) {
    quickLPAssetGuard = contracts.SushiLPAssetGuard && QuickLPAssetGuard.attach(contracts.QuickLPAssetGuard);
  }

  const poolLogic = PoolLogic.attach((contracts.PoolLogic && contracts.PoolLogic) || contracts.PoolLogic);
  const poolManagerLogic = PoolManagerLogic.attach(
    (contracts.PoolManagerLogic && contracts.PoolManagerLogic) || contracts.PoolManagerLogic,
  );
  const openAssetGuard = contracts.OpenAssetGuard && OpenAssetGuard.attach(contracts.OpenAssetGuard);
  const oneInchV4Guard = contracts.OneInchV4Guard && OpenAssetGuard.attach(contracts.OneInchV4Guard);
  const balancerV2Guard = contracts.BalancerV2Guard && OpenAssetGuard.attach(contracts.BalancerV2Guard);

  const IBalancerV2Vault = await artifacts.readArtifact("IBalancerV2Vault");
  const balancerV2Vault =
    (balancerV2VaultAddress && (await ethers.getContractAt(IBalancerV2Vault.abi, balancerV2VaultAddress))) || undefined;

  console.log("PoolFactory Implementation:", poolFactoryAddress);
  console.log("PoolLogic Implementation:", poolLogic.address);
  console.log("PoolManagerLogic Implementation:", poolManagerLogic.address);

  console.log("Initialization complete!");
  console.log("_________________________________________");

  return {
    assetsFileName,
    balancerV2Vault,
    namesFileName,
    assetGuardsFileName,
    contractGuardsFileName,
    versions,
    version,
    signer,
    protocolDao,
    protocolTreasury,
    contracts,
    proxyAdmin,
    proxyAdminOwner,
    poolFactoryProxy,
    poolFactory,
    assetHandlerProxy,
    assetHandler,
    governance,
    sushiLPAssetGuard,
    quickLPAssetGuard,
    balancerV2Guard,
    poolLogic,
    poolManagerLogic,
    openAssetGuard,
    oneInchV4Guard,
  };
};

const getEnvironmentFiles = async (environment: string) => {
  let versionsFileName, assetsFileName, namesFileName, assetGuardsFileName, contractGuardsFileName;

  switch (environment) {
    case "polygon":
      versionsFileName = polygonProdFileNames.versionsFileName;
      assetsFileName = polygonProdFileNames.assetsFileName;
      namesFileName = polygonProdFileNames.governanceNamesFileName;
      assetGuardsFileName = polygonProdFileNames.assetGuardsFileName;
      contractGuardsFileName = polygonProdFileNames.contractGuardsFileName;
      break;

    case "staging":
      versionsFileName = polygonStagingFileNames.versionsFileName;
      assetsFileName = polygonStagingFileNames.assetsFileName;
      namesFileName = polygonStagingFileNames.governanceNamesFileName;
      assetGuardsFileName = polygonStagingFileNames.assetGuardsFileName;
      contractGuardsFileName = polygonStagingFileNames.contractGuardsFileName;
      break;

    case "ovm":
      versionsFileName = "../../publish/ovm/prod/versions.json";
      assetsFileName = ovmProdFileNames.assetsFileName;
      namesFileName = ovmProdFileNames.governanceNamesFileName;
      assetGuardsFileName = ovmProdFileNames.assetGuardsFileName;
      contractGuardsFileName = ovmProdFileNames.contractGuardsFileName;
      break;

    default:
      throw "Invalid environment input. Should be 'prod' or 'staging'.";
  }
  return {
    versionsFileName,
    assetsFileName,
    namesFileName,
    assetGuardsFileName,
    contractGuardsFileName,
  };
};

const getEnvironmentContracts = async (environment: string) => {
  let proxyAdminOwner, protocolDao, proxyAdminAddress, protocolTreasury, balancerV2VaultAddress;

  switch (environment) {
    case "polygon":
      proxyAdminOwner = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
      proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
      protocolDao = proxyAdminOwner;
      protocolTreasury = "0x6f005cbceC52FFb28aF046Fd48CB8D6d19FD25E3";
      balancerV2VaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
      break;

    case "staging":
      proxyAdminOwner = "0xc715Aa67866A2FEF297B12Cb26E953481AeD2df4";
      proxyAdminAddress = "0x0C0a10C9785a73018077dBC74B2A006695849252";
      protocolDao = proxyAdminOwner;
      protocolTreasury = "0x51150F973c2b0537642f5AE8911A49567598808f";
      balancerV2VaultAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
      break;

    case "ovm":
      protocolDao = "0xeB03C960EC60b2159B3EcCfb341cE8d7e1268B08";
      proxyAdminOwner = "0xef31D75A2f85CfDD9032158A2CEB773C84d79192";
      proxyAdminAddress = "0x9FEE88a18479bf7f0D41Da03819538AA7A617730";
      protocolTreasury = "0x2b0763A33b4D3DC8D6c1A4916D0f9467d6E11FFc";
      break;

    default:
      throw "Invalid environment input.";
  }
  return { proxyAdminOwner, proxyAdminAddress, protocolDao, protocolTreasury, balancerV2VaultAddress };
};
