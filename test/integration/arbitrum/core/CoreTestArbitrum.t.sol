// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {EntryExitFeesTestSetup} from "test/integration/common/core/EntryExitFeesTestSetup.t.sol";
import {MaxSupplyCapTestSetup} from "test/integration/common/core/MaxSupplyCapTestSetup.t.sol";
import {PoolPrivacyTestSetup} from "test/integration/common/core/PoolPrivacyTestSetup.t.sol";
import {ReferralSystemTestSetup} from "test/integration/common/core/ReferralSystemTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract CoreTestArbitrum is
  MaxSupplyCapTestSetup,
  EntryExitFeesTestSetup,
  PoolPrivacyTestSetup,
  ReferralSystemTestSetup,
  ArbitrumSetup
{
  constructor()
    MaxSupplyCapTestSetup()
    EntryExitFeesTestSetup()
    PoolPrivacyTestSetup()
    ReferralSystemTestSetup()
    ArbitrumSetup(434809736)
  {}

  function setUp()
    public
    virtual
    override(
      MaxSupplyCapTestSetup,
      EntryExitFeesTestSetup,
      PoolPrivacyTestSetup,
      ReferralSystemTestSetup,
      ArbitrumSetup
    )
  {
    super.setUp();
  }
}
