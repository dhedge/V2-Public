// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {PoolUnitTestSetup} from "test/unit/PoolUnitTestSetup.t.sol";

/// @notice Performance and streaming (management) fee accrual: how much `mintManagerFee` mints,
/// the high watermark that stops managers charging twice for the same gain, and the fee mint that
/// `commitFeeIncrease` forces so a fee rise never applies retroactively.
contract PoolManagerFeesTest is PoolUnitTestSetup {
  uint256 internal constant PERFORMANCE_FEE_NUMERATOR = 5_000; // 50%
  uint256 internal constant MANAGER_FEE_NUMERATOR = 200; // 2% per year
  uint256 internal constant FEE_DENOMINATOR = 10_000;
  uint256 internal constant DEPOSIT_AMOUNT = 200e6;

  PoolLogic private testPool;
  PoolManagerLogic private testPoolManagerLogic;

  function setUp() public override {
    super.setUp();

    IHasSupportedAsset.Asset[] memory supportedAssets = new IHasSupportedAsset.Asset[](1);
    supportedAssets[0] = IHasSupportedAsset.Asset({asset: address(usdc), isDeposit: true});

    vm.prank(manager);
    testPool = PoolLogic(
      poolFactoryProxy.createFund({
        _privatePool: false,
        _manager: manager,
        _managerName: "Manager",
        _fundName: "ManagerFeesTest",
        _fundSymbol: "MFT",
        _performanceFeeNumerator: PERFORMANCE_FEE_NUMERATOR,
        _managerFeeNumerator: MANAGER_FEE_NUMERATOR,
        _entryFeeNumerator: 0,
        _exitFeeNum: 0,
        _supportedAssets: supportedAssets
      })
    );
    testPoolManagerLogic = PoolManagerLogic(testPool.poolManagerLogic());

    _makeDeposit(testPool, investor, address(usdc), DEPOSIT_AMOUNT);
  }

  /* ========== PERFORMANCE FEE ========== */

  function test_performance_fee_mints_share_of_profit() public {
    _growVaultByTenPercent();

    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 totalSupplyPreMint = testPool.totalSupply();
    uint256 tokenPricePreMint = testPool.tokenPriceWithoutManagerFee();
    uint256 availableFee = testPool.calculateAvailableManagerFee(testPoolManagerLogic.totalFundValue());

    assertEq(availableFee, _expectedPerformanceFee());
    assertGt(availableFee, 0);

    testPool.mintManagerFee();

    uint256 totalSupplyPostMint = testPool.totalSupply();
    assertEq(totalSupplyPostMint, totalSupplyPreMint + availableFee);
    // Minting fee shares dilutes the token price by exactly the shares added.
    assertApproxEqRel(testPool.tokenPrice(), (tokenPricePreMint * totalSupplyPreMint) / totalSupplyPostMint, 0.001e18);
    assertEq(testPool.tokenPriceAtLastFeeMint(), tokenPricePreMint);
    assertEq(testPool.balanceOf(dao), daoBalanceBefore + _daoCut(availableFee));

    // The same gain cannot be charged for twice.
    assertEq(testPool.calculateAvailableManagerFee(testPoolManagerLogic.totalFundValue()), 0);
  }

  function test_performance_fee_respects_high_watermark() public {
    _growVaultByTenPercent();

    assertGt(testPool.calculateAvailableManagerFee(testPoolManagerLogic.totalFundValue()), 0);
    testPool.mintManagerFee();
    uint256 highWatermark = testPool.tokenPriceAtLastFeeMint();

    // Halve the vault: the manager is now far below the watermark.
    deal(address(usdc), address(testPool), IERC20(address(usdc)).balanceOf(address(testPool)) / 2);
    vm.warp(block.timestamp + 1 days);

    // Only the streaming fee accrues while under water.
    assertEq(testPool.calculateAvailableManagerFee(testPoolManagerLogic.totalFundValue()), _expectedStreamingFee());

    testPool.mintManagerFee();

    // The watermark must not ratchet down, otherwise recovering the loss would be charged as profit.
    assertEq(testPool.tokenPriceAtLastFeeMint(), highWatermark);
  }

  /* ========== STREAMING FEE ========== */

  function test_streaming_fee_accrues_over_six_months() public {
    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 totalSupplyPreMint = testPool.totalSupply();
    uint256 tokenPricePreMint = testPool.tokenPriceWithoutManagerFee();

    vm.warp(block.timestamp + 365 days / 2);

    // 2% per year over half a year is 1% of supply.
    uint256 availableFee = testPool.calculateAvailableManagerFee(testPoolManagerLogic.totalFundValue());
    assertApproxEqRel(availableFee, totalSupplyPreMint / 100, 0.001e18);
    assertEq(availableFee, _expectedStreamingFee());

    testPool.mintManagerFee();

    assertEq(testPool.tokenPriceAtLastFeeMint(), tokenPricePreMint);
    assertEq(testPool.balanceOf(dao), daoBalanceBefore + _daoCut(availableFee));
  }

  function test_mints_both_performance_and_streaming_fees() public {
    _growVaultByTenPercent();
    vm.warp(block.timestamp + 1 days);

    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 totalSupplyPreMint = testPool.totalSupply();
    uint256 tokenPricePreMint = testPool.tokenPriceWithoutManagerFee();

    uint256 streamingFee = _expectedStreamingFee();
    uint256 availableFee = testPool.calculateAvailableManagerFee(testPoolManagerLogic.totalFundValue());

    assertEq(availableFee, _expectedPerformanceFee() + streamingFee);
    assertGt(availableFee, streamingFee);

    testPool.mintManagerFee();

    assertEq(testPool.totalSupply(), totalSupplyPreMint + availableFee);
    assertEq(testPool.tokenPriceAtLastFeeMint(), tokenPricePreMint);
    assertEq(testPool.balanceOf(dao), daoBalanceBefore + _daoCut(availableFee));
    assertEq(testPool.calculateAvailableManagerFee(testPoolManagerLogic.totalFundValue()), 0);
  }

  /* ========== FEE INCREASES ========== */

  function test_commitFeeIncrease_mints_fee_at_the_old_rate() public {
    vm.startPrank(owner);
    poolFactoryProxy.setMaximumFee(6_000, 300, 0, 0);
    poolFactoryProxy.setPerformanceFeeNumeratorChangeDelay(1 days);
    vm.stopPrank();

    _growVaultByTenPercent();
    uint256 tokenPriceBeforeIncrease = testPool.tokenPriceWithoutManagerFee();

    _announceAndCommitFeeIncrease(5_500, 250);

    // Committing settles outstanding fees, so the increase cannot be applied to past performance.
    assertEq(testPool.lastFeeMintTime(), block.timestamp);
    assertEq(testPool.tokenPriceAtLastFeeMint(), tokenPriceBeforeIncrease);

    // Drop below the watermark and raise fees again.
    deal(address(usdc), address(testPool), IERC20(address(usdc)).balanceOf(address(testPool)) / 2);
    uint256 tokenPriceWhileUnderWater = testPool.tokenPriceWithoutManagerFee();
    uint256 highWatermark = testPool.tokenPriceAtLastFeeMint();

    _announceAndCommitFeeIncrease(6_000, 300);

    assertEq(testPool.lastFeeMintTime(), block.timestamp);
    assertTrue(testPool.tokenPriceAtLastFeeMint() != tokenPriceWhileUnderWater);
    assertEq(testPool.tokenPriceAtLastFeeMint(), highWatermark);
  }

  function test_announced_fee_numerators_reset_after_commitFeeIncrease() public {
    vm.startPrank(owner);
    poolFactoryProxy.setMaximumFee(6_000, 300, 100, 100);
    poolFactoryProxy.setPerformanceFeeNumeratorChangeDelay(1 days);
    vm.stopPrank();

    vm.prank(manager);
    testPoolManagerLogic.announceFeeIncrease(5_500, 250, 100, 100);
    vm.warp(block.timestamp + 1 days);
    vm.prank(manager);
    testPoolManagerLogic.commitFeeIncrease();

    assertEq(testPoolManagerLogic.announcedPerformanceFeeNumerator(), 0);
    assertEq(testPoolManagerLogic.announcedManagerFeeNumerator(), 0);
    assertEq(testPoolManagerLogic.announcedEntryFeeNumerator(), 0);
    assertEq(testPoolManagerLogic.announcedExitFeeNumerator(), 0);
    assertEq(testPoolManagerLogic.announcedFeeIncreaseTimestamp(), 0);
  }

  /// @dev A deposit lands at the token price of the moment, so it buys its shares rather than
  /// creating a gain. A large one arriving between fee mints must therefore not enlarge the
  /// performance fee, which is charged on the price rise alone, and a year of streaming fee has to
  /// accrue on top of it.
  function test_manager_fee_after_a_large_intervening_deposit() public {
    // The original deposit gains 10%.
    _mockPriceFeed(usdcPriceFeed, (USDC_PRICE * 110) / 100);

    // A deposit ten times its size arrives at that higher price.
    _makeDeposit(testPool, otherInvestor, address(usdc), DEPOSIT_AMOUNT * 10);

    // Everything then gains again, and a year of streaming fee accrues.
    _mockPriceFeed(usdcPriceFeed, (USDC_PRICE * 120) / 100);
    vm.warp(block.timestamp + 365 days);

    uint256 daoBalanceBefore = testPool.balanceOf(dao);
    uint256 totalSupplyPreMint = testPool.totalSupply();
    uint256 tokenPricePreMint = testPool.tokenPriceWithoutManagerFee();

    uint256 streamingFee = _expectedStreamingFee();
    uint256 availableFee = testPool.calculateAvailableManagerFee(testPoolManagerLogic.totalFundValue());

    assertEq(availableFee, _expectedPerformanceFee() + streamingFee);
    assertGt(availableFee, streamingFee);

    testPool.mintManagerFee();

    assertEq(testPool.totalSupply(), totalSupplyPreMint + availableFee);
    assertEq(testPool.tokenPriceAtLastFeeMint(), tokenPricePreMint);
    assertEq(testPool.balanceOf(dao), daoBalanceBefore + _daoCut(availableFee));
    assertEq(testPool.calculateAvailableManagerFee(testPoolManagerLogic.totalFundValue()), 0);
  }

  /* ========== FEE SETTER AUTHORIZATION AND LIMITS ========== */

  function test_revert_announceFeeIncrease_when_not_manager() public {
    vm.expectRevert(bytes("dh4"));
    testPoolManagerLogic.announceFeeIncrease(PERFORMANCE_FEE_NUMERATOR, MANAGER_FEE_NUMERATOR, 0, 0);
  }

  function test_revert_announceFeeIncrease_above_the_maximum() public {
    (uint256 maxPerformance, uint256 maxManager, uint256 maxEntry, uint256 maxExit, ) = testPoolManagerLogic
      .getMaximumFee();

    vm.startPrank(manager);
    vm.expectRevert("exceeded allowed increase");
    testPoolManagerLogic.announceFeeIncrease(maxPerformance + 1, MANAGER_FEE_NUMERATOR, 0, 0);

    vm.expectRevert("exceeded allowed increase");
    testPoolManagerLogic.announceFeeIncrease(PERFORMANCE_FEE_NUMERATOR, maxManager + 1, 0, 0);

    vm.expectRevert("exceeded allowed increase");
    testPoolManagerLogic.announceFeeIncrease(PERFORMANCE_FEE_NUMERATOR, MANAGER_FEE_NUMERATOR, maxEntry + 1, 0);

    vm.expectRevert("exceeded allowed increase");
    testPoolManagerLogic.announceFeeIncrease(PERFORMANCE_FEE_NUMERATOR, MANAGER_FEE_NUMERATOR, 0, maxExit + 1);
    vm.stopPrank();
  }

  /// @dev The performance fee may only climb one step at a time, however far below the cap it sits.
  function test_revert_announceFeeIncrease_beyond_one_allowed_step() public {
    uint256 maximumChange = testPoolManagerLogic.getMaximumPerformanceFeeChange();

    vm.prank(manager);
    vm.expectRevert("exceeded allowed increase");
    testPoolManagerLogic.announceFeeIncrease(
      PERFORMANCE_FEE_NUMERATOR + maximumChange + 1,
      MANAGER_FEE_NUMERATOR,
      0,
      0
    );
  }

  /// @dev The delay is what gives investors time to leave before a rise takes effect.
  function test_revert_commitFeeIncrease_before_the_delay_elapses() public {
    vm.prank(owner);
    poolFactoryProxy.setPerformanceFeeNumeratorChangeDelay(4 weeks);

    vm.startPrank(manager);
    testPoolManagerLogic.announceFeeIncrease(PERFORMANCE_FEE_NUMERATOR, MANAGER_FEE_NUMERATOR, 0, 0);

    vm.expectRevert("fee increase delay active");
    testPoolManagerLogic.commitFeeIncrease();
    vm.stopPrank();
  }

  function test_revert_setFeeNumerator_when_not_manager() public {
    vm.expectRevert(bytes("dh4"));
    testPoolManagerLogic.setFeeNumerator(0, 0, 0, 0);
  }

  /// @dev `setFeeNumerator` is the immediate path, so it may only lower fees. Raising any one of
  /// the four has to go through announce and commit instead.
  function test_revert_setFeeNumerator_cannot_raise_a_fee() public {
    vm.startPrank(manager);
    vm.expectRevert("manager fee too high");
    testPoolManagerLogic.setFeeNumerator(PERFORMANCE_FEE_NUMERATOR + 1, MANAGER_FEE_NUMERATOR, 0, 0);

    vm.expectRevert("manager fee too high");
    testPoolManagerLogic.setFeeNumerator(PERFORMANCE_FEE_NUMERATOR, MANAGER_FEE_NUMERATOR + 1, 0, 0);

    vm.expectRevert("manager fee too high");
    testPoolManagerLogic.setFeeNumerator(PERFORMANCE_FEE_NUMERATOR, MANAGER_FEE_NUMERATOR, 1, 0);

    vm.expectRevert("manager fee too high");
    testPoolManagerLogic.setFeeNumerator(PERFORMANCE_FEE_NUMERATOR, MANAGER_FEE_NUMERATOR, 0, 1);
    vm.stopPrank();
  }

  function test_setFeeNumerator_lowers_the_fees() public {
    vm.prank(manager);
    testPoolManagerLogic.setFeeNumerator(PERFORMANCE_FEE_NUMERATOR / 2, MANAGER_FEE_NUMERATOR / 2, 0, 0);

    (
      uint256 performanceFeeNumerator,
      uint256 managerFeeNumerator,
      uint256 entryFeeNumerator,
      uint256 exitFeeNumerator,
      uint256 denominator
    ) = testPoolManagerLogic.getFee();

    assertEq(performanceFeeNumerator, PERFORMANCE_FEE_NUMERATOR / 2);
    assertEq(managerFeeNumerator, MANAGER_FEE_NUMERATOR / 2);
    assertEq(entryFeeNumerator, 0);
    assertEq(exitFeeNumerator, 0);
    assertEq(denominator, FEE_DENOMINATOR);
  }

  /* ========== HELPERS ========== */

  /// @dev Donating to the vault raises its value without minting shares, which is what the
  /// performance fee is charged on.
  function _growVaultByTenPercent() internal {
    deal(address(usdc), address(testPool), (IERC20(address(usdc)).balanceOf(address(testPool)) * 110) / 100);
  }

  function _announceAndCommitFeeIncrease(uint256 _performanceFeeNumerator, uint256 _managerFeeNumerator) internal {
    vm.prank(manager);
    testPoolManagerLogic.announceFeeIncrease(_performanceFeeNumerator, _managerFeeNumerator, 0, 0);
    vm.warp(block.timestamp + 1 days);
    vm.prank(manager);
    testPoolManagerLogic.commitFeeIncrease();
  }

  /// @dev Mirrors PoolLogic's performance fee maths: the manager's cut of the gain above the
  /// watermark, converted from dollars into the shares that have to be minted to pay it.
  function _expectedPerformanceFee() internal view returns (uint256 fee) {
    uint256 tokenPrice = testPool.tokenPriceWithoutManagerFee();
    uint256 tokenPriceAtLastFeeMint = testPool.tokenPriceAtLastFeeMint();
    if (tokenPrice <= tokenPriceAtLastFeeMint) return 0;

    uint256 totalSupply = testPool.totalSupply();
    uint256 feeDollarAmount = ((tokenPrice - tokenPriceAtLastFeeMint) *
      totalSupply *
      testPoolManagerLogic.performanceFeeNumerator()) / (FEE_DENOMINATOR * 1e18);

    fee = (feeDollarAmount * totalSupply) / (testPoolManagerLogic.totalFundValue() - feeDollarAmount);
  }

  function _expectedStreamingFee() internal view returns (uint256 fee) {
    fee =
      (testPool.totalSupply() *
        (block.timestamp - testPool.lastFeeMintTime()) *
        testPoolManagerLogic.managerFeeNumerator()) /
      FEE_DENOMINATOR /
      365 days;
  }

  function _daoCut(uint256 _totalFee) internal view returns (uint256 daoFee) {
    (uint256 numerator, uint256 denominator) = poolFactoryProxy.getDaoFee();
    daoFee = (_totalFee * numerator) / denominator;
  }
}
