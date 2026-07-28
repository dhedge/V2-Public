// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IGMTokenManager} from "contracts/interfaces/ondo/IGMTokenManager.sol";
import {IOndoAttestationOracle} from "contracts/interfaces/ondo/IOndoAttestationOracle.sol";
import {OndoGMSwapContractGuard} from "contracts/guards/contractGuards/ondo/OndoGMSwapContractGuard.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {OndoGMSwapTestSetup} from "test/integration/common/ondo/OndoGMSwapTestSetup.t.sol";

contract OndoGMSwapTestEthereum is OndoGMSwapTestSetup, EthereumSetup {
  constructor() EthereumSetup(24724485) OndoGMSwapTestSetup() {}

  function setUp() public override(OndoGMSwapTestSetup, EthereumSetup) {
    EthereumSetup.setUp();
    OndoGMSwapTestSetup.setUp();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OndoGMSwap — Initialize
  // ═══════════════════════════════════════════════════════════════════════

  function test_initialize_setsPoolFactory() public view {
    (bool success, bytes memory data) = ondoGMSwap.staticcall(abi.encodeWithSignature("poolFactory()"));
    require(success, "poolFactory() call failed");
    address pf = abi.decode(data, (address));
    assertEq(pf, address(poolFactoryProxy));
  }

  function test_initialize_setsUsdc() public view {
    (bool success, bytes memory data) = ondoGMSwap.staticcall(abi.encodeWithSignature("usdc()"));
    require(success, "usdc() call failed");
    address usdc = abi.decode(data, (address));
    assertEq(usdc, usdcData.asset);
  }

  function test_initialize_setsGMTokenManager() public view {
    (bool success, bytes memory data) = ondoGMSwap.staticcall(abi.encodeWithSignature("gmTokenManager()"));
    require(success, "gmTokenManager() call failed");
    address gm = abi.decode(data, (address));
    assertEq(gm, GM_TOKEN_MANAGER);
  }

  function test_revert_initialize_zeroPoolFactory() public {
    address impl = deployCode("OndoGMSwap.sol:OndoGMSwap");
    address newSwap = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "_poolFactory"));
    (bool success, ) = newSwap.call(
      abi.encodeWithSignature(
        "initialize(address,address,address,address)",
        owner,
        address(0),
        GM_TOKEN_MANAGER,
        usdcData.asset
      )
    );
    require(success);
  }

  function test_revert_initialize_zeroGMTokenManager() public {
    address impl = deployCode("OndoGMSwap.sol:OndoGMSwap");
    address newSwap = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "_gmTokenManager"));
    (bool success, ) = newSwap.call(
      abi.encodeWithSignature(
        "initialize(address,address,address,address)",
        owner,
        address(poolFactoryProxy),
        address(0),
        usdcData.asset
      )
    );
    require(success);
  }

  function test_revert_initialize_zeroUsdc() public {
    address impl = deployCode("OndoGMSwap.sol:OndoGMSwap");
    address newSwap = address(new TransparentUpgradeableProxy(impl, proxyAdmin, ""));
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "_usdc"));
    (bool success, ) = newSwap.call(
      abi.encodeWithSignature(
        "initialize(address,address,address,address)",
        owner,
        address(poolFactoryProxy),
        GM_TOKEN_MANAGER,
        address(0)
      )
    );
    require(success);
  }

  function test_revert_initialize_alreadyInitialized() public {
    vm.expectRevert();
    (bool success, ) = ondoGMSwap.call(
      abi.encodeWithSignature(
        "initialize(address,address,address,address)",
        owner,
        address(poolFactoryProxy),
        GM_TOKEN_MANAGER,
        usdcData.asset
      )
    );
    require(success);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OndoGMSwap — swapExactInWithAttestation (Mint)
  // ═══════════════════════════════════════════════════════════════════════

  function test_mint_swapExactInWithAttestation() public {
    uint256 poolUsdcBefore = IERC20(usdcData.asset).balanceOf(address(testPool));
    uint256 poolGooglonBefore = IERC20(GOOGLON).balanceOf(address(testPool));

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));

    uint256 poolUsdcAfter = IERC20(usdcData.asset).balanceOf(address(testPool));
    uint256 poolGooglonAfter = IERC20(GOOGLON).balanceOf(address(testPool));

    // USDC decreased by amountIn
    assertEq(poolUsdcBefore - poolUsdcAfter, MINT_AMOUNT_IN);
    // GOOGLon increased by expected output
    assertEq(poolGooglonAfter - poolGooglonBefore, MINT_EXPECTED_OUTPUT);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OndoGMSwap — swapExactInWithAttestation (Redeem)
  // ═══════════════════════════════════════════════════════════════════════

  function test_redeem_swapExactInWithAttestation() public {
    // Give pool GOOGLon for redemption
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);

    uint256 poolGooglonBefore = IERC20(GOOGLON).balanceOf(address(testPool));
    uint256 poolUsdcBefore = IERC20(usdcData.asset).balanceOf(address(testPool));

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE));

    uint256 poolGooglonAfter = IERC20(GOOGLON).balanceOf(address(testPool));
    uint256 poolUsdcAfter = IERC20(usdcData.asset).balanceOf(address(testPool));

    // GOOGLon decreased by amountIn
    assertEq(poolGooglonBefore - poolGooglonAfter, REDEEM_AMOUNT_IN);
    // USDC increased by expected output
    assertEq(poolUsdcAfter - poolUsdcBefore, REDEEM_EXPECTED_OUTPUT);
  }

  function test_swapExactIn_usdcMaxApprovedAfterMint() public {
    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));

    // USDC approval to GMTokenManager should remain at max (set in constructor)
    uint256 allowance = IERC20(usdcData.asset).allowance(ondoGMSwap, GM_TOKEN_MANAGER);
    assertGt(allowance, 0);
  }

  function test_swapExactIn_ondoAssetApprovalResetAfterRedeem() public {
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE));

    // Ondo asset approval to GMTokenManager should be reset to 0
    uint256 allowance = IERC20(GOOGLON).allowance(ondoGMSwap, GM_TOKEN_MANAGER);
    assertEq(allowance, 0);
  }

  function test_swapExactIn_transfersOutputToVault() public {
    uint256 poolGooglonBefore = IERC20(GOOGLON).balanceOf(address(testPool));

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));

    uint256 poolGooglonAfter = IERC20(GOOGLON).balanceOf(address(testPool));
    assertEq(poolGooglonAfter - poolGooglonBefore, MINT_EXPECTED_OUTPUT);

    // OndoGMSwap should have no leftover tokens
    assertEq(IERC20(GOOGLON).balanceOf(ondoGMSwap), 0);
    assertEq(IERC20(usdcData.asset).balanceOf(ondoGMSwap), 0);
  }

  function test_revert_mint_excessiveAmountIn() public {
    IGMTokenManager.Quote memory quote = _getMintQuote();
    // impliedCost = quote.quantity * quote.price / 1e30 ≈ 5_852_936_789
    // amountIn with +2 USDC tolerance exceeds the allowed +1 USDC
    uint256 excessiveAmountIn = MINT_AMOUNT_IN + 2e6;

    vm.prank(manager);
    vm.expectRevert(
      abi.encodeWithSelector(
        bytes4(keccak256("ExcessiveAmountIn(uint256,uint256)")),
        excessiveAmountIn,
        (quote.quantity * quote.price) / 1e30
      )
    );
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(excessiveAmountIn, MINT_EXPECTED_OUTPUT, quote));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OndoGMSwap — rescueToken
  // ═══════════════════════════════════════════════════════════════════════

  function test_rescueToken() public {
    // Send some tokens to the swap contract (stuck tokens)
    deal(usdcData.asset, ondoGMSwap, 1000e6);

    address recipient = makeAddr("recipient");
    // OndoGMSwap owner is the test contract's `owner` address
    vm.prank(owner);
    (bool success, ) = ondoGMSwap.call(
      abi.encodeWithSignature("rescueToken(address,uint256,address)", usdcData.asset, 1000e6, recipient)
    );
    require(success, "rescueToken failed");

    assertEq(IERC20(usdcData.asset).balanceOf(recipient), 1000e6);
    assertEq(IERC20(usdcData.asset).balanceOf(ondoGMSwap), 0);
  }

  function test_revert_rescueToken_notOwner() public {
    vm.prank(manager);
    (bool success, ) = ondoGMSwap.call(
      abi.encodeWithSignature("rescueToken(address,uint256,address)", usdcData.asset, 1000e6, manager)
    );
    assertFalse(success);
  }

  function test_revert_rescueToken_zeroRecipient() public {
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("ZeroAddress(string)")), "recipient"));
    vm.prank(owner);
    (bool success, ) = ondoGMSwap.call(
      abi.encodeWithSignature("rescueToken(address,uint256,address)", usdcData.asset, 1000e6, address(0))
    );
    require(success);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OndoGMSwap — non-pool / non-vault callers are rejected
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_swap_unauthorizedCaller() public {
    address caller = makeAddr("anyCaller");

    deal(GOOGLON, caller, REDEEM_AMOUNT_IN);
    vm.prank(caller);
    IERC20(GOOGLON).approve(ondoGMSwap, type(uint256).max);

    vm.prank(caller);
    vm.expectRevert(abi.encodeWithSignature("UnauthorizedCaller(address)", caller));
    (bool ok, ) = ondoGMSwap.call(_encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE));
    ok; // silence unused
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OndoGMSwapContractGuard — Constructor
  // ═══════════════════════════════════════════════════════════════════════

  function test_guard_constructor_setsMaxSlippage() public view {
    assertEq(ondoGMSwapGuard.maxSlippagePerSwapBps(), MAX_SLIPPAGE_BPS);
  }

  function test_revert_guard_constructor_invalidSlippageBps() public {
    vm.expectRevert("invalid slippage bps");
    new OndoGMSwapContractGuard(address(slippageAccumulator), 10_001, IOndoAttestationOracle(address(0)));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OndoGMSwapContractGuard — txGuard (Ondo pause checks)
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_txGuard_mint_mintingPaused() public {
    _mockMintingPaused(GOOGLON, true);

    vm.prank(manager);
    vm.expectRevert("Ondo minting paused");
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));
  }

  function test_revert_txGuard_redeem_redemptionsPaused() public {
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);
    _mockRedemptionsPaused(GOOGLON, true);

    vm.prank(manager);
    vm.expectRevert("Ondo redemptions paused");
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE));
  }

  function test_txGuard_mint_succeedsWhenRedemptionsPaused() public {
    // Redemptions paused should NOT block minting
    _mockRedemptionsPaused(GOOGLON, true);
    _mockMintingPaused(GOOGLON, false);

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));

    assertGt(IERC20(GOOGLON).balanceOf(address(testPool)), 0);
  }

  function test_txGuard_redeem_succeedsWhenMintingPaused() public {
    // Minting paused should NOT block redemptions
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);
    _mockMintingPaused(GOOGLON, true);
    _mockRedemptionsPaused(GOOGLON, false);

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE));

    assertEq(IERC20(GOOGLON).balanceOf(address(testPool)), 0);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OndoGMSwapContractGuard — txGuard (Fail cases)
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_txGuard_unsupportedDestAsset() public {
    // Remove GOOGLon from supported assets
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory empty;
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = GOOGLON;
    fundManagerLogic.changeAssets(empty, removeAssets);

    vm.expectRevert("unsupported destination asset");
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));
    vm.stopPrank();
  }

  function test_revert_txGuard_nonZeroAdditionalData() public {
    IGMTokenManager.Quote memory quote = _getMintQuote();
    quote.additionalData = bytes32(uint256(1));

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidAdditionalData()"))));
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT, quote));
  }

  function test_revert_txGuard_wrongChainId() public {
    IGMTokenManager.Quote memory quote = _getMintQuote();
    quote.chainId = 42161; // Arbitrum chain ID

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidChainId()"))));
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT, quote));
  }

  function test_revert_txGuard_mint_assetMismatch() public {
    IGMTokenManager.Quote memory quote = _getMintQuote();
    quote.asset = usdcData.asset; // Should be GOOGLon (tokenOut) for mint

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AssetMismatch()"))));
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT, quote));
  }

  function test_revert_txGuard_redeem_assetMismatch() public {
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);

    IGMTokenManager.Quote memory quote = _getRedeemQuote();
    quote.asset = usdcData.asset; // Should be GOOGLon (tokenIn) for redeem

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AssetMismatch()"))));
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE, quote));
  }

  function test_revert_txGuard_redeem_quantityMismatch() public {
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);

    IGMTokenManager.Quote memory quote = _getRedeemQuote();
    quote.quantity = REDEEM_AMOUNT_IN + 1; // Mismatch with amountIn

    vm.prank(manager);
    vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AmountMismatch()"))));
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE, quote));
  }

  function test_revert_txGuard_slippageTooHigh() public {
    // Set amountOutMinimum very low so oracle value check fails
    // USDC in = ~$5852, if min output is 1 GOOGLon (~$300), that's ~95% slippage > 2% allowed
    vm.prank(manager);
    vm.expectRevert("slippage too high");
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, 1e18));
  }

  function test_revert_txGuard_slippageTooHigh_mint_lowOraclePrice() public {
    // GOOGLon oracle at $270 makes ~19.4 GOOGLon output worth ~$5250 vs ~$5852 USDC input (~10% slippage > 2%)
    address googlonAggregator = makeAddr("googlon_aggregator");
    vm.mockCall(
      googlonAggregator,
      abi.encodeWithSignature("latestRoundData()"),
      abi.encode(uint80(0), int256(270e8), uint256(0), block.timestamp, uint80(0))
    );

    vm.prank(manager);
    vm.expectRevert("slippage too high");
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));
  }

  function test_revert_txGuard_slippageTooHigh_redeem_highOraclePrice() public {
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);

    // GOOGLon oracle at $330 makes ~9.7 GOOGLon input worth ~$3209 vs ~$2921 USDC output (~9% slippage > 2%)
    address googlonAggregator = makeAddr("googlon_aggregator");
    vm.mockCall(
      googlonAggregator,
      abi.encodeWithSignature("latestRoundData()"),
      abi.encode(uint80(0), int256(330e8), uint256(0), block.timestamp, uint80(0))
    );

    vm.prank(manager);
    vm.expectRevert("slippage too high");
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE));
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OndoGMSwapContractGuard — afterTxGuard (Fail cases)
  // ═══════════════════════════════════════════════════════════════════════

  function test_revert_afterTxGuard_unsupportedSourceAsset() public {
    bytes memory data = _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE);

    // Remove GOOGLon (tokenIn for redeem) from supported assets
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory empty;
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = GOOGLON;
    fundManagerLogic.changeAssets(empty, removeAssets);
    vm.stopPrank();

    // afterTxGuard is called by pool logic
    vm.prank(address(testPool));
    vm.expectRevert("unsupported source asset");
    ondoGMSwapGuard.afterTxGuard(address(fundManagerLogic), ondoGMSwap, data);
  }

  function test_revert_afterTxGuard_unsupportedDestAsset() public {
    bytes memory data = _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT);

    // Remove GOOGLon (tokenOut for mint) from supported assets
    vm.startPrank(manager);
    IHasSupportedAsset.Asset[] memory empty;
    address[] memory removeAssets = new address[](1);
    removeAssets[0] = GOOGLON;
    fundManagerLogic.changeAssets(empty, removeAssets);
    vm.stopPrank();

    vm.prank(address(testPool));
    vm.expectRevert("unsupported destination asset");
    ondoGMSwapGuard.afterTxGuard(address(fundManagerLogic), ondoGMSwap, data);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Integration — Full flow through pool
  // ═══════════════════════════════════════════════════════════════════════

  function test_integration_mint_throughPool() public {
    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 poolUsdcBefore = IERC20(usdcData.asset).balanceOf(address(testPool));
    uint256 poolGooglonBefore = IERC20(GOOGLON).balanceOf(address(testPool));

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));

    uint256 valueAfter = fundManagerLogic.totalFundValue();

    // USDC decreased, GOOGLon increased
    assertEq(poolUsdcBefore - IERC20(usdcData.asset).balanceOf(address(testPool)), MINT_AMOUNT_IN);
    assertGt(IERC20(GOOGLON).balanceOf(address(testPool)), poolGooglonBefore);

    // Fund value should be approximately preserved (within 2% slippage)
    assertApproxEqRel(valueBefore, valueAfter, 0.02e18);
  }

  function test_integration_redeem_throughPool() public {
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);

    uint256 valueBefore = fundManagerLogic.totalFundValue();
    uint256 poolUsdcBefore = IERC20(usdcData.asset).balanceOf(address(testPool));
    uint256 poolGooglonBefore = IERC20(GOOGLON).balanceOf(address(testPool));

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE));

    uint256 valueAfter = fundManagerLogic.totalFundValue();

    // GOOGLon decreased, USDC increased
    assertEq(poolGooglonBefore - IERC20(GOOGLON).balanceOf(address(testPool)), REDEEM_AMOUNT_IN);
    assertGt(IERC20(usdcData.asset).balanceOf(address(testPool)), poolUsdcBefore);

    // Fund value should be approximately preserved (within 2% slippage)
    assertApproxEqRel(valueBefore, valueAfter, 0.02e18);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SlippageAccumulator — cumulative slippage tracking
  // ═══════════════════════════════════════════════════════════════════════

  function test_slippageAccumulator_accumulatesSlippage() public {
    address googlonAggregator = makeAddr("googlon_aggregator");

    // Mint at $297 oracle — GOOGLon output appears worth less than USDC input (~1.3% slippage, passes 2% check)
    vm.mockCall(
      googlonAggregator,
      abi.encodeWithSignature("latestRoundData()"),
      abi.encode(uint80(0), int256(297e8), uint256(0), block.timestamp, uint80(0))
    );

    (, uint128 slippageBefore) = slippageAccumulator.managerData(address(fundManagerLogic));
    assertEq(uint256(slippageBefore), 0);

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));

    (, uint128 slippageAfterMint) = slippageAccumulator.managerData(address(fundManagerLogic));
    assertGt(uint256(slippageAfterMint), 0, "slippage should accumulate after mint");

    // Redeem at $303 oracle — GOOGLon input appears worth more than USDC output (~0.9% slippage, passes 2% check)
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);

    vm.mockCall(
      googlonAggregator,
      abi.encodeWithSignature("latestRoundData()"),
      abi.encode(uint80(0), int256(303e8), uint256(0), block.timestamp, uint80(0))
    );

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE));

    (, uint128 slippageAfterRedeem) = slippageAccumulator.managerData(address(fundManagerLogic));
    assertGt(
      uint256(slippageAfterRedeem),
      uint256(slippageAfterMint),
      "slippage should accumulate further after redeem"
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // afterTxGuard — Opportunistic Oracle Update
  // ═══════════════════════════════════════════════════════════════════════

  /// @notice BUY swap succeeds even when oracle update fails (e.g., stale attestation, wrong config).
  function test_afterTxGuard_buy_swap_succeeds_when_oracle_update_fails() public {
    // Oracle will reject (real mainnet signatures won't pass oracle's signature verification)
    // but the swap itself should still succeed
    uint256 googlonBefore = IERC20(GOOGLON).balanceOf(address(testPool));

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));

    uint256 googlonAfter = IERC20(GOOGLON).balanceOf(address(testPool));
    assertGt(googlonAfter, googlonBefore, "pool should receive GOOGLon despite oracle update failure");
  }

  /// @notice SELL swap does not attempt oracle update (only BUY triggers it).
  function test_afterTxGuard_sell_swap_does_not_attempt_oracle_update() public {
    // Provide GOOGLon directly (skip BUY to isolate the SELL path)
    deal(GOOGLON, address(testPool), REDEEM_AMOUNT_IN);

    address googlonAggregator = makeAddr("googlon_aggregator");
    vm.mockCall(
      googlonAggregator,
      abi.encodeWithSignature("latestRoundData()"),
      abi.encode(uint80(0), int256(303e8), uint256(0), block.timestamp, uint80(0))
    );

    // Assert updatePrices is never called during the SELL swap
    vm.expectCall(attestationOracle, abi.encodeWithSelector(UPDATE_PRICES_SELECTOR), 0);

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeRedeemSwapData(REDEEM_AMOUNT_IN, REDEEM_MIN_RECEIVE));
  }

  /// @notice Guard with address(0) oracle still works correctly (feature disabled).
  function test_afterTxGuard_zero_address_oracle_skips_update() public {
    // Redeploy guard without oracle
    vm.startPrank(owner);
    OndoGMSwapContractGuard guardNoOracle = new OndoGMSwapContractGuard(
      address(slippageAccumulator),
      MAX_SLIPPAGE_BPS,
      IOndoAttestationOracle(address(0))
    );
    governance.setContractGuard(ondoGMSwap, address(guardNoOracle));
    vm.stopPrank();

    uint256 googlonBefore = IERC20(GOOGLON).balanceOf(address(testPool));

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));

    uint256 googlonAfter = IERC20(GOOGLON).balanceOf(address(testPool));
    assertGt(googlonAfter, googlonBefore, "swap should succeed with no oracle configured");
  }

  /// @notice Verify oracle update is actually attempted by mocking updatePrices to succeed.
  function test_afterTxGuard_buy_swap_attempts_oracle_update() public {
    // Mock updatePrices to succeed (accept any call)
    vm.mockCall(attestationOracle, abi.encodeWithSelector(UPDATE_PRICES_SELECTOR), abi.encode());

    // Expect exactly one call to updatePrices on the oracle
    vm.expectCall(attestationOracle, abi.encodeWithSelector(UPDATE_PRICES_SELECTOR), 1);

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));
  }

  /// @notice Slippage accumulation still works correctly alongside oracle update attempt.
  function test_afterTxGuard_slippage_accumulation_with_oracle_update() public {
    (, uint128 slippageBefore) = slippageAccumulator.managerData(address(fundManagerLogic));
    assertEq(uint256(slippageBefore), 0);

    vm.prank(manager);
    testPool.execTransaction(ondoGMSwap, _encodeMintSwapData(MINT_AMOUNT_IN, MINT_EXPECTED_OUTPUT));

    (, uint128 slippageAfter) = slippageAccumulator.managerData(address(fundManagerLogic));
    assertGt(uint256(slippageAfter), 0, "slippage should accumulate after mint with oracle update");
  }
}
