// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {KyberSwapRouterV2ContractGuardTestSetup} from "test/integration/common/kyberSwap/KyberSwapRouterV2ContractGuardTestSetup.t.sol";
import {PolygonSetup} from "test/integration/utils/foundry/chains/PolygonSetup.t.sol";
import {PolygonConfig} from "test/integration/utils/foundry/config/PolygonConfig.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/**
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract KyberSwapRouterV2ContractGuardTestFFIPolygon is KyberSwapRouterV2ContractGuardTestSetup, PolygonSetup {
  uint256 private testForkBlockNumber = 78027416;

  constructor()
    KyberSwapRouterV2ContractGuardTestSetup(EthereumConfig.KYBER_SWAP_ROUTER_V2, PolygonConfig.CHAIN_ID)
    PolygonSetup(testForkBlockNumber)
  {}

  function setUp() public override(KyberSwapRouterV2ContractGuardTestSetup, PolygonSetup) {
    super.setUp();
  }
}
