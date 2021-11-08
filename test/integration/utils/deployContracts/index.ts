import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { IERC20, PoolFactory, PoolLogic, PoolManagerLogic } from "../../../../types";
import { deployPolygonContracts } from "./deployPolygonContracts";

export type Deployments = {
  logicOwner: SignerWithAddress;
  manager: SignerWithAddress;
  dao: SignerWithAddress;
  user: SignerWithAddress;
  poolFactory: PoolFactory;
  poolLogic: PoolLogic;
  poolManagerLogic: PoolManagerLogic;
  assets: {
    [name: string]: IERC20;
  };
};
