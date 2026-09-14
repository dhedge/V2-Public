// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {HyperEVMSetup} from "../utils/foundry/chains/HyperEVMSetup.t.sol";
import {CoreSimulatorLib} from "./test-suite/hyperevm-lib/CoreSimulatorLib.sol";
import {HLConstants} from "test/integration/hyperevm/test-suite/hyperevm-lib/lib/HLConstants.sol";
import {PrecompileLib} from "test/integration/hyperevm/test-suite/hyperevm-lib/lib/PrecompileLib.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "contracts/interfaces/IPoolManagerLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IGuard} from "contracts/interfaces/guards/IGuard.sol";
import {ICoreWriter} from "contracts/interfaces/hyperliquid/ICoreWriter.sol";
import {IHyperliquidCoreWriterContractGuard} from "contracts/interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";
import {ITransactionTypes} from "contracts/interfaces/ITransactionTypes.sol";
import {PrecompileHelper} from "contracts/utils/hyperliquid/PrecompileHelper.sol";
import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";
import {IChangeAssets} from "test/integration/utils/foundry/CoreBackboneSetup.sol";
import {FixedPointMathLib} from "contracts/utils/FixedPointMathLib.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {IEasySwapperV2Mock} from "test/integration/common/limitOrders/IEasySwapperV2Mock.sol";

/// @title HyperEVM Integration Tests
/// @notice Tests for Hyperliquid integration on HyperEVM network
contract HyperEvmTests is HyperEVMSetup, PrecompileHelper {
  using FixedPointMathLib for uint256;

  /////////////////////////////////////////////
  //       Deposit and Withdrawal Tests      //
  /////////////////////////////////////////////

  /// @notice Test that correct amount of pool tokens are minted after deposit
  /// @dev Pool token minted amount should be equivalent to the USD amount as per the token price
  function test_deposit_correctPoolTokensMinted() public {
    uint256 depositAmount = 10_000e6; // 10,000 USDC

    // Get pool token price before deposit
    uint256 tokenPrice = IPoolLogic(hyperliquidTestPool).tokenPrice();
    uint256 poolTotalSupplyBefore = IPoolLogic(hyperliquidTestPool).totalSupply();
    uint256 investorBalanceBefore = IPoolLogic(hyperliquidTestPool).balanceOf(investor);

    // Calculate expected liquidity minted
    // USDC has 6 decimals, need to convert to 18 decimals for USD value
    // liquidity = (depositAmount * 10^12) * 10^18 / tokenPrice
    uint256 usdValue = _scale(depositAmount, 6, 18); // Convert USDC (6 decimals) to 18 decimals
    uint256 expectedLiquidity = usdValue.divWadDown(tokenPrice);

    // Make deposit
    vm.startPrank(investor);
    uint256 liquidityMinted = IPoolLogic(hyperliquidTestPool).deposit(usdc, depositAmount);

    // Assertions
    assertGt(liquidityMinted, 0, "Liquidity minted should be greater than 0");
    assertEq(liquidityMinted, expectedLiquidity, "Liquidity minted should match expected amount");
    assertEq(
      IPoolLogic(hyperliquidTestPool).balanceOf(investor),
      investorBalanceBefore + liquidityMinted,
      "Investor should receive correct pool tokens"
    );
    assertEq(
      IPoolLogic(hyperliquidTestPool).totalSupply(),
      poolTotalSupplyBefore + liquidityMinted,
      "Total supply should increase by liquidity minted"
    );
  }

  /// @notice Test that pool tokens minted equals USD value deposited
  /// @dev Verify that depositing X USD worth of USDC mints pool tokens worth X USD
  function test_deposit_poolTokenValueEqualsDepositValue() public {
    // Setup
    uint256 depositAmount = 5_000e6; // 5,000 USDC

    // Get pool state before deposit
    uint256 tokenPriceBefore = IPoolLogic(hyperliquidTestPool).tokenPrice();

    // Make deposit
    vm.startPrank(investor);
    uint256 liquidityMinted = IPoolLogic(hyperliquidTestPool).deposit(usdc, depositAmount);
    vm.stopPrank();

    // Get token price after deposit
    uint256 tokenPriceAfter = IPoolLogic(hyperliquidTestPool).tokenPrice();

    // Calculate the USD value of minted pool tokens (convert back to USDC 6 decimals)
    uint256 mintedTokensValue = _scale(liquidityMinted.mulWadDown(tokenPriceAfter), 18, 6);

    // Assertions
    assertEq(tokenPriceBefore, tokenPriceAfter, "Token price should remain constant after deposit");
    assertApproxEqAbs(
      mintedTokensValue,
      depositAmount,
      1, // Allow 1 wei difference for rounding
      "Minted tokens value should equal deposit amount"
    );
  }

  /// @notice Test withdrawal returns correct amount of USDC
  /// @dev Verify that withdrawing pool tokens returns appropriate USDC amount
  function test_withdraw_correctUSDCReturned() public {
    uint256 depositAmount = 20_000e6; // 20,000 USDC

    vm.startPrank(investor);

    IPoolLogic(hyperliquidTestPool).deposit(usdc, depositAmount);

    // Get pool tokens
    uint256 investorPoolTokens = IPoolLogic(hyperliquidTestPool).balanceOf(investor);
    assertGt(investorPoolTokens, 0, "Investor should have pool tokens");

    // Wait for cooldown period to expire (5 minutes + 1 second)
    // Use vm.warp with the current timestamp to avoid overflow in HyperCore
    // vm.warp(block.timestamp + 5 minutes + 1);
    // vm.roll(block.number + 1);
    skip(6 minutes);

    // Get balances before withdrawal
    uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(investor);
    uint256 tokenPrice = IPoolLogic(hyperliquidTestPool).tokenPrice();

    // Calculate expected USDC to receive
    // expectedUSDC = (poolTokens * tokenPrice) / 10^18 / 10^12 (convert to 6 decimals)
    uint256 expectedUSDC = _scale(investorPoolTokens.mulWadDown(tokenPrice), 18, 6);

    // Withdraw all pool tokens
    IPoolLogic(hyperliquidTestPool).withdraw(investorPoolTokens);

    // Get balances after withdrawal
    uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(investor);
    uint256 poolTokensAfter = IPoolLogic(hyperliquidTestPool).balanceOf(investor);

    // Assertions
    assertEq(poolTokensAfter, 0, "Investor should have 0 pool tokens after full withdrawal");
    assertApproxEqAbs(
      usdcBalanceAfter - usdcBalanceBefore,
      expectedUSDC,
      1, // Allow 1 wei difference for rounding
      "USDC received should match expected amount"
    );
  }

  /// @notice Test partial withdrawal returns correct proportional USDC amount
  /// @dev Verify that withdrawing half the pool tokens returns approximately half the value
  function test_withdraw_partialWithdrawalCorrectAmount() public {
    uint256 depositAmount = 15_000e6; // 15,000 USDC

    vm.startPrank(investor);
    IPoolLogic(hyperliquidTestPool).deposit(usdc, depositAmount);
    vm.stopPrank();

    // Get pool tokens
    uint256 investorPoolTokens = IPoolLogic(hyperliquidTestPool).balanceOf(investor);
    assertGt(investorPoolTokens, 0, "Investor should have pool tokens");

    // Withdraw half of the pool tokens
    uint256 withdrawAmount = investorPoolTokens / 2;

    // Wait for cooldown period (5 minutes + 1 second)
    vm.warp(block.timestamp + 5 minutes + 1);
    vm.roll(block.number + 1);

    // Get balances before withdrawal
    uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(investor);
    uint256 tokenPrice = IPoolLogic(hyperliquidTestPool).tokenPrice();

    // Calculate expected USDC to receive (convert to 6 decimals)
    uint256 expectedUSDC = (withdrawAmount * tokenPrice) / 10 ** 18 / 10 ** 12;

    // Withdraw
    vm.prank(investor);
    IPoolLogic(hyperliquidTestPool).withdraw(withdrawAmount);

    // Get balances after withdrawal
    uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(investor);
    uint256 poolTokensAfter = IPoolLogic(hyperliquidTestPool).balanceOf(investor);

    // Assertions
    assertEq(
      poolTokensAfter,
      investorPoolTokens - withdrawAmount,
      "Investor should have correct remaining pool tokens"
    );
    assertApproxEqAbs(
      usdcBalanceAfter - usdcBalanceBefore,
      expectedUSDC,
      1, // Allow 1 wei difference for rounding
      "USDC received should match expected amount"
    );
  }

  /// @notice Test deposit after bridging USDC to spot dex
  /// @dev Verify deposits work correctly when some USDC is bridged to core spot
  function test_deposit_afterBridgingToSpotDex() public {
    // First, bridge some USDC to core spot dex
    uint256 poolUsdcBalance = _getPoolUSDCBalance();
    uint256 bridgeAmount = poolUsdcBalance / 2; // Bridge half

    _bridgeUSDCToCore(bridgeAmount, _DEX_ID_CORE_SPOT);

    // Advance to next block to process bridge
    CoreSimulatorLib.nextBlock();

    // Setup deposit
    uint256 depositAmount = 8_000e6; // 8,000 USDC

    // Get pool state before deposit
    uint256 tokenPriceBefore = IPoolLogic(hyperliquidTestPool).tokenPrice();

    // Make deposit
    vm.startPrank(investor);
    uint256 liquidityMinted = IPoolLogic(hyperliquidTestPool).deposit(usdc, depositAmount);
    vm.stopPrank();

    // Get token price after deposit
    uint256 tokenPriceAfter = IPoolLogic(hyperliquidTestPool).tokenPrice();

    // Calculate expected liquidity and value
    uint256 usdValueDeposit = _scale(depositAmount, 6, 18); // Convert to 18 decimals
    uint256 expectedLiquidity = usdValueDeposit.divWadDown(tokenPriceBefore);
    uint256 mintedTokensValue = _scale(liquidityMinted.mulWadDown(tokenPriceAfter), 18, 6);

    // Assertions
    assertGt(liquidityMinted, 0, "Liquidity should be minted");
    assertEq(liquidityMinted, expectedLiquidity, "Correct liquidity should be minted");
    assertEq(tokenPriceBefore, tokenPriceAfter, "Token price should remain constant");
    assertApproxEqAbs(mintedTokensValue, depositAmount, 1, "Minted tokens value should equal deposit amount");
  }

  /// @notice Test withdrawal after bridging USDC to spot dex
  /// @dev Verify withdrawals work correctly when some USDC is on core spot
  function test_withdraw_afterBridgingToSpotDex() public {
    // First, bridge some USDC to core spot dex
    uint256 poolUsdcBalance = _getPoolUSDCBalance();
    uint256 bridgeAmount = poolUsdcBalance / 3; // Bridge one-third

    _bridgeUSDCToCore(bridgeAmount, _DEX_ID_CORE_SPOT);

    // Advance to next block to process bridge
    CoreSimulatorLib.nextBlock();

    // Make a fresh deposit with the 10-minute cooldown
    uint256 depositAmount = 12_000e6; // 12,000 USDC

    vm.startPrank(investor);
    IPoolLogic(hyperliquidTestPool).deposit(usdc, depositAmount);
    vm.stopPrank();

    // Get investor's pool tokens
    uint256 investorPoolTokens = IPoolLogic(hyperliquidTestPool).balanceOf(investor);
    assertGt(investorPoolTokens, 0, "Investor should have pool tokens");

    // Wait for exit cooldown period (5 minutes)
    vm.warp(block.timestamp + 5 minutes);
    vm.roll(block.number + 1);

    // Withdraw portion of tokens
    uint256 withdrawAmount = investorPoolTokens / 4; // Withdraw 25%

    uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(investor);
    uint256 tokenPrice = IPoolLogic(hyperliquidTestPool).tokenPrice();

    // Calculate expected USDC (convert to 6 decimals)
    uint256 expectedUSDC = (withdrawAmount * tokenPrice) / 10 ** 18 / 10 ** 12;

    // Withdraw
    vm.prank(investor);
    IPoolLogic(hyperliquidTestPool).withdraw(withdrawAmount);

    uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(investor);
    uint256 poolTokensAfter = IPoolLogic(hyperliquidTestPool).balanceOf(investor);

    // Assertions
    assertEq(poolTokensAfter, investorPoolTokens - withdrawAmount, "Correct pool tokens should be burned");
    assertApproxEqAbs(
      usdcBalanceAfter - usdcBalanceBefore,
      expectedUSDC,
      2, // Allow small difference for rounding
      "Correct USDC should be returned"
    );
  }

  /// @notice Test deposit with full USDC bridged to spot dex
  /// @dev Verify that deposits still work when all pool USDC is bridged
  function test_deposit_withFullUSDCBridgedToSpot() public {
    // Bridge all USDC to core spot dex
    uint256 poolUsdcBalance = _getPoolUSDCBalance();
    assertGt(poolUsdcBalance, 0, "Pool should have USDC");

    _bridgeUSDCToCore(poolUsdcBalance, _DEX_ID_CORE_SPOT);

    // Advance to next block
    CoreSimulatorLib.nextBlock();

    // Verify pool USDC balance is 0
    assertEq(_getPoolUSDCBalance(), 0, "Pool USDC should be 0 after full bridge");

    // Pool value should remain unchanged
    uint256 poolValue = _getTotalFundValue();
    assertGt(poolValue, 0, "Pool should still have value");

    // Setup and make deposit
    uint256 depositAmount = 15_000e6; // 15,000 USDC

    uint256 tokenPriceBefore = IPoolLogic(hyperliquidTestPool).tokenPrice();

    vm.startPrank(investor);
    uint256 liquidityMinted = IPoolLogic(hyperliquidTestPool).deposit(usdc, depositAmount);
    vm.stopPrank();

    uint256 tokenPriceAfter = IPoolLogic(hyperliquidTestPool).tokenPrice();

    // Assertions
    uint256 usdValueDeposited = _scale(depositAmount, 6, 18); // Convert to 18 decimals
    uint256 expectedLiquidityMinted = usdValueDeposited.divWadDown(tokenPriceBefore);

    assertGt(liquidityMinted, 0, "Liquidity should be minted even with bridged USDC");
    assertEq(liquidityMinted, expectedLiquidityMinted, "Correct liquidity should be minted");
    assertEq(tokenPriceBefore, tokenPriceAfter, "Token price should remain constant");

    // New USDC should be in the pool
    assertEq(_getPoolUSDCBalance(), depositAmount, "Pool should have deposited USDC");
  }

  /////////////////////////////////////////////
  //              Bridge Tests               //
  /////////////////////////////////////////////

  /// @notice Test that bridging USDC to core dex doesn't change pool value
  /// @dev The pool value should remain constant before, after, and in the next block
  function test_bridgeUSDCToCore_poolValueUnchanged() public {
    // Get pool value before bridging
    uint256 poolValueBefore = _getTotalFundValue();
    uint256 poolUsdcBalanceBefore = _getPoolUSDCBalance();

    // Ensure we have USDC to bridge
    assertGt(poolUsdcBalanceBefore, 0, "Pool should have USDC balance");

    // Amount to bridge (half of pool balance)
    uint256 bridgeAmount = poolUsdcBalanceBefore / 2;
    assertGt(bridgeAmount, 0, "Bridge amount should be greater than 0");

    // Bridge USDC to core spot dex
    _bridgeUSDCToCore(bridgeAmount, _DEX_ID_CORE_SPOT);

    // Get pool value after bridging (same block)
    uint256 poolValueAfterBridge = _getTotalFundValue();

    // Pool value should not change after bridging in the same block
    assertEq(poolValueAfterBridge, poolValueBefore, "Pool value should not change after bridging");

    // Advance to next block using CoreSimulatorLib.
    // This also processes any pending bridge actions.
    CoreSimulatorLib.nextBlock();

    // Get pool value in the next block
    uint256 poolValueNextBlock = _getTotalFundValue();

    // Pool value should remain the same in the next block
    assertEq(poolValueNextBlock, poolValueBefore, "Pool value should remain same in next block");
  }

  /// @notice Test bridging full USDC balance to core dex
  /// @dev The pool value should remain constant even when bridging all USDC
  function test_bridgeFullUSDCToCore_poolValueUnchanged() public {
    // Get pool value before bridging
    uint256 poolValueBefore = _getTotalFundValue();
    uint256 poolUsdcBalanceBefore = _getPoolUSDCBalance();

    // Ensure we have USDC to bridge
    assertGt(poolUsdcBalanceBefore, 0, "Pool should have USDC balance");

    // Bridge all USDC to core spot dex
    _bridgeUSDCToCore(poolUsdcBalanceBefore, _DEX_ID_CORE_SPOT);

    // Get pool value after bridging (same block)
    uint256 poolValueAfterBridge = _getTotalFundValue();

    // Pool value should not change after bridging
    assertEq(poolValueAfterBridge, poolValueBefore, "Pool value should not change after bridging full balance");

    // Verify USDC balance is now 0 in the pool
    uint256 poolUsdcBalanceAfter = _getPoolUSDCBalance();
    assertEq(poolUsdcBalanceAfter, 0, "Pool USDC balance should be 0 after full bridge");

    // Advance to next block
    CoreSimulatorLib.nextBlock();

    // Get pool value in the next block
    uint256 poolValueNextBlock = _getTotalFundValue();

    // Pool value should remain the same
    assertEq(poolValueNextBlock, poolValueBefore, "Pool value should remain same in next block after full bridge");
  }

  /// @notice Test multiple bridge operations maintain pool value
  /// @dev The pool value should remain constant across multiple bridge operations
  function test_multipleBridges_poolValueUnchanged() public {
    // Get initial pool value
    uint256 poolValueInitial = _getTotalFundValue();
    uint256 poolUsdcBalance = _getPoolUSDCBalance();

    // Bridge in 3 increments
    uint256 bridgeAmount = poolUsdcBalance / 4;

    for (uint256 i = 0; i < 3; i++) {
      _bridgeUSDCToCore(bridgeAmount, _DEX_ID_CORE_SPOT);

      // Verify pool value remains constant
      uint256 currentValue = _getTotalFundValue();
      assertEq(currentValue, poolValueInitial, "Pool value should remain constant after each bridge");
    }

    // Advance block between bridges
    CoreSimulatorLib.nextBlock();

    assertEq(_getTotalFundValue(), poolValueInitial, "Pool value should remain constant after block advance");
  }

  /// @notice Test that CoreDepositWallet deposits revert when the perps tracker asset is not supported.
  /// @dev This validates the fix for missing 0x3333 enforcement on the deposit-wallet path.
  function test_revert_core_deposit_without_core_writer_tracker() public {
    uint256 fundValueBefore = _getTotalFundValue();

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = coreWriter;

    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(
      new IHasSupportedAsset.Asset[](0),
      assetsToRemove
    );

    assertFalse(IHasSupportedAsset(hyperliquidTestPoolManagerLogic).isSupportedAsset(coreWriter));

    vm.expectRevert("CoreWriter not supported asset");
    _bridgeUSDCToCore(1_000e6, _DEX_ID_CORE_SPOT);

    assertEq(_getTotalFundValue(), fundValueBefore);
  }

  /// @notice Test that USD class transfers revert when the perps tracker asset is not supported.
  /// @dev This validates the hoisted 0x3333 invariant directly on the CoreWriter guard.
  function test_revert_usd_class_transfer_without_core_writer_tracker() public {
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = coreWriter;

    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(
      new IHasSupportedAsset.Asset[](0),
      assetsToRemove
    );

    bytes memory rawAction = abi.encodePacked(uint8(1), uint24(7), abi.encode(uint64(1_000e6), true));
    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, rawAction);

    vm.prank(hyperliquidTestPool);
    vm.expectRevert("CoreWriter not supported asset");
    IGuard(address(hyperliquidCoreWriterContractGuard)).txGuard(hyperliquidTestPoolManagerLogic, coreWriter, txData);
  }

  /// @notice A spot order on a pair that is NOT quoted in USDC is rejected, even for the manager and even
  ///         though the pair's base token is a supported asset. A spot order swaps the pair's two tokens,
  ///         so a sell is PAID IN the quote token; on a non-USDC pair that is a token no asset guard reads
  ///         (`HyperliquidPositionGuard` values only the USDC Core spot balance), so `totalFundValue` would
  ///         drop by the whole amount traded while the money still sits on Core.
  /// @dev On mainnet 4 of the 5 configured spot assets have such a pair — XAUT0/USDT0 (10209),
  ///      HYPE/USDT0 (10207), HYPE/USDH (10232), HYPE/USDE (10255), UBTC/USDH (10234), UETH/USDH (10235) —
  ///      and none of USDT0/USDH/USDE is a dHEDGE asset. Guarded here in the CoreWriter guard rather than
  ///      in a caller so both the manager path and the HyperliquidWithdrawalManager path are covered.
  function test_revert_spot_order_on_non_usdc_quoted_pair() public {
    // Same base token as the allowed XAUT0/USDC pair — only the quote token differs.
    assertEq(
      spotInfo(HyperEVMConfig.XAUT0_ALT_SPOT_INDEX).tokens[0],
      HyperEVMConfig.XAUT0_TOKEN_INDEX,
      "alt pair's base token is the supported XAUT0"
    );
    assertEq(
      spotInfo(HyperEVMConfig.XAUT0_ALT_SPOT_INDEX).tokens[1],
      HyperEVMConfig.USDT0_TOKEN_INDEX,
      "alt pair is quoted in USDT0"
    );
    assertTrue(
      IHasSupportedAsset(hyperliquidTestPoolManagerLogic).isSupportedAsset(HyperEVMConfig.XAUT0_SYSTEM_ADDRESS),
      "base token IS supported, so the base-token check alone would pass"
    );

    // Priced 1% under the alt pair's own spot px, i.e. within the guard's slippage cap, so the only
    // reason to reject is the quote token.
    uint64 limitPx = uint64((normalizedSpotPx(HyperEVMConfig.XAUT0_ALT_SPOT_INDEX) * 99) / 100);
    bytes memory sellForUsdt0 = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(
        uint32(10_000 + HyperEVMConfig.XAUT0_ALT_SPOT_INDEX),
        false,
        limitPx,
        uint64(1e8),
        false,
        HLConstants.LIMIT_ORDER_TIF_IOC,
        uint128(1)
      )
    );

    vm.prank(manager);
    vm.expectRevert("spot pair not USDC quoted");
    IPoolLogic(hyperliquidTestPool).execTransaction(
      coreWriter,
      abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, sellForUsdt0)
    );
  }

  /// @notice USDC cannot be removed from a vault that still holds the CoreWriter asset. USDC is the payout
  ///         asset of every Hyperliquid asset guard (`OutsidePositionWithdrawalHelper` requires it to be
  ///         enabled) and the denomination `HyperliquidPositionGuard` values the Core spot balance in, so
  ///         removing it would make EVERY withdrawal revert with "withdrawal asset not enabled" and strand
  ///         depositors until a manager re-added it.
  /// @dev The inherited empty-balance check does not catch this: `getBalance` here is the EVM balance only
  ///      (Core USDC is valued by the position guard), so with all USDC bridged to Core the balance reads 0
  ///      and the removal would otherwise be allowed. The vault needs a second deposit asset first, since
  ///      PoolManagerLogic independently requires at least one.
  function test_revert_cannot_remove_usdc_while_coreWriter_supported() public {
    // Bridge all USDC to Core so the EVM balance is 0 and the empty-balance check passes.
    _bridgeUSDCToCore(_getPoolUSDCBalance(), _DEX_ID_CORE_SPOT);
    CoreSimulatorLib.nextBlock();
    assertEq(_getPoolUSDCBalance(), 0, "EVM USDC drained to Core");

    // Give the vault a second deposit asset so "at least one deposit asset" is not what blocks removal.
    // (WHYPE, not the CoreWriter asset — the position guard rejects that as a deposit asset.)
    vm.prank(owner);
    assetHandlerProxy.addAsset(
      HyperEVMConfig.WHYPE_TOKEN_ADDRESS,
      uint16(AssetTypeIncomplete.CHAINLINK),
      HyperEVMConfig.USDC_USD_PRICE_FEED
    );
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: HyperEVMConfig.WHYPE_TOKEN_ADDRESS, isDeposit: true});
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = usdc;

    assertTrue(
      IHasSupportedAsset(hyperliquidTestPoolManagerLogic).isSupportedAsset(coreWriter),
      "vault still holds the CoreWriter asset"
    );

    vm.prank(manager);
    vm.expectRevert("USDC required for HL");
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(assetsToAdd, assetsToRemove);

    assertTrue(IHasSupportedAsset(hyperliquidTestPoolManagerLogic).isSupportedAsset(usdc), "USDC still supported");
  }

  /// @notice The Hyperliquid position asset (the CoreWriter address, asset type 39) cannot be marked as a
  ///         deposit asset. It stands in for the pool's HyperCore account rather than being a token anyone
  ///         can transfer in, so depositing it is meaningless — yet `assetValue` prices it, so a deposit
  ///         reaching the mint would credit real value for nothing.
  /// @dev Mirrors `GmxPerpMarketAssetGuard` (the equivalent perps position guard) and
  ///      `HyperliquidSpotGuard`, which both reject deposit assets with the same message. Until this check
  ///      existed the flag was accepted and the deposit only failed later, incidentally, because CoreWriter
  ///      implements no `transferFrom`.
  function test_revert_cannot_add_coreWriter_as_deposit_asset() public {
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: coreWriter, isDeposit: true});

    vm.prank(manager);
    vm.expectRevert("deposit not supported");
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(assetsToAdd, new address[](0));

    assertFalse(
      IPoolManagerLogic(hyperliquidTestPoolManagerLogic).isDepositAsset(coreWriter),
      "CoreWriter is not a deposit asset"
    );
  }

  /// @notice The position asset remains addable as a normal (non-deposit) supported asset — the check is
  ///         scoped to the deposit flag only, so the standard Hyperliquid vault setup is unaffected.
  function test_canAddCoreWriter_asNonDepositAsset() public {
    address[] memory removeCoreWriter = new address[](1);
    removeCoreWriter[0] = coreWriter;
    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(
      new IHasSupportedAsset.Asset[](0),
      removeCoreWriter
    );
    assertFalse(IHasSupportedAsset(hyperliquidTestPoolManagerLogic).isSupportedAsset(coreWriter), "removed");

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: coreWriter, isDeposit: false});
    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(assetsToAdd, new address[](0));

    assertTrue(IHasSupportedAsset(hyperliquidTestPoolManagerLogic).isSupportedAsset(coreWriter), "re-added");
  }

  /// @notice The invariant is scoped to Hyperliquid vaults: with the CoreWriter asset already gone, nothing
  ///         needs USDC as a payout asset, so removing it is permitted as before.
  function test_canRemoveUsdc_afterCoreWriterRemoved() public {
    // Drop CoreWriter first (its value is 0 — nothing has been bridged in this test).
    address[] memory removeCoreWriter = new address[](1);
    removeCoreWriter[0] = coreWriter;
    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(
      new IHasSupportedAsset.Asset[](0),
      removeCoreWriter
    );

    // Move the EVM USDC out so the inherited empty-balance check passes, then remove it. WHYPE stands in
    // as the replacement deposit asset PoolManagerLogic requires.
    vm.prank(owner);
    assetHandlerProxy.addAsset(
      HyperEVMConfig.WHYPE_TOKEN_ADDRESS,
      uint16(AssetTypeIncomplete.CHAINLINK),
      HyperEVMConfig.USDC_USD_PRICE_FEED
    );
    deal(usdc, hyperliquidTestPool, 0);

    IHasSupportedAsset.Asset[] memory addWhype = new IHasSupportedAsset.Asset[](1);
    addWhype[0] = IHasSupportedAsset.Asset({asset: HyperEVMConfig.WHYPE_TOKEN_ADDRESS, isDeposit: true});
    address[] memory removeUsdc = new address[](1);
    removeUsdc[0] = usdc;

    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(addWhype, removeUsdc);

    assertFalse(IHasSupportedAsset(hyperliquidTestPoolManagerLogic).isSupportedAsset(usdc), "USDC removable");
  }

  /// @dev Makes the vault report USDC as unsupported WITHOUT removing it. `HyperliquidERC20Guard` now
  ///      blocks removing USDC while the CoreWriter asset is supported (USDC is the payout asset of every
  ///      Hyperliquid guard), so this state is no longer reachable through `changeAssets` — see
  ///      {test_revert_cannot_remove_usdc_while_coreWriter_supported}. The txGuard branches exercised
  ///      below are kept as defence in depth, and this mock is how they stay covered. Exact-calldata
  ///      match, so lookups for every other asset still hit the real PoolManagerLogic.
  function _mockUsdcUnsupported() internal {
    vm.mockCall(
      hyperliquidTestPoolManagerLogic,
      abi.encodeWithSelector(IHasSupportedAsset.isSupportedAsset.selector, usdc),
      abi.encode(false)
    );
  }

  /// @notice Test that spot-send rejects USDC when EVM USDC is not a supported asset.
  /// @dev This validates the fix for the USDC bypass on action 6.
  function test_revert_spot_send_usdc_when_usdc_not_supported() public {
    uint256 poolUsdcBalance = _getPoolUSDCBalance();
    _bridgeUSDCToCore(poolUsdcBalance, _DEX_ID_CORE_SPOT);
    CoreSimulatorLib.nextBlock();

    assertEq(_getPoolUSDCBalance(), 0, "Pool USDC should be 0 after full bridge");

    _mockUsdcUnsupported();

    uint256 fundValueBefore = _getTotalFundValue();
    uint256 poolUsdcBefore = IERC20(usdc).balanceOf(hyperliquidTestPool);

    vm.expectRevert("unsupported asset");
    vm.prank(manager);
    IPoolLogic(hyperliquidTestPool).execTransaction(
      coreWriter,
      abi.encodeWithSelector(
        ICoreWriter.sendRawAction.selector,
        abi.encodePacked(
          uint8(1),
          uint24(6),
          abi.encode(getSystemAddress(_USDC_TOKEN_INDEX), _USDC_TOKEN_INDEX, uint64(1_000e6 * 1e2))
        )
      )
    );

    assertFalse(IHasSupportedAsset(hyperliquidTestPoolManagerLogic).isSupportedAsset(usdc));
    assertEq(IERC20(usdc).balanceOf(hyperliquidTestPool), poolUsdcBefore);
    assertEq(_getTotalFundValue(), fundValueBefore);
  }

  /// @notice Test that send-asset rejects USDC when EVM USDC is not a supported asset.
  /// @dev The simulator does not execute action 13, so this validates the affected txGuard branch directly.
  function test_revert_send_asset_when_usdc_not_supported() public {
    uint256 poolUsdcBalance = _getPoolUSDCBalance();
    _bridgeUSDCToCore(poolUsdcBalance, _DEX_ID_CORE_SPOT);
    CoreSimulatorLib.nextBlock();

    assertEq(_getPoolUSDCBalance(), 0, "Pool USDC should be 0 after full bridge");

    _mockUsdcUnsupported();

    bytes memory rawAction = abi.encodePacked(
      uint8(1),
      uint24(13),
      abi.encode(
        getSystemAddress(_USDC_TOKEN_INDEX),
        address(0),
        _DEX_ID_CORE_PERP,
        _DEX_ID_CORE_SPOT,
        _USDC_TOKEN_INDEX,
        uint64(1_000e6 * 1e2)
      )
    );
    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, rawAction);

    vm.prank(hyperliquidTestPool);
    vm.expectRevert("unsupported asset");
    IGuard(address(hyperliquidCoreWriterContractGuard)).txGuard(hyperliquidTestPoolManagerLogic, coreWriter, txData);
  }

  /// @notice Test that send-asset L1 self-transfers reject non-USDC tokens.
  /// @dev The simulator does not execute action 13, so this validates the affected txGuard branch directly.
  function test_revert_send_asset_self_transfer_non_usdc() public {
    bytes memory rawAction = abi.encodePacked(
      uint8(1),
      uint24(13),
      abi.encode(
        hyperliquidTestPool,
        address(0),
        _DEX_ID_CORE_SPOT,
        _DEX_ID_CORE_PERP,
        uint64(HyperEVMConfig.XAUT0_TOKEN_INDEX),
        uint64(1e8)
      )
    );
    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, rawAction);

    vm.prank(hyperliquidTestPool);
    vm.expectRevert("only USDC self-transfers");
    IGuard(address(hyperliquidCoreWriterContractGuard)).txGuard(hyperliquidTestPoolManagerLogic, coreWriter, txData);
  }

  /// @notice Test that send-asset rejects a destination dex that is approved but disabled.
  function test_revert_send_asset_to_disabled_dex() public {
    uint256 disabledDexId = 1;

    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory settings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: disabledDexId,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.DISABLED
    });

    vm.prank(owner);
    hyperliquidCoreWriterContractGuard.setDexIdStatus(settings);

    bytes memory rawAction = abi.encodePacked(
      uint8(1),
      uint24(13),
      abi.encode(hyperliquidTestPool, address(0), _DEX_ID_CORE_PERP, disabledDexId, _USDC_TOKEN_INDEX, uint64(1_000e8))
    );
    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, rawAction);

    vm.prank(hyperliquidTestPool);
    vm.expectRevert("invalid destination dex");
    IGuard(address(hyperliquidCoreWriterContractGuard)).txGuard(hyperliquidTestPoolManagerLogic, coreWriter, txData);
  }

  /// @notice Test that a USDC send-asset self-transfer to the core perp dex passes the guard.
  function test_send_asset_usdc_self_transfer_allowed() public {
    bytes memory rawAction = abi.encodePacked(
      uint8(1),
      uint24(13),
      abi.encode(
        hyperliquidTestPool,
        address(0),
        _DEX_ID_CORE_SPOT,
        _DEX_ID_CORE_PERP,
        _USDC_TOKEN_INDEX,
        uint64(1_000e8)
      )
    );
    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, rawAction);

    vm.prank(hyperliquidTestPool);
    (uint16 txType, bool isPublic) = IGuard(address(hyperliquidCoreWriterContractGuard)).txGuard(
      hyperliquidTestPoolManagerLogic,
      coreWriter,
      txData
    );

    assertEq(
      txType,
      uint16(ITransactionTypes.TransactionType.HyperliquidSendAssetAction),
      "should return send-asset tx type"
    );
    assertFalse(isPublic, "manager self-transfer should not be public");
  }

  /////////////////////////////////////////////
  //          API Wallet (Agent) Tests       //
  /////////////////////////////////////////////

  /// @notice Helper to build an action 9 (Add API wallet) raw CoreWriter action.
  function _addApiWalletAction(address apiWallet, string memory name) internal pure returns (bytes memory) {
    return abi.encodePacked(uint8(1), uint24(9), abi.encode(apiWallet, name));
  }

  /// @notice Helper to enable/disable API wallet registration for the test pool as the owner.
  function _setApiWalletEnabled(bool enabled) internal {
    IHyperliquidCoreWriterContractGuard.ApiWalletSetting[]
      memory settings = new IHyperliquidCoreWriterContractGuard.ApiWalletSetting[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.ApiWalletSetting({
      poolLogic: hyperliquidTestPool,
      enabled: enabled
    });

    vm.prank(owner);
    hyperliquidCoreWriterContractGuard.setApiWalletEnabled(settings);
  }

  /// @notice Action 9 must revert when the pool has not been opted in by the owner (disabled by default).
  function test_revert_add_api_wallet_when_not_enabled() public {
    bytes memory txData = abi.encodeWithSelector(
      ICoreWriter.sendRawAction.selector,
      _addApiWalletAction(address(0xABCD), "agent")
    );

    vm.prank(hyperliquidTestPool);
    vm.expectRevert("api wallet not enabled");
    IGuard(address(hyperliquidCoreWriterContractGuard)).txGuard(hyperliquidTestPoolManagerLogic, coreWriter, txData);
  }

  /// @notice Once enabled by the owner, the manager can register any API wallet address via action 9.
  function test_add_api_wallet_succeeds_when_enabled() public {
    _setApiWalletEnabled(true);

    assertTrue(hyperliquidCoreWriterContractGuard.apiWalletEnabled(hyperliquidTestPool));

    bytes memory txData = abi.encodeWithSelector(
      ICoreWriter.sendRawAction.selector,
      _addApiWalletAction(address(0xABCD), "agent")
    );

    vm.prank(hyperliquidTestPool);
    (uint16 txType, bool isPublic) = IGuard(address(hyperliquidCoreWriterContractGuard)).txGuard(
      hyperliquidTestPoolManagerLogic,
      coreWriter,
      txData
    );

    assertEq(txType, uint16(ITransactionTypes.TransactionType.HyperliquidAddApiWallet));
    assertFalse(isPublic);

    // End-to-end: the manager can route the action through the pool without reverting.
    vm.prank(manager);
    IPoolLogic(hyperliquidTestPool).execTransaction(coreWriter, txData);
  }

  /// @notice Only the owner can toggle the per-pool API wallet flag.
  function test_revert_setApiWalletEnabled_non_owner() public {
    IHyperliquidCoreWriterContractGuard.ApiWalletSetting[]
      memory settings = new IHyperliquidCoreWriterContractGuard.ApiWalletSetting[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.ApiWalletSetting({poolLogic: hyperliquidTestPool, enabled: true});

    vm.prank(manager);
    vm.expectRevert();
    hyperliquidCoreWriterContractGuard.setApiWalletEnabled(settings);
  }

  /////////////////////////////////////////////
  //          Spot Asset Trading Tests       //
  /////////////////////////////////////////////

  /// @notice Test that a spot token transfer to its own system address passes the spot guard.
  function test_spot_transfer_to_system_address_allowed() public {
    bytes memory txData = abi.encodeWithSelector(
      IERC20.transfer.selector,
      HyperEVMConfig.XAUT0_SYSTEM_ADDRESS,
      uint256(1e8)
    );

    (uint16 txType, bool isPublic) = IGuard(hyperliquidSpotGuard).txGuard(
      hyperliquidTestPoolManagerLogic,
      xaut,
      txData
    );

    assertEq(
      txType,
      uint16(ITransactionTypes.TransactionType.HyperliquidSystemAddressTransfer),
      "should return system address transfer tx type"
    );
    assertFalse(isPublic, "system address transfer should not be public");
  }

  /// @notice Test that a spot token transfer is rejected when the registry index
  ///         doesn't match the token's linked EVM contract per the tokenInfo precompile.
  function test_revert_spot_transfer_when_registry_index_mismatch() public {
    // Simulate a wrong/stale registry entry: registry returns the HYPE token index for `xaut`.
    vm.mockCall(
      address(TOKEN_REGISTRY),
      abi.encodeWithSelector(TOKEN_REGISTRY.getTokenIndex.selector, xaut),
      abi.encode(uint32(_MAINNET_HYPE_TOKEN_INDEX))
    );

    bytes memory txData = abi.encodeWithSelector(
      IERC20.transfer.selector,
      HyperEVMConfig.XAUT0_SYSTEM_ADDRESS,
      uint256(1e8)
    );

    vm.expectRevert("evm contract mismatch");
    IGuard(hyperliquidSpotGuard).txGuard(hyperliquidTestPoolManagerLogic, xaut, txData);
  }

  /// @notice Test non-system spot withdrawals pay mixed assets: spot token (EVM leg) + USDC (Core leg)
  function test_spotAsset_nonSystem_withdraw_mixedPayout() public {
    // Setup: make the EVM token address a supported type-40 spot asset and remove the system-address mapping.
    vm.startPrank(owner);
    assetHandlerProxy.addAsset(xaut, uint16(AssetTypeIncomplete.HYPERLIQUID_SPOT), xaut0PriceAggregator);
    vm.stopPrank();

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: xaut, isDeposit: false});

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = HyperEVMConfig.XAUT0_SYSTEM_ADDRESS;

    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(assetsToAdd, assetsToRemove);

    // Set XAUT0 spot price to $2800 and buy 1 XAUT0 on Core.
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    uint256 poolUSDCBalance = _getPoolUSDCBalance();
    _bridgeUSDCToCore(poolUSDCBalance / 2, HLConstants.SPOT_DEX);
    CoreSimulatorLib.nextBlock();

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100);
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, limitPrice, uint64(1e8), false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );

    _placeLimitOrder(orderActionData);
    CoreSimulatorLib.nextBlock();

    // Seed EVM-side XAUT balance so withdrawal has an in-kind leg.
    uint256 evmXautInPool = 1e8;
    deal(xaut, hyperliquidTestPool, evmXautInPool);

    uint256 managerXautBefore = IERC20(xaut).balanceOf(manager);
    uint256 managerUsdcBefore = IERC20(usdc).balanceOf(manager);
    uint256 managerShares = IPoolLogic(hyperliquidTestPool).balanceOf(manager);

    // Withdraw half shares (portion = 0.5).
    skip(5 minutes + 1);
    vm.prank(manager);
    IPoolLogic(hyperliquidTestPool).withdraw(managerShares / 2);

    // Mixed payout expectations:
    // 1) manager receives XAUT from the EVM-held leg,
    // 2) manager receives USDC for the Core-held leg.
    assertGt(IERC20(xaut).balanceOf(manager) - managerXautBefore, 0, "manager should receive XAUT in-kind");
    assertGt(IERC20(usdc).balanceOf(manager) - managerUsdcBefore, 0, "manager should receive USDC for core leg");
  }

  /// @notice Test that the EasySwapperV2 two-step withdrawal tracks the in-kind EVM leg of a
  ///         non-system spot asset, so it can be claimed instead of being stranded in the vault.
  function test_easySwapperV2_initWithdrawal_tracks_nonSystem_spot_token() public {
    // Setup: make the EVM token address a supported type-40 spot asset and remove the system-address mapping.
    vm.prank(owner);
    assetHandlerProxy.addAsset(xaut, uint16(AssetTypeIncomplete.HYPERLIQUID_SPOT), xaut0PriceAggregator);

    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: xaut, isDeposit: false});

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = HyperEVMConfig.XAUT0_SYSTEM_ADDRESS;

    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(assetsToAdd, assetsToRemove);

    // Buy 1 XAUT0 on Core (Core leg, paid out as USDC on withdrawal).
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    _bridgeUSDCToCore(_getPoolUSDCBalance() / 2, HLConstants.SPOT_DEX);
    CoreSimulatorLib.nextBlock();

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100);
    _placeLimitOrder(
      abi.encodePacked(
        uint8(1),
        HLConstants.LIMIT_ORDER_ACTION,
        abi.encode(
          10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX),
          true,
          limitPrice,
          uint64(1e8),
          false,
          HLConstants.LIMIT_ORDER_TIF_IOC,
          uint128(1)
        )
      )
    );
    CoreSimulatorLib.nextBlock();

    // Seed EVM-side XAUT balance (EVM leg, paid out in-kind on withdrawal).
    uint256 evmXautInPool = 1e8;
    deal(xaut, hyperliquidTestPool, evmXautInPool);

    // Deploy EasySwapperV2 with its WithdrawalVault logic (both 0.7.6, hence deployCode).
    address easySwapper = deployCode("EasySwapperV2.sol");
    vm.startPrank(owner);
    IEasySwapperV2Mock(easySwapper).initialize(
      deployCode("WithdrawalVault.sol"),
      address(0), // unused (deprecated) parameter
      HyperEVMConfig.WHYPE_TOKEN_ADDRESS,
      makeAddr("swapper"), // only used by the swap completion path, not exercised here
      3600
    );
    IEasySwapperV2Mock(easySwapper).setdHedgePoolFactory(address(poolFactoryProxy));
    vm.stopPrank();

    // Two-step withdrawal of half of manager's shares (portion = 0.5).
    uint256 sharesToWithdraw = IPoolLogic(hyperliquidTestPool).balanceOf(manager) / 2;
    uint256 supportedAssetsCount = IHasSupportedAsset(hyperliquidTestPoolManagerLogic).getSupportedAssets().length;

    skip(5 minutes + 1);
    vm.startPrank(manager);
    IERC20(hyperliquidTestPool).approve(easySwapper, sharesToWithdraw);
    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = IEasySwapperV2Mock(easySwapper)
      .initWithdrawal(hyperliquidTestPool, sharesToWithdraw, new IPoolLogic.ComplexAsset[](supportedAssetsCount));

    // The vault must track both payout legs: XAUT in-kind (EVM leg) and USDC (Core leg).
    uint256 trackedXaut;
    uint256 trackedUsdc;
    for (uint256 i; i < trackedAssets.length; ++i) {
      if (trackedAssets[i].token == xaut) trackedXaut = trackedAssets[i].balance;
      if (trackedAssets[i].token == usdc) trackedUsdc = trackedAssets[i].balance;
    }
    assertEq(trackedXaut, evmXautInPool / 2, "vault should track XAUT EVM leg");
    assertGt(trackedUsdc, 0, "vault should track USDC");

    // Completing the withdrawal pays out both legs; nothing is stranded in the vault.
    uint256 managerXautBefore = IERC20(xaut).balanceOf(manager);
    uint256 managerUsdcBefore = IERC20(usdc).balanceOf(manager);

    IEasySwapperV2Mock(easySwapper).completeWithdrawal();
    vm.stopPrank();

    assertEq(IERC20(xaut).balanceOf(manager) - managerXautBefore, evmXautInPool / 2, "manager should receive XAUT");
    assertGt(IERC20(usdc).balanceOf(manager) - managerUsdcBefore, 0, "manager should receive USDC");
    assertEq(IERC20(xaut).balanceOf(vault), 0, "no XAUT stranded in vault");
    assertEq(IERC20(usdc).balanceOf(vault), 0, "no USDC stranded in vault");
  }

  /// @notice Test spot asset (XAUT0) integration: place IOC order, verify accounting, and withdrawal
  /// @dev Complete flow: bridge USDC, buy XAUT0, check balances, and withdraw
  function test_spotAsset_buyXAUT0AndWithdraw() public {
    // Setup: Set XAUT0 spot price to $2800
    // XAUT0 has szDecimals = 2, so price is in (8 - szDecimals) = 6 decimals
    uint64 xaut0Price = 2800e6; // $2800 with 6 decimals (8 - 2)
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    // Store initial values
    uint256 poolValueBefore = _getTotalFundValue();
    uint256 initialManagerBalance = IPoolLogic(hyperliquidTestPool).balanceOf(manager);

    // Bridge USDC to core spot for trading (use half of pool's USDC balance)
    uint256 poolUSDCBalance = _getPoolUSDCBalance();
    _bridgeUSDCToCore(poolUSDCBalance / 2, HLConstants.SPOT_DEX);
    CoreSimulatorLib.nextBlock();

    // Verify pool value after bridge (should be unchanged)
    assertEq(_getTotalFundValue(), poolValueBefore, "Pool value should be unchanged after bridging to core");

    // 1. Place IOC order to buy XAUT0
    // Buy 1 XAUT0 token at $2800 = $2,800 worth (should be within available USDC)
    // limitPx must be in normalized format (8 decimals) to match simulator and guard validation
    // For XAUT0: szDecimals=2, so we normalize from 6 decimals to 8 decimals
    uint64 normalizedPrice = xaut0Price * 100; // Convert from 6 decimals to 8 decimals (multiply by 10^szDecimals)
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100); // +1% slippage to ensure immediate fill

    // For spot assets, assetId = 10000 + spotIndex
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    // Place the order through the pool using CoreWriter
    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(
        xaut0AssetId, // asset: spot asset ID = 10000 + spotIndex
        true, // isBuy
        limitPrice, // limitPx in normalized format (8 decimals for XAUT0)
        uint64(1e8), // sz: 1 XAUT0 with 8 decimals
        false, // reduceOnly
        HLConstants.LIMIT_ORDER_TIF_IOC, // encodedTif: IOC order
        uint128(1) // cloid
      )
    );

    _placeLimitOrder(orderActionData);

    // Advance to next block - this will process and execute the pending order
    CoreSimulatorLib.nextBlock();

    // 2. Verify pool accounting after buying XAUT0
    PrecompileLib.SpotBalance memory xaut0Balance = PrecompileLib.spotBalance(
      hyperliquidTestPool,
      HyperEVMConfig.XAUT0_TOKEN_INDEX
    );
    assertGt(xaut0Balance.total, 0, "Pool should have XAUT0 balance on core");
    assertEq(xaut0Balance.total, 1e8, "XAUT0 balance should be 1 token");

    // Check pool value includes XAUT0 position
    uint256 poolValueWithXAUT0 = _getTotalFundValue();
    assertGt(poolValueWithXAUT0, 0, "Pool value should be greater than 0");

    // The pool value should be approximately the same (accounting for trading fees)
    assertApproxEqAbs(
      poolValueWithXAUT0,
      poolValueBefore,
      poolValueBefore / 100, // 1% tolerance
      "Pool value should be approximately unchanged after trade"
    );

    // Check XAUT0 position value
    uint256 xaut0PositionValue = IPoolManagerLogic(hyperliquidTestPoolManagerLogic).assetValue(
      HyperEVMConfig.XAUT0_SYSTEM_ADDRESS
    );
    assertGt(xaut0PositionValue, 0, "XAUT0 position should have value");

    // Expected value: 1 XAUT0 * $2800 = $2,800 (in 18 decimals)
    // The price aggregator returns normalizedSpotPx (8 decimals) scaled to 18 decimals by AssetHandler
    // AssetHandler.getUSDPrice scales: 2800e8 * 1e10 = 2800e18
    uint256 expectedValue = uint256(xaut0Price) * 1e12; // Convert from 6 decimals to 18 decimals
    assertApproxEqAbs(
      xaut0PositionValue,
      expectedValue,
      expectedValue / 100, // 1% tolerance
      "XAUT0 position value should match expected"
    );

    // 3. Test withdrawal with sufficient USDC liquidity
    // Wait for the exit cooldown period (5 minutes)
    skip(5 minutes + 1);

    uint256 managerUsdcBefore = IERC20(usdc).balanceOf(manager);

    vm.startPrank(manager);
    IPoolLogic(hyperliquidTestPool).withdraw(initialManagerBalance / 2);
    vm.stopPrank();

    // Verify manager received USDC
    assertGt(IERC20(usdc).balanceOf(manager) - managerUsdcBefore, 0, "Manager should receive USDC from withdrawal");

    // Verify pool still holds XAUT0 position
    assertEq(
      PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      1e8,
      "Pool should still hold 1 XAUT0 after partial withdrawal"
    );

    // Note: Pool value won't decrease proportionally because XAUT0 can't be easily converted to USDC
    // during withdrawal. The pool still holds the full XAUT0 position, so the value remains higher.
    // In production, a manager would need to sell XAUT0 back to USDC before large withdrawals.
  }

  /// @notice Test that a manager cannot remove a spot asset if they placed an order involving it in the same transaction
  /// @dev The HyperliquidCoreWriterContractGuard sets a transient storage flag when a spot order is placed.
  ///      HyperliquidSpotGuard.removeAssetCheck reads this flag and reverts if it is set.
  function test_revert_cannot_remove_spot_asset_after_placing_order() public {
    // Setup: Set XAUT0 spot price
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    // Bridge USDC to core spot for trading
    uint256 poolUSDCBalance = _getPoolUSDCBalance();
    _bridgeUSDCToCore(poolUSDCBalance / 2, HLConstants.SPOT_DEX);
    CoreSimulatorLib.nextBlock();

    // Place IOC order to buy XAUT0 — this sets the transient storage flag
    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100);
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, limitPrice, uint64(1e8), false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );

    _placeLimitOrder(orderActionData);

    // Do NOT advance the block — the order hasn't been processed yet, so balance is still 0.
    // However, the transient storage flag is set, so removing the asset should revert.

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = HyperEVMConfig.XAUT0_SYSTEM_ADDRESS;

    vm.startPrank(manager);
    vm.expectRevert("spot asset action performed");
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(
      new IHasSupportedAsset.Asset[](0),
      assetsToRemove
    );
  }

  /// @notice The post-action settlement lock blocks spot-asset removal in the placement block AND the
  ///         `SPOT_ACTION_LOCK_BLOCKS` (N) that follow (B through B+N), then permits it from B+N+1.
  ///         Reproduces the original same-block-only gap: an IOC buy is enqueued, blocks pass with the
  ///         order still unfilled (Core balance 0), and removal must STILL revert at B+N. One more block
  ///         (B+N+1) clears the lock.
  /// @dev Blocks are advanced manually (vm.roll) so the queued order stays unfilled; the lock is
  ///      block-based, so removal is blocked through B+N and cleared at B+N+1.
  function test_spotActionLock_blocksRemovalUntilSettlementWindowElapses() public {
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    // Bridge USDC to core spot so the pool can place a spot buy.
    uint256 poolUSDCBalance = _getPoolUSDCBalance();
    _bridgeUSDCToCore(poolUSDCBalance / 2, HLConstants.SPOT_DEX);
    CoreSimulatorLib.nextBlock();

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100); // within the slippage bound
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    // IOC buy — enqueued, not yet filled. Sets the settlement lock at the current timestamp.
    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, limitPrice, uint64(1e8), false, HLConstants.LIMIT_ORDER_TIF_IOC, uint128(1))
    );
    _placeLimitOrder(orderActionData);

    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = HyperEVMConfig.XAUT0_SYSTEM_ADDRESS;

    // Advance to B+N — the last block of the lock window; the order is still unfilled (balance 0).
    uint256 lockBlocks = hyperliquidCoreWriterContractGuard.SPOT_ACTION_LOCK_BLOCKS();
    vm.roll(block.number + lockBlocks);
    assertEq(
      PrecompileLib.spotBalance(hyperliquidTestPool, HyperEVMConfig.XAUT0_TOKEN_INDEX).total,
      0,
      "precondition: pending IOC buy has not filled yet"
    );

    // B+N is still covered: removal must be blocked even though blocks have passed.
    vm.prank(manager);
    vm.expectRevert("spot asset action performed");
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(
      new IHasSupportedAsset.Asset[](0),
      assetsToRemove
    );

    // At B+N+1 the lock clears (settlement would be reflected by now) and removal is permitted again.
    vm.roll(block.number + 1);
    vm.prank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(
      new IHasSupportedAsset.Asset[](0),
      assetsToRemove
    );

    assertFalse(
      IHasSupportedAsset(hyperliquidTestPoolManagerLogic).isSupportedAsset(HyperEVMConfig.XAUT0_SYSTEM_ADDRESS),
      "spot asset should be removable after the settlement window elapses"
    );
  }

  /////////////////////////////////////////////
  //        Time-In-Force Guard Tests        //
  /////////////////////////////////////////////

  /// @notice An ALO (post-only) spot buy is rejected by the guard, regardless of the reduce-only flag.
  /// @dev Resting spot orders (ALO/GTC) must be sells, so every spot acquisition is an IOC that settles
  ///      within the CoreWriter delay. A resting buy could otherwise sit on the book and fill after the
  ///      post-action removal lock expired, delivering NAV-invisible tokens to a since-removed asset.
  ///      The revert happens in the guard, before the order reaches Core.
  function test_revert_aloSpotBuy() public {
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100); // within the slippage bound
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    // ALO spot buy (isBuy = true), reduceOnly = false.
    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, limitPrice, uint64(1e8), false, HLConstants.LIMIT_ORDER_TIF_ALO, uint128(1))
    );

    vm.expectRevert("resting spot order must be sell");
    _placeLimitOrder(orderActionData);
  }

  /// @notice A GTC spot buy is rejected even when reduce-only is set.
  /// @dev Proves the guard keys on the order side, not reduceOnly (which has no well-defined spot
  ///      meaning), and that GTC is constrained identically to ALO. The revert happens in the guard.
  function test_revert_reduceOnly_gtcSpotBuy() public {
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100); // within the slippage bound
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    // GTC spot buy (isBuy = true), reduceOnly = true — still rejected because it's a buy.
    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, limitPrice, uint64(1e8), true, HLConstants.LIMIT_ORDER_TIF_GTC, uint128(1))
    );

    vm.expectRevert("resting spot order must be sell");
    _placeLimitOrder(orderActionData);
  }

  /// @notice An ALO (post-only) spot sell priced far from the oracle is rejected by the slippage bound.
  /// @dev Uses a sell so it passes the resting-spot-order check and reaches the oracle-anchored slippage
  ///      bound (reduceOnly is irrelevant — the guard keys on the order side). Guards against a manager
  ///      resting a post-only order at an off-market price for a colluding counterparty. The revert
  ///      happens in the guard, before Core.
  function test_revert_aloOrder_offMarket_exceedsSlippage() public {
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice / 10; // sell 90% below oracle
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    // ALO spot sell (isBuy = false), reduceOnly = false — allowed past the resting check because it's a sell.
    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, false, limitPrice, uint64(1e8), false, HLConstants.LIMIT_ORDER_TIF_ALO, uint128(1))
    );

    vm.expectRevert("Slippage exceeds limit");
    _placeLimitOrder(orderActionData);
  }

  /// @notice An unrecognised time-in-force value is rejected instead of bypassing the price bound.
  /// @dev INVALID (0) and any out-of-enum TIF must hit the explicit reject, not fall through unchecked.
  function test_revert_unsupportedTif() public {
    uint64 xaut0Price = 2800e6;
    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), xaut0Price);

    uint64 normalizedPrice = xaut0Price * 100;
    uint64 limitPrice = normalizedPrice + ((normalizedPrice * 1) / 100);
    uint32 xaut0AssetId = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);

    bytes memory orderActionData = abi.encodePacked(
      uint8(1),
      HLConstants.LIMIT_ORDER_ACTION,
      abi.encode(xaut0AssetId, true, limitPrice, uint64(1e8), false, uint8(0), uint128(1)) // TIF = INVALID
    );

    vm.expectRevert("unsupported tif");
    _placeLimitOrder(orderActionData);
  }

  /////////////////////////////////////////////
  //        addAssetCheck Guard Tests        //
  /////////////////////////////////////////////

  /// @notice Test that adding a system address as a deposit asset reverts
  function test_revert_addAssetCheck_system_address_deposit_not_supported() public {
    // First remove the existing XAUT0 system address asset so we can re-add it
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = HyperEVMConfig.XAUT0_SYSTEM_ADDRESS;

    vm.startPrank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(
      new IHasSupportedAsset.Asset[](0),
      assetsToRemove
    );

    // Attempt to add XAUT0 system address with isDeposit: true — should revert
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: HyperEVMConfig.XAUT0_SYSTEM_ADDRESS, isDeposit: true});

    vm.expectRevert("deposit not supported");
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(assetsToAdd, new address[](0));
  }

  /// @notice Test that adding a system address as a non-deposit asset succeeds
  function test_addAssetCheck_system_address_non_deposit_succeeds() public {
    // First remove the existing XAUT0 system address asset so we can re-add it
    address[] memory assetsToRemove = new address[](1);
    assetsToRemove[0] = HyperEVMConfig.XAUT0_SYSTEM_ADDRESS;

    vm.startPrank(manager);
    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(
      new IHasSupportedAsset.Asset[](0),
      assetsToRemove
    );

    // Add XAUT0 system address with isDeposit: false — should succeed
    IHasSupportedAsset.Asset[] memory assetsToAdd = new IHasSupportedAsset.Asset[](1);
    assetsToAdd[0] = IHasSupportedAsset.Asset({asset: HyperEVMConfig.XAUT0_SYSTEM_ADDRESS, isDeposit: false});

    IChangeAssets(address(hyperliquidTestPoolManagerLogic)).changeAssets(assetsToAdd, new address[](0));

    assertTrue(
      IHasSupportedAsset(address(hyperliquidTestPoolManagerLogic)).isSupportedAsset(
        HyperEVMConfig.XAUT0_SYSTEM_ADDRESS
      ),
      "XAUT0 system address should be a supported asset"
    );
  }
}
