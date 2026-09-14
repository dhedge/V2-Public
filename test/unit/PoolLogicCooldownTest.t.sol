// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {PoolLogicExposed} from "contracts/test/PoolLogicExposed.sol";

/// @notice `PoolLogicLib.calculateCooldown` decides the exit lockup applied to a depositor after a
/// deposit. It is a pure function, so it is covered here by its behavioural rules and the
/// invariants that must hold for any input, rather than by a table of hand-picked numbers.
contract PoolLogicCooldownTest is Test {
  uint256 internal constant DEFAULT_COOLDOWN = 1 days;
  uint256 internal constant CUSTOM_COOLDOWN = 5 minutes;

  PoolLogicExposed internal poolLogicExposed;

  function setUp() public {
    poolLogicExposed = new PoolLogicExposed();

    // Start far enough into the future that a deposit can sit in the past.
    vm.warp(365 days);
  }

  /* ========== BEHAVIOUR ========== */

  function test_no_cooldown_when_nothing_is_held_and_nothing_minted() public view {
    assertEq(
      _cooldown({
        _currentBalance: 0,
        _liquidityMinted: 0,
        _newCooldown: DEFAULT_COOLDOWN,
        _lastCooldown: 0,
        _lastDepositTime: 0
      }),
      0
    );
  }

  function test_first_deposit_gets_the_full_new_cooldown() public view {
    assertEq(
      _cooldown({
        _currentBalance: 0,
        _liquidityMinted: 100e18,
        _newCooldown: DEFAULT_COOLDOWN,
        _lastCooldown: 0,
        _lastDepositTime: 0
      }),
      DEFAULT_COOLDOWN
    );
  }

  function test_zero_liquidity_deposit_leaves_remaining_cooldown_untouched() public view {
    // Half a day into a one day lockup.
    uint256 cooldown = _cooldown({
      _currentBalance: 100e18,
      _liquidityMinted: 0,
      _newCooldown: DEFAULT_COOLDOWN,
      _lastCooldown: DEFAULT_COOLDOWN,
      _lastDepositTime: block.timestamp - 12 hours
    });

    assertEq(cooldown, 12 hours);
  }

  function test_expired_cooldown_counts_as_zero_remaining() public view {
    uint256 cooldown = _cooldown({
      _currentBalance: 100e18,
      _liquidityMinted: 0,
      _newCooldown: DEFAULT_COOLDOWN,
      _lastCooldown: DEFAULT_COOLDOWN,
      _lastDepositTime: block.timestamp - 2 days
    });

    assertEq(cooldown, 0);
  }

  function test_shorter_new_cooldown_cannot_shorten_an_active_lockup() public view {
    // A custom-cooldown deposit must not let a holder escape a longer running lockup.
    uint256 cooldown = _cooldown({
      _currentBalance: 100e18,
      _liquidityMinted: 100e18,
      _newCooldown: CUSTOM_COOLDOWN,
      _lastCooldown: DEFAULT_COOLDOWN,
      _lastDepositTime: block.timestamp - 1 hours
    });

    assertEq(cooldown, DEFAULT_COOLDOWN - 1 hours);
  }

  function test_additional_cooldown_is_proportional_to_liquidity_added() public view {
    // Doubling a holding with no lockup running adds the whole new cooldown.
    assertEq(
      _cooldown({
        _currentBalance: 100e18,
        _liquidityMinted: 100e18,
        _newCooldown: DEFAULT_COOLDOWN,
        _lastCooldown: 0,
        _lastDepositTime: 0
      }),
      DEFAULT_COOLDOWN
    );

    // Adding a tenth of the holding adds a tenth of the cooldown.
    assertEq(
      _cooldown({
        _currentBalance: 100e18,
        _liquidityMinted: 10e18,
        _newCooldown: DEFAULT_COOLDOWN,
        _lastCooldown: 0,
        _lastDepositTime: 0
      }),
      DEFAULT_COOLDOWN / 10
    );
  }

  function test_aggregated_cooldown_is_capped_at_the_new_cooldown() public view {
    // A large top-up while a lockup is still running would overflow past the new cooldown.
    uint256 cooldown = _cooldown({
      _currentBalance: 100e18,
      _liquidityMinted: 100e18,
      _newCooldown: DEFAULT_COOLDOWN,
      _lastCooldown: DEFAULT_COOLDOWN,
      _lastDepositTime: block.timestamp - 1 hours
    });

    assertEq(cooldown, DEFAULT_COOLDOWN);
  }

  function test_dust_deposit_still_locks_for_at_least_one_second() public view {
    // The proportional part rounds down to zero, but a deposit must never be lockup-free.
    uint256 cooldown = _cooldown({
      _currentBalance: 100e18,
      _liquidityMinted: 1,
      _newCooldown: DEFAULT_COOLDOWN,
      _lastCooldown: 0,
      _lastDepositTime: 0
    });

    assertEq(cooldown, 1);
  }

  /* ========== INVARIANTS ========== */

  /// @dev The property that matters for security: depositing again can never shorten the lockup a
  /// holder is already serving, no matter the sizes or cooldowns involved.
  function test_fuzz_deposit_never_shortens_an_active_lockup(
    uint256 _currentBalance,
    uint256 _liquidityMinted,
    uint256 _newCooldown,
    uint256 _lastCooldown,
    uint256 _elapsed
  ) public view {
    _currentBalance = bound(_currentBalance, 1, 1e30);
    _liquidityMinted = bound(_liquidityMinted, 0, 1e30);
    _newCooldown = bound(_newCooldown, 0, 365 days);
    _lastCooldown = bound(_lastCooldown, 0, 365 days);
    _elapsed = bound(_elapsed, 0, 365 days);

    uint256 lastDepositTime = block.timestamp - _elapsed;
    uint256 remaining = _elapsed >= _lastCooldown ? 0 : _lastCooldown - _elapsed;

    uint256 cooldown = _cooldown(_currentBalance, _liquidityMinted, _newCooldown, _lastCooldown, lastDepositTime);

    assertGe(cooldown, remaining);
  }

  function test_fuzz_cooldown_never_exceeds_the_longer_of_new_and_remaining(
    uint256 _currentBalance,
    uint256 _liquidityMinted,
    uint256 _newCooldown,
    uint256 _lastCooldown,
    uint256 _elapsed
  ) public view {
    _currentBalance = bound(_currentBalance, 0, 1e30);
    _liquidityMinted = bound(_liquidityMinted, 0, 1e30);
    _newCooldown = bound(_newCooldown, 0, 365 days);
    _lastCooldown = bound(_lastCooldown, 0, 365 days);
    _elapsed = bound(_elapsed, 0, 365 days);

    uint256 lastDepositTime = block.timestamp - _elapsed;
    uint256 remaining = _elapsed >= _lastCooldown ? 0 : _lastCooldown - _elapsed;
    uint256 upperBound = _newCooldown > remaining ? _newCooldown : remaining;

    uint256 cooldown = _cooldown(_currentBalance, _liquidityMinted, _newCooldown, _lastCooldown, lastDepositTime);

    // A mint into an existing balance always locks for at least a second, so with both cooldowns
    // at zero the floor is the bound. Unreachable in production - the factory's exit cooldown and
    // EasySwapperV2's custom cooldown are both floored at 5 minutes.
    assertLe(cooldown, upperBound == 0 ? 1 : upperBound);
  }

  /// @dev A holder who receives liquidity is always locked for something, so a deposit can never
  /// be immediately followed by an exit.
  function test_fuzz_any_minted_liquidity_leaves_a_nonzero_lockup(
    uint256 _currentBalance,
    uint256 _liquidityMinted,
    uint256 _elapsed
  ) public view {
    _currentBalance = bound(_currentBalance, 0, 1e30);
    _liquidityMinted = bound(_liquidityMinted, 1, 1e30);
    _elapsed = bound(_elapsed, 0, 365 days);

    uint256 cooldown = _cooldown(
      _currentBalance,
      _liquidityMinted,
      DEFAULT_COOLDOWN,
      DEFAULT_COOLDOWN,
      block.timestamp - _elapsed
    );

    assertGt(cooldown, 0);
  }

  /// @dev Minting more liquidity in one go can never result in a shorter lockup than minting less.
  function test_fuzz_cooldown_is_monotonic_in_liquidity_minted(
    uint256 _currentBalance,
    uint256 _smallMint,
    uint256 _extraMint
  ) public view {
    _currentBalance = bound(_currentBalance, 1, 1e30);
    _smallMint = bound(_smallMint, 0, 1e30);
    _extraMint = bound(_extraMint, 0, 1e30 - _smallMint);

    uint256 smallCooldown = _cooldown(_currentBalance, _smallMint, DEFAULT_COOLDOWN, 0, 0);
    uint256 largeCooldown = _cooldown(_currentBalance, _smallMint + _extraMint, DEFAULT_COOLDOWN, 0, 0);

    assertGe(largeCooldown, smallCooldown);
  }

  function _cooldown(
    uint256 _currentBalance,
    uint256 _liquidityMinted,
    uint256 _newCooldown,
    uint256 _lastCooldown,
    uint256 _lastDepositTime
  ) internal view returns (uint256 cooldown) {
    cooldown = poolLogicExposed._calculateCooldownExposed(
      _currentBalance,
      _liquidityMinted,
      _newCooldown,
      _lastCooldown,
      _lastDepositTime,
      block.timestamp
    );
  }
}
