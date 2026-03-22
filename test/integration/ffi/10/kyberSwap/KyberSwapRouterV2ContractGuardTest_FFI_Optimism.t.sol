// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {KyberSwapRouterV2ContractGuardTestSetup} from "test/integration/common/kyberSwap/KyberSwapRouterV2ContractGuardTestSetup.t.sol";
import {OptimismSetup} from "test/integration/utils/foundry/chains/OptimismSetup.t.sol";
import {OptimismConfig} from "test/integration/utils/foundry/config/OptimismConfig.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/**
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract KyberSwapRouterV2ContractGuardTestFFIOptimism is KyberSwapRouterV2ContractGuardTestSetup, OptimismSetup {
  uint256 private testForkBlockNumber = 142780402;

  constructor()
    KyberSwapRouterV2ContractGuardTestSetup(EthereumConfig.KYBER_SWAP_ROUTER_V2, OptimismConfig.CHAIN_ID)
    OptimismSetup(testForkBlockNumber)
  {}

  function setUp() public override(KyberSwapRouterV2ContractGuardTestSetup, OptimismSetup) {
    super.setUp();
  }
}
