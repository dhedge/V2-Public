// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice `DHedgePoolAggregator` exposes a vault's token price as a Chainlink-style USD feed, which
/// is how a nested dHEDGE vault (a Toros token held by another vault) gets priced. Its whole job is
/// `answer = tokenPrice / 1e10` at 8 decimals, so that identity is what these tests pin down.
contract DHedgePoolAggregatorTest is PoolUnitTestSetup {
  uint256 internal constant DEPOSIT_AMOUNT = 1_000e6;

  IAggregatorV3Interface internal aggregator;

  function setUp() public override {
    super.setUp();

    aggregator = IAggregatorV3Interface(
      deployCode("DHedgePoolAggregator.sol:DHedgePoolAggregator", abi.encode(address(fund)))
    );
  }

  function test_aggregator_reports_eight_decimals() public view {
    assertEq(uint256(aggregator.decimals()), 8);
  }

  function test_aggregator_price_is_zero_for_empty_vault() public view {
    assertEq(_answer(), 0);
  }

  function test_aggregator_answer_tracks_the_vault_token_price() public {
    _deposit(investor, address(usdc), DEPOSIT_AMOUNT);
    assertEq(_answer(), fund.tokenPrice() / 1e10);

    // Donating doubles the vault's value without minting shares, so the reported price follows the
    // token price up rather than tracking what the vault holds.
    deal(address(usdc), address(fund), usdc.balanceOf(address(fund)) * 2);
    assertEq(_answer(), fund.tokenPrice() / 1e10);
    assertApproxEqRel(_answer(), 2e8, 0.001e18);
  }

  function _answer() internal view returns (uint256 answer) {
    (, int256 latestAnswer, , , ) = aggregator.latestRoundData();
    answer = uint256(latestAnswer);
  }
}
