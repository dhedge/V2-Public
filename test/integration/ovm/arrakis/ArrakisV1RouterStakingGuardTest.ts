import { ovmChainData } from "../../../../config/chainData/ovmData";
import { ArrakisV1RouterStakingGuardTest } from "../../common/arrakis/ArrakisV1RouterStakingGuardTest";

ArrakisV1RouterStakingGuardTest(
  "ovm",
  ovmChainData.arrakis,
  ovmChainData.assets.op,
  ovmChainData.assets,
  ovmChainData.assetsBalanceOfSlot,
);
