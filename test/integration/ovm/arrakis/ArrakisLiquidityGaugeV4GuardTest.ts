import { ovmChainData } from "../../../../config/chainData/ovmData";
import { ArrakisLiquidityGaugeV4ContractGuardTest } from "../../common/arrakis/ArrakisLiquidityGaugeV4GuardTest";

ArrakisLiquidityGaugeV4ContractGuardTest(
  "ovm",
  ovmChainData.arrakis,
  ovmChainData.assets.op,
  ovmChainData.assets,
  ovmChainData.assetsBalanceOfSlot,
);
