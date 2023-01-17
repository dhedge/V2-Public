import { ArrakisLiquidityGaugeV4ContractGuardTest } from "../../common/arrakis/ArrakisLiquidityGaugeV4GuardTest";
import { polygonChainData } from "../../../../config/chainData/polygon-data";

ArrakisLiquidityGaugeV4ContractGuardTest(
  "polygon",
  polygonChainData.arrakis,
  polygonChainData.assets.wmatic,
  polygonChainData.assets,
  polygonChainData.assetsBalanceOfSlot,
);
