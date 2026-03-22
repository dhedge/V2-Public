// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosLimitOrdersTestSetup} from "test/integration/common/odos/OdosLimitOrdersTestSetup.t.sol";
import {BaseSetup} from "test/integration/utils/foundry/chains/BaseSetup.t.sol";

contract OdosLimitOrdersTestBase is OdosLimitOrdersTestSetup, BaseSetup {
  uint256 public constant TEST_FORK_BLOCK_NUMBER = 39261342;
  address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
  address public constant ODOS_LIMIT_ORDER_ROUTER = 0xeDeAfdEf0901eF74Ee28c207BE8424D3B353D97A;

  constructor() OdosLimitOrdersTestSetup(PERMIT2, ODOS_LIMIT_ORDER_ROUTER) BaseSetup(TEST_FORK_BLOCK_NUMBER) {}

  function setUp() public override(OdosLimitOrdersTestSetup, BaseSetup) {
    super.setUp();
  }
}
