// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {KyberSwapRouterV2ContractGuardTestSetup} from "test/integration/common/kyberSwap/KyberSwapRouterV2ContractGuardTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/**
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract KyberSwapRouterV2ContractGuardTestFFIBase is KyberSwapRouterV2ContractGuardTestSetup, BaseSetup {
  uint256 private testForkBlockNumber = 37185190;

  constructor()
    KyberSwapRouterV2ContractGuardTestSetup(EthereumConfig.KYBER_SWAP_ROUTER_V2, BaseConfig.CHAIN_ID)
    BaseSetup(testForkBlockNumber)
  {}

  function setUp() public override(KyberSwapRouterV2ContractGuardTestSetup, BaseSetup) {
    super.setUp();
  }
}
