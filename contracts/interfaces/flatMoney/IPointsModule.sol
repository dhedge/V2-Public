// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IFlatcoinVault} from "./IFlatcoinVault.sol";

interface IPointsModule {
  struct MintPoints {
    address to;
    uint256 amount;
  }

  function balanceOf(address owner) external view returns (uint256);

  function getUnlockTax(address account) external view returns (uint256 unlockTax);

  function unlock(uint256 amount) external;

  function mintTo(MintPoints memory _mintPoints) external;

  function vault() external view returns (IFlatcoinVault vaultAddress);
}
