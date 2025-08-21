// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {AaveV3sUSDeSEP25TestEthereum} from "test/integration/ethereum/aaveV3/AaveV3sUSDeSEP25TestEthereum.t.sol";
import {AaveV3TestFFI} from "test/integration/ffi/common/aave/AaveV3TestFFI.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

contract AaveV3sUSDeSEP25TestFFIEthereum is AaveV3TestFFI, AaveV3sUSDeSEP25TestEthereum {
  constructor() AaveV3TestFFI(EthereumConfig.CHAIN_ID) AaveV3sUSDeSEP25TestEthereum() {}

  function setUp() public override(AaveV3TestFFI, AaveV3sUSDeSEP25TestEthereum) {
    super.setUp();
  }

  function test_can_withdraw_from_pool_with_two_assets_supplied_and_one_borrowed_in_aave_v3_with_swapdata() public {
    can_withdraw_from_pool_with_assets_supplied_and_borrowed_in_aave_v3_with_swapdata(block.timestamp + 1 days, true);
  }
}
