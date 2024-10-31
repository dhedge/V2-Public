import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import type { Wallet } from "ethers";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { Address } from "../../../deployment/types";
import {
  IERC20__factory,
  IRamsesNonfungiblePositionManager,
  IRamsesNonfungiblePositionManager__factory,
  PoolLogic,
} from "../../../types";
import { getAccountToken } from "./getAccountTokens";

const iERC20 = new ethers.utils.Interface(IERC20__factory.abi);
const iNonfungiblePositionManager = new ethers.utils.Interface(IRamsesNonfungiblePositionManager__factory.abi);
const deadLine = Math.floor(Date.now() / 1000 + 100000000);
export interface RamsesCLMintSettings {
  token0: Address;
  token1: Address;
  fee: number;
  amount0: BigNumber;
  amount1: BigNumber;
  tickLower: number;
  tickUpper: number;
  veRamTokenId?: number;
}

export const mintLpAsUser = async (
  nonfungiblePositionManager: IRamsesNonfungiblePositionManager,
  user: Wallet | SignerWithAddress,
  mintSettings: RamsesCLMintSettings,
  assetSlots = [0, 0],
) => {
  const token0 = mintSettings.token0;
  const token1 = mintSettings.token1;
  const fee = mintSettings.fee;
  const amount0 = mintSettings.amount0;
  const amount1 = mintSettings.amount1;
  const tickLower = mintSettings.tickLower;
  const tickUpper = mintSettings.tickUpper;
  const veRamTokenId = mintSettings.veRamTokenId || 0;

  await getAccountToken(amount0, user.address, token0, assetSlots[0]);
  await getAccountToken(amount1, user.address, token1, assetSlots[1]);
  // Approve nft manager to take tokens
  const token0Contract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token0);
  await token0Contract.connect(user).approve(nonfungiblePositionManager.address, amount0);
  const token1Contract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token1);
  await token1Contract.connect(user).approve(nonfungiblePositionManager.address, amount1);

  await nonfungiblePositionManager.connect(user).mint({
    token0,
    token1,
    fee,
    tickLower,
    tickUpper,
    amount0Desired: amount0,
    amount1Desired: amount1,
    amount0Min: 0,
    amount1Min: 0,
    recipient: user.address,
    deadline: deadLine,
    veRamTokenId, // default to 0
  });
  await ethers.provider.send("evm_mine", []);
};

/**
 * Mints Uni v3 LP for the pool from the manager
 * @param poolLogicProxy poolLogicProxy contract
 * @param manager Manager address
 * @param mintSettings LP configuration
 * @param approveTokens Approval of underlying tokens for transfer
 */
export const mintLpAsPool = async (
  nonfungiblePositionManager: Address,
  poolLogicProxy: PoolLogic,
  manager: SignerWithAddress,
  mintSettings: RamsesCLMintSettings,
  approveTokens = false,
) => {
  const token0 = mintSettings.token0;
  const token1 = mintSettings.token1;
  const fee = mintSettings.fee;
  const amount0 = mintSettings.amount0;
  const amount1 = mintSettings.amount1;
  const tickLower = mintSettings.tickLower;
  const tickUpper = mintSettings.tickUpper;
  const veRamTokenId = mintSettings.veRamTokenId || 0;

  if (approveTokens) {
    const approve0ABI = iERC20.encodeFunctionData("approve", [nonfungiblePositionManager, amount0]);
    await poolLogicProxy.connect(manager).execTransaction(token0, approve0ABI);
    const approve1ABI = iERC20.encodeFunctionData("approve", [nonfungiblePositionManager, amount1]);
    await poolLogicProxy.connect(manager).execTransaction(token1, approve1ABI);
  }

  const mintABI = iNonfungiblePositionManager.encodeFunctionData("mint", [
    [token0, token1, fee, tickLower, tickUpper, amount0, amount1, 0, 0, poolLogicProxy.address, deadLine, veRamTokenId],
  ]);
  await ethers.provider.send("evm_mine", []);

  await poolLogicProxy.connect(manager).execTransaction(nonfungiblePositionManager, mintABI);
};
