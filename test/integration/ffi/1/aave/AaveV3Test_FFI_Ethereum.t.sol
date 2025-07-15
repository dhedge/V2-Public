// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3TestEthereum} from "test/integration/ethereum/aaveV3/AaveV3TestEthereum.t.sol";
import {AaveV3TestFFI} from "test/integration/ffi/common/aave/AaveV3TestFFI.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract AaveV3TestFFIEthereum is AaveV3TestFFI, AaveV3TestEthereum {
  constructor() AaveV3TestFFI(EthereumConfig.CHAIN_ID) AaveV3TestEthereum() {}

  function setUp() public override(AaveV3TestFFI, AaveV3TestEthereum) {
    super.setUp();
  }
}
