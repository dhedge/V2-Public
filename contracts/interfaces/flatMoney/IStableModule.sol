// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20Extended} from "../IERC20Extended.sol";
import {IFlatcoinVault} from "./IFlatcoinVault.sol";

interface IStableModule is IERC20Extended {
  struct AnnouncedStableDeposit {
    uint256 depositAmount;
    uint256 minAmountOut;
    address announcedBy;
  }

  function vault() external view returns (IFlatcoinVault vaultAddress);

  function executeDeposit(
    address account,
    uint64 executableAtTime,
    AnnouncedStableDeposit calldata announcedDeposit
  ) external returns (uint256 liquidityMinted);
}
