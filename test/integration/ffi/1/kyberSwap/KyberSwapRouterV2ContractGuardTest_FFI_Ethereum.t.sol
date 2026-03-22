// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {KyberSwapRouterV2ContractGuardTestSetup} from "test/integration/common/kyberSwap/KyberSwapRouterV2ContractGuardTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

/**
 * @dev This contract requires the FFI flag to be enabled in Foundry
 */
contract KyberSwapRouterV2ContractGuardTestFFIEthereum is KyberSwapRouterV2ContractGuardTestSetup, EthereumSetup {
  uint256 private testForkBlockNumber = 23634994;

  constructor()
    KyberSwapRouterV2ContractGuardTestSetup(EthereumConfig.KYBER_SWAP_ROUTER_V2, EthereumConfig.CHAIN_ID)
    EthereumSetup(testForkBlockNumber)
  {}

  function setUp() public override(KyberSwapRouterV2ContractGuardTestSetup, EthereumSetup) {
    super.setUp();
  }
}
