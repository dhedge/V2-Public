import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  AssetHandler,
  DhedgeEasySwapper,
  Governance,
  IERC20,
  PoolFactory,
  PoolLogic,
  PoolManagerLogic,
  PoolPerformance,
  SushiMiniChefV2Guard,
  UniswapV3AssetGuard,
} from "../../../../types";

export type IDeployments = {
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
  sushiMiniChefV2Guard?: SushiMiniChefV2Guard;
  dhedgeEasySwapper?: DhedgeEasySwapper;
  uniV3AssetGuard: UniswapV3AssetGuard;
  assets: {
    [name: string]: IERC20;
  };
};
