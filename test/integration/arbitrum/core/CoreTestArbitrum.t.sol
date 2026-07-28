// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {EntryExitFeesTestSetup} from "test/integration/common/core/EntryExitFeesTestSetup.t.sol";
import {MaxPriceAgeTestSetup} from "test/integration/common/core/MaxPriceAgeTestSetup.t.sol";
import {MaxSupplyCapTestSetup} from "test/integration/common/core/MaxSupplyCapTestSetup.t.sol";
import {PoolPrivacyTestSetup} from "test/integration/common/core/PoolPrivacyTestSetup.t.sol";
import {ReferralSystemTestSetup} from "test/integration/common/core/ReferralSystemTestSetup.t.sol";
import {ArbitrumSetup} from "test/integration/utils/foundry/chains/ArbitrumSetup.t.sol";

contract CoreTestArbitrum is
  MaxSupplyCapTestSetup,
  MaxPriceAgeTestSetup,
  EntryExitFeesTestSetup,
  PoolPrivacyTestSetup,
  ReferralSystemTestSetup,
  ArbitrumSetup
{
  constructor()
    MaxSupplyCapTestSetup()
    MaxPriceAgeTestSetup()
    EntryExitFeesTestSetup()
    PoolPrivacyTestSetup()
    ReferralSystemTestSetup()
    ArbitrumSetup(455522266)
  {}

  function setUp()
    public
    virtual
    override(
      MaxSupplyCapTestSetup,
      MaxPriceAgeTestSetup,
      EntryExitFeesTestSetup,
      PoolPrivacyTestSetup,
      ReferralSystemTestSetup,
      ArbitrumSetup
    )
  {
    super.setUp();
  }
}
