// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import {IVelodromeCLFactory} from "../../interfaces/velodrome/IVelodromeCLFactory.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/// @title Provides functions for deriving a pool address from the factory, tokens, and the fee
library PoolAddress {
  /// @notice The identifying key of the pool
  struct PoolKey {
    address token0;
    address token1;
    int24 tickSpacing;
  }

  /// @notice Deterministically computes the pool address given the factory and PoolKey
  /// @param factory The CL factory contract address
  /// @param key The PoolKey
  /// @return pool The contract address of the V3 pool
  function computeAddress(address factory, PoolKey memory key) internal view returns (address pool) {
    require(key.token0 < key.token1, "token0 not less than token1");
    pool = Clones.predictDeterministicAddress({
      master: IVelodromeCLFactory(factory).poolImplementation(),
      salt: keccak256(abi.encode(key.token0, key.token1, key.tickSpacing)),
      deployer: factory
    });
  }
}
