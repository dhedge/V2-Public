import { ovmChainData } from "../../../../config/chainData/ovm-data";
import { ArrakisV1RouterStakingGuardTest } from "../../common/arrakis/ArrakisV1RouterStakingGuardTest";

ArrakisV1RouterStakingGuardTest(
  "ovm",
  ovmChainData.arrakis,
  ovmChainData.assets.op,
  ovmChainData.assets,
  ovmChainData.assetsBalanceOfSlot,
);
