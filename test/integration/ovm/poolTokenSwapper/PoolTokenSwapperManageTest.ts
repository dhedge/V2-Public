import { ovmChainData as chainData } from "../../../../config/chainData/ovmData";
import { testPoolTokenSwapperManage } from "../../common/poolTokenSwapper/PoolTokenSwapperManageTest";
import versionsUntyped from "../../../../publish/ovm/prod/versions.json";
import { IVersions } from "../../../../deployment/types";

const versions = versionsUntyped as unknown as IVersions;
const latestVersion = Object.keys(versions)[Object.keys(versions).length - 1];
const poolFactory = versions[latestVersion].contracts.PoolFactoryProxy;
const easySwapper = versions[latestVersion].contracts.DhedgeEasySwapperProxy;
const assetHandler = versions[latestVersion].contracts.AssetHandlerProxy;

testPoolTokenSwapperManage([
  {
    network: "ovm",
    chainData,
    poolFactory,
    easySwapper,
    assetHandler,
    assets: [
      {
        name: "USDy",
        type: "pool",
        swapFee: 10, // 0.1%
        address: chainData.torosPools.USDY,
        balanceOfSlot: 0,
        decimals: 18,
      },
    ],
  },
]);
