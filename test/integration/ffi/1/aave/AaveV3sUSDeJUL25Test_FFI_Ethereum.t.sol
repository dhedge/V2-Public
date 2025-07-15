// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3sUSDeJUL25TestEthereum} from "test/integration/ethereum/aaveV3/AaveV3sUSDeJUL25TestEthereum.t.sol";
import {AaveV3TestFFI} from "test/integration/ffi/common/aave/AaveV3TestFFI.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract AaveV3sUSDeJUL25TestFFIEthereum is AaveV3TestFFI, AaveV3sUSDeJUL25TestEthereum {
  constructor() AaveV3TestFFI(EthereumConfig.CHAIN_ID) AaveV3sUSDeJUL25TestEthereum() {}

  function setUp() public override(AaveV3TestFFI, AaveV3sUSDeJUL25TestEthereum) {
    super.setUp();
  }
}
