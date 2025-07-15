// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3USDeJUL25TestEthereum} from "test/integration/ethereum/aaveV3/AaveV3USDeJUL25TestEthereum.t.sol";
import {AaveV3TestFFI} from "test/integration/ffi/common/aave/AaveV3TestFFI.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract AaveV3USDeJUL25TestFFIEthereum is AaveV3TestFFI, AaveV3USDeJUL25TestEthereum {
  constructor() AaveV3TestFFI(EthereumConfig.CHAIN_ID) AaveV3USDeJUL25TestEthereum() {}

  function setUp() public override(AaveV3TestFFI, AaveV3USDeJUL25TestEthereum) {
    super.setUp();
  }
}
