// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {KyberSwapRouterV2ContractGuardTestSetup} from "test/integration/common/kyberSwap/KyberSwapRouterV2ContractGuardTestSetup.t.sol";
import {PlasmaSetup} from "test/integration/utils/foundry/chains/PlasmaSetup.t.sol";
import {PlasmaConfig} from "test/integration/utils/foundry/config/PlasmaConfig.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/**
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract KyberSwapRouterV2ContractGuardTestFFIPlasma is KyberSwapRouterV2ContractGuardTestSetup, PlasmaSetup {
  uint256 private testForkBlockNumber = 3968830;

  constructor()
    KyberSwapRouterV2ContractGuardTestSetup(EthereumConfig.KYBER_SWAP_ROUTER_V2, PlasmaConfig.CHAIN_ID)
    PlasmaSetup(testForkBlockNumber)
  {}

  function setUp() public override(KyberSwapRouterV2ContractGuardTestSetup, PlasmaSetup) {
    super.setUp();
  }
}
