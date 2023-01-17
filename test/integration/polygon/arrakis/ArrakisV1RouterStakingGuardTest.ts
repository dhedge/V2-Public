import { ArrakisV1RouterStakingGuardTest } from "../../common/arrakis/ArrakisV1RouterStakingGuardTest";
import { polygonChainData } from "../../../../config/chainData/polygon-data";

ArrakisV1RouterStakingGuardTest(
  "polygon",
  polygonChainData.arrakis,
  polygonChainData.assets.wmatic,
  polygonChainData.assets,
  polygonChainData.assetsBalanceOfSlot,
);
