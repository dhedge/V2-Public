import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  AssetHandler,
  Governance,
  IERC20,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  PoolPerformance,
  SushiMiniChefV2Guard,
} from "../../../../types";

export type Deployments = {
  logicOwner: SignerWithAddress;
  manager: SignerWithAddress;
  dao: SignerWithAddress;
  user: SignerWithAddress;
  governance: Governance;
  assetHandler: AssetHandler;
  poolFactory: PoolFactory;
  poolLogic: PoolLogic;
  poolManagerLogic: PoolManagerLogic;
  poolPerformance: PoolPerformance;
  sushiMiniChefV2Guard: SushiMiniChefV2Guard;
  assets: {
    [name: string]: IERC20;
  };
};
