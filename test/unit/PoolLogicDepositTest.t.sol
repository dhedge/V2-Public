// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {WETH9} from "contracts/test/WETH9.sol";
import {TestAssetWithFallback} from "contracts/test/TestAssets.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice Share accounting rules that protect depositors: the minimum share supply that defuses
/// the ERC4626-style inflation attack, and the lockup that stops shares being moved out of it.
contract PoolLogicDepositTest is PoolUnitTestSetup {
  /// @dev PoolLogic refuses to mint or leave behind less than this many shares.
  uint256 internal constant MIN_SUPPLY = 100_000;
  uint256 internal constant CUSTOM_COOLDOWN = 5 minutes;

  /* ========== MINIMUM SUPPLY ========== */

  function test_revert_deposit_minting_fewer_shares_than_the_minimum() public {
    // One wei of WETH is worth ~2000 shares, well under the floor.
    vm.prank(manager);
    vm.expectRevert(bytes("dh10"));
    fund.deposit(address(weth), 1);
  }

  function test_revert_withdraw_leaving_supply_below_the_minimum() public {
    uint256 shares = _deposit(manager, address(usdc), 1e6);
    vm.warp(block.timestamp + EXIT_COOLDOWN + 1);

    // Leaving a single share behind would put the vault back in inflation-attack territory.
    vm.prank(manager);
    vm.expectRevert(bytes("dh10"));
    fund.withdraw(shares - 1);
  }

  function test_withdrawing_everything_is_allowed() public {
    uint256 shares = _deposit(manager, address(usdc), 1e6);
    vm.warp(block.timestamp + EXIT_COOLDOWN + 1);

    _withdraw(manager, shares);

    assertEq(fund.totalSupply(), 0);
    assertEq(fund.balanceOf(manager), 0);
  }

  /* ========== INFLATION ATTACK ========== */

  /// @dev The classic attack: seed the vault, withdraw down to dust, donate a large amount to
  /// inflate the share price, then let a victim deposit and round down to zero shares.
  /// See https://mixbytes.io/blog/overview-of-the-inflation-attack
  function test_inflation_attack_cannot_steal_a_depositors_funds() public {
    // The donation has to dwarf the victim's deposit, so give the attacker the deep pockets the
    // attack assumes.
    usdc.transfer(manager, 1_000_001e6);
    uint256 attackerBalanceBefore = usdc.balanceOf(manager);

    uint256 attackerShares = _deposit(manager, address(usdc), 10e6);
    vm.warp(block.timestamp + EXIT_COOLDOWN + 1);

    // Wind down to the smallest supply the vault permits.
    _withdraw(manager, attackerShares - MIN_SUPPLY);
    assertEq(fund.balanceOf(manager), MIN_SUPPLY);

    // Donate a large amount directly to inflate the share price.
    vm.prank(manager);
    usdc.transfer(address(fund), 1_000_001e6);

    // The victim's deposit is rejected rather than silently minting them nothing.
    vm.prank(investor);
    vm.expectRevert(bytes("dh10"));
    fund.deposit(address(usdc), 10e6);
    assertEq(fund.balanceOf(investor), 0);

    // The attacker only ever gets their own money back.
    _withdraw(manager, MIN_SUPPLY);
    assertEq(usdc.balanceOf(manager), attackerBalanceBefore);
  }

  function test_inflation_attack_loss_stays_negligible_for_18_decimal_tokens() public {
    _runDonationAttack({_asset: address(weth), _seed: 100, _donation: 0.005e18, _victimDeposit: 0.01e18});
  }

  function test_inflation_attack_loss_stays_negligible_for_6_decimal_tokens() public {
    _runDonationAttack({_asset: address(usdc), _seed: 1e6, _donation: 501e6, _victimDeposit: 1_000e6});
  }

  /// @dev Where the attack is not outright rejected it must not be profitable: depositors who
  /// follow the attacker still get essentially all of their money back.
  function _runDonationAttack(address _asset, uint256 _seed, uint256 _donation, uint256 _victimDeposit) internal {
    uint256 investorBalanceBefore = _balanceOf(_asset, investor);
    uint256 otherInvestorBalanceBefore = _balanceOf(_asset, otherInvestor);

    uint256 attackerShares = _deposit(manager, _asset, _seed);
    vm.warp(block.timestamp + EXIT_COOLDOWN + 1);
    _withdraw(manager, attackerShares - MIN_SUPPLY);

    vm.prank(manager);
    _transfer(_asset, address(fund), _donation);

    uint256 investorShares = _deposit(investor, _asset, _victimDeposit);
    uint256 otherInvestorShares = _deposit(otherInvestor, _asset, _victimDeposit);

    vm.warp(block.timestamp + EXIT_COOLDOWN + 1);

    // Attacker exits first, then the depositors.
    _withdraw(manager, fund.balanceOf(manager));
    _withdraw(investor, investorShares);
    _withdraw(otherInvestor, otherInvestorShares);

    // At most 0.01% may be lost to the attack and rounding.
    assertGe(_balanceOf(_asset, investor), (investorBalanceBefore * 9_999) / 10_000);
    assertGe(_balanceOf(_asset, otherInvestor), (otherInvestorBalanceBefore * 9_999) / 10_000);
  }

  /* ========== TRANSFERS UNDER LOCKUP ========== */

  function test_revert_transfer_while_shares_are_locked() public {
    uint256 shares = _deposit(investor, address(usdc), 42e6);
    assertEq(fund.getExitRemainingCooldown(investor), EXIT_COOLDOWN);

    vm.prank(investor);
    vm.expectRevert(bytes("dh3"));
    fund.transfer(dao, shares);
  }

  function test_locked_shares_can_be_sent_to_a_whitelisted_receiver() public {
    uint256 shares = _deposit(investor, address(usdc), 42e6);

    vm.prank(owner);
    poolFactoryProxy.addReceiverWhitelist(dao);

    vm.prank(investor);
    fund.transfer(dao, shares);

    assertEq(fund.balanceOf(dao), shares);
  }

  function test_removing_a_receiver_from_the_whitelist_locks_it_out_again() public {
    uint256 shares = _deposit(investor, address(usdc), 42e6);

    vm.prank(owner);
    poolFactoryProxy.addReceiverWhitelist(dao);

    vm.prank(investor);
    fund.transfer(dao, shares / 2);

    vm.prank(owner);
    poolFactoryProxy.removeReceiverWhitelist(dao);

    vm.prank(investor);
    vm.expectRevert(bytes("dh3"));
    fund.transfer(dao, shares / 2);
  }

  function test_transfers_are_free_once_the_lockup_expires() public {
    uint256 shares = _deposit(investor, address(usdc), 42e6);
    vm.warp(block.timestamp + EXIT_COOLDOWN + 1);

    vm.prank(investor);
    fund.transfer(dao, shares);

    assertEq(fund.balanceOf(dao), shares);
  }

  /* ========== CUSTOM COOLDOWN ========== */

  function test_revert_depositForWithCustomCooldown_when_caller_is_not_whitelisted() public {
    assertFalse(poolFactoryProxy.customCooldownWhitelist(manager));

    vm.prank(manager);
    vm.expectRevert(bytes("dh5"));
    fund.depositForWithCustomCooldown(investor, address(usdc), 42e6, CUSTOM_COOLDOWN, address(0));
  }

  function test_plain_deposit_applies_the_default_cooldown() public {
    assertEq(fund.getExitRemainingCooldown(investor), 0);

    _deposit(investor, address(usdc), 42e6);

    assertEq(fund.getExitRemainingCooldown(investor), EXIT_COOLDOWN);
  }

  function test_whitelisted_caller_can_deposit_with_a_shorter_cooldown() public {
    vm.prank(owner);
    poolFactoryProxy.addCustomCooldownWhitelist(manager);

    vm.prank(manager);
    fund.depositForWithCustomCooldown(investor, address(usdc), 42e6, CUSTOM_COOLDOWN, address(0));

    // The shares land with the recipient, locked only for the custom period.
    assertGt(fund.balanceOf(investor), 0);
    assertEq(fund.getExitRemainingCooldown(investor), CUSTOM_COOLDOWN);
  }

  function test_removing_a_caller_from_the_custom_cooldown_whitelist_locks_it_out_again() public {
    vm.startPrank(owner);
    poolFactoryProxy.addCustomCooldownWhitelist(manager);
    poolFactoryProxy.removeCustomCooldownWhitelist(manager);
    vm.stopPrank();

    vm.prank(manager);
    vm.expectRevert(bytes("dh5"));
    fund.depositForWithCustomCooldown(investor, address(usdc), 42e6, CUSTOM_COOLDOWN, address(0));
  }

  /* ========== UNUSUAL DEPOSIT TOKENS ========== */

  function test_can_deposit_canonical_weth() public {
    WETH9 weth9 = new WETH9();
    _enableExtraDepositAsset(address(weth9), wethPriceFeed);

    vm.deal(investor, 1 ether);
    vm.startPrank(investor);
    weth9.deposit{value: 1 ether}();
    weth9.approve(address(fund), 1 ether);
    fund.deposit(address(weth9), 1 ether);
    vm.stopPrank();

    assertEq(weth9.balanceOf(address(fund)), 1 ether);
  }

  /// @dev A token whose fallback is non-view breaks naive staticcall-based probing, so depositing
  /// one has to keep working.
  function test_can_deposit_token_with_a_non_view_fallback() public {
    TestAssetWithFallback fallbackAsset = new TestAssetWithFallback(2_000_000);
    _enableExtraDepositAsset(address(fallbackAsset), usdcPriceFeed);

    fallbackAsset.mint(investor, 1e18);

    vm.startPrank(investor);
    fallbackAsset.approve(address(fund), 1e18);
    fund.deposit(address(fallbackAsset), 1e18);
    vm.stopPrank();

    assertEq(fallbackAsset.balanceOf(address(fund)), 1e18);
  }

  function _enableExtraDepositAsset(address _asset, address _priceFeed) internal {
    vm.prank(owner);
    assetHandlerProxy.addAsset({asset: _asset, assetType: 0, aggregator: _priceFeed});

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: _asset, isDeposit: true});

    vm.prank(manager);
    fundManagerLogic.changeAssets(assetsToAdd, new address[](0));
  }

  /* ========== FEE WATERMARK RESET ========== */

  function test_watermark_resets_once_the_vault_is_emptied() public {
    uint256 shares = _deposit(investor, address(usdc), 42e6);
    uint256 tokenPriceAfterDeposit = fund.tokenPrice();

    // Donating raises the share price, so a fee mint moves the watermark above $1.
    vm.prank(manager);
    usdc.transfer(address(fund), 100e6);
    assertGt(fund.tokenPrice(), tokenPriceAfterDeposit);

    vm.warp(block.timestamp + EXIT_COOLDOWN + 1 hours);
    vm.prank(manager);
    fund.mintManagerFee();
    assertGt(fund.tokenPriceAtLastFeeMint(), 1e18);

    uint256 lastFeeMintTimeBefore = fund.lastFeeMintTime();

    _withdraw(investor, shares);

    // An emptied vault starts over at $1 so the next depositor is not charged for old gains,
    // while the fee clock is left alone because emptying the vault mints no fee.
    assertEq(fund.tokenPrice(), 0);
    assertEq(fund.tokenPriceAtLastFeeMint(), 1e18);
    assertEq(fund.lastFeeMintTime(), lastFeeMintTimeBefore);
  }

  /* ========== HELPERS ========== */

  function _balanceOf(address _asset, address _account) internal view returns (uint256 balance) {
    balance = _asset == address(usdc) ? usdc.balanceOf(_account) : weth.balanceOf(_account);
  }

  function _transfer(address _asset, address _to, uint256 _amount) internal {
    if (_asset == address(usdc)) {
      usdc.transfer(_to, _amount);
    } else {
      weth.transfer(_to, _amount);
    }
  }
}
