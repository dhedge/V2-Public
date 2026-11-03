// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {HyperEVMSetup} from "../utils/foundry/chains/HyperEVMSetup.t.sol";
import {CoreSimulatorLib} from "./test-suite/hyperevm-lib/CoreSimulatorLib.sol";
import {HLConstants} from "test/integration/hyperevm/test-suite/hyperevm-lib/lib/HLConstants.sol";
import {PrecompileLib} from "test/integration/hyperevm/test-suite/hyperevm-lib/lib/PrecompileLib.sol";
import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";
import {IHyperliquidCoreWriterContractGuard} from "contracts/interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";
import {ISlippageAccumulator} from "contracts/interfaces/ISlippageAccumulator.sol";

/// @notice Every limit order is charged its worst-case concession, size times the distance of its limit from the
///         guard's reference price, to the shared slippage budget (10% of vault value per 24 hours).
contract HyperEvmSlippageBudgetTests is HyperEVMSetup {
  struct TxToExecute {
    address to;
    bytes data;
  }

  uint32 internal constant BTC_PERP = 0;
  uint32 internal constant XAUT0_ASSET_ID = 10000 + uint32(HyperEVMConfig.XAUT0_SPOT_INDEX);
  uint64 internal constant XAUT0_PX = 2800e6; // spot px has (8 - szDecimals=2) = 6 decimals
  uint256 internal constant ONE_PERCENT = 1e4; // accumulator scale: 1e6 = 100%

  ISlippageAccumulator internal accumulator;
  uint256 internal btcRef; // the guard's reference price, 8 decimals

  function setUp() public override {
    super.setUp();

    accumulator = ISlippageAccumulator(slippageAccumulator);

    IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[]
      memory settings = new IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting({assetId: BTC_PERP, approved: true});
    vm.prank(owner);
    hyperliquidCoreWriterContractGuard.setApprovedAssets(settings);

    // Pin the oracle the guard reads (precompile 0x807) so the reference is the same for every order in a test.
    vm.mockCall(
      address(0x0000000000000000000000000000000000000807),
      abi.encode(BTC_PERP),
      abi.encode(PrecompileLib.oraclePx(BTC_PERP))
    );
    btcRef = PrecompileLib.normalizedOraclePx(BTC_PERP) * 1e2;

    // The guard measures a perp order against the worse of oracle and mark; hold the mark at the oracle so the
    // reference is `btcRef` unless a test moves it.
    hyperCore.setMarkPx(BTC_PERP, PrecompileLib.oraclePx(BTC_PERP));

    hyperCore.setSpotPx(uint32(HyperEVMConfig.XAUT0_SPOT_INDEX), XAUT0_PX);
  }

  /////////////////////////////////////////////
  //                 Helpers                 //
  /////////////////////////////////////////////

  function _order(uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, uint8 tif) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        uint8(1),
        HLConstants.LIMIT_ORDER_ACTION,
        abi.encode(asset, isBuy, limitPx, sz, false, tif, uint128(0))
      );
  }

  /// @dev The charge the accumulator records for `sz` units at `limitPx` against `ref`, in its 1e6 = 100% scale.
  function _expectedCharge(uint256 ref, uint64 limitPx, uint64 sz) internal view returns (uint256) {
    uint256 diff = limitPx > ref ? limitPx - ref : ref - limitPx;

    return (diff * sz * 1e2 * 1e6) / _getTotalFundValue();
  }

  function _cumulative() internal view returns (uint256) {
    return accumulator.getCumulativeSlippageImpact(hyperliquidTestPoolManagerLogic);
  }

  /////////////////////////////////////////////
  //                  Tests                  //
  /////////////////////////////////////////////

  /// @notice One IOC buy 1.9% above the oracle for 1 BTC concedes about $1,600 against a $10,000 vault, over the
  ///         10% budget on its own. The guard's 2% band would have let it through.
  function test_revert_single_order_concession_over_budget() public {
    uint64 limitPx = uint64(btcRef + (btcRef * 19) / 1000);
    assertGt(_expectedCharge(btcRef, limitPx, 1e8), 10 * ONE_PERCENT, "setup: over budget");

    vm.expectRevert("slippage impact exceeded");
    _placeLimitOrder(_order(BTC_PERP, true, limitPx, 1e8, HLConstants.LIMIT_ORDER_TIF_IOC));

    assertEq(_cumulative(), 0, "nothing recorded on revert");
  }

  /// @notice Orders inside the band add up: two 4.8% concessions pass, the third tips over 10%, and the budget
  ///         is back after the 24 hour decay.
  function test_concessions_accumulate_across_orders_and_decay() public {
    uint64 limitPx = uint64(btcRef + (btcRef * 19) / 1000);
    uint64 sz = 0.3e8;
    bytes memory order = _order(BTC_PERP, true, limitPx, sz, HLConstants.LIMIT_ORDER_TIF_IOC);

    uint256 first = _expectedCharge(btcRef, limitPx, sz);
    assertGt(first, 4 * ONE_PERCENT, "setup: each order is about 4.8%");
    assertLt(first, 5 * ONE_PERCENT, "setup: each order is about 4.8%");
    _placeLimitOrder(order);
    assertEq(_cumulative(), first, "first order recorded");

    uint256 second = _expectedCharge(btcRef, limitPx, sz);
    _placeLimitOrder(order);
    assertEq(_cumulative(), first + second, "second order added");

    vm.expectRevert("slippage impact exceeded");
    _placeLimitOrder(order);

    skip(1 days);
    assertEq(_cumulative(), 0, "fully decayed");

    uint256 third = _expectedCharge(btcRef, limitPx, sz);
    _placeLimitOrder(order);
    assertEq(_cumulative(), third, "budget available again");
  }

  /// @notice An IOC sell 1.9% under the reference is charged the same way as a buy above it.
  function test_sell_order_concession_is_charged() public {
    uint64 limitPx = uint64(btcRef - (btcRef * 19) / 1000);
    uint64 sz = 0.3e8;

    uint256 expected = _expectedCharge(btcRef, limitPx, sz);
    assertGt(expected, 4 * ONE_PERCENT, "setup: about 4.8%");
    _placeLimitOrder(_order(BTC_PERP, false, limitPx, sz, HLConstants.LIMIT_ORDER_TIF_IOC));
    assertEq(_cumulative(), expected, "sell concession recorded");
  }

  /// @notice With the mark 1% under the oracle a buy is measured against the mark: an order at the oracle, free
  ///         when the two agree, pays the 1% distance, and the band moves down with it. A sell is still measured
  ///         against the oracle, the higher of the two.
  function test_perp_buy_reference_is_the_lower_of_oracle_and_mark() public {
    hyperCore.setMarkPx(BTC_PERP, (PrecompileLib.oraclePx(BTC_PERP) * 99) / 100);
    uint256 markRef = PrecompileLib.normalizedMarkPx(BTC_PERP) * 1e2;
    uint64 sz = 0.3e8;

    uint256 expected = _expectedCharge(markRef, uint64(btcRef), sz);
    assertGt(expected, 0, "setup: oracle is above the mark");
    _placeLimitOrder(_order(BTC_PERP, true, uint64(btcRef), sz, HLConstants.LIMIT_ORDER_TIF_IOC));
    assertEq(_cumulative(), expected, "buy at the oracle pays the distance to the mark");

    // The 2% band now sits on the mark: 1.5% over the oracle is about 2.5% over the mark.
    vm.expectRevert("Slippage exceeds limit");
    _placeLimitOrder(
      _order(BTC_PERP, true, uint64(btcRef + (btcRef * 15) / 1000), sz, HLConstants.LIMIT_ORDER_TIF_IOC)
    );

    uint256 recorded = _cumulative();
    _placeLimitOrder(_order(BTC_PERP, false, uint64(btcRef), 100e8, HLConstants.LIMIT_ORDER_TIF_IOC));
    assertEq(_cumulative(), recorded, "sell at the oracle is free");
  }

  /// @notice With the mark 1% over the oracle a sell at the oracle pays the distance to the mark, the sell band
  ///         moves up with it, and a buy at the oracle is free.
  function test_perp_sell_reference_is_the_higher_of_oracle_and_mark() public {
    hyperCore.setMarkPx(BTC_PERP, (PrecompileLib.oraclePx(BTC_PERP) * 101) / 100);
    uint256 markRef = PrecompileLib.normalizedMarkPx(BTC_PERP) * 1e2;
    uint64 sz = 0.3e8;

    uint256 expected = _expectedCharge(markRef, uint64(btcRef), sz);
    assertGt(expected, 0, "setup: mark is above the oracle");
    _placeLimitOrder(_order(BTC_PERP, false, uint64(btcRef), sz, HLConstants.LIMIT_ORDER_TIF_IOC));
    assertEq(_cumulative(), expected, "sell at the oracle pays the distance to the mark");

    vm.expectRevert("Slippage exceeds limit");
    _placeLimitOrder(
      _order(BTC_PERP, false, uint64(btcRef - (btcRef * 15) / 1000), sz, HLConstants.LIMIT_ORDER_TIF_IOC)
    );

    uint256 recorded = _cumulative();
    _placeLimitOrder(_order(BTC_PERP, true, uint64(btcRef), 100e8, HLConstants.LIMIT_ORDER_TIF_IOC));
    assertEq(_cumulative(), recorded, "buy at the oracle is free");
  }

  /// @notice A resting sell above the oracle and a buy priced exactly at it concede nothing, whatever the size.
  function test_orders_at_or_past_the_reference_are_free() public {
    _placeLimitOrder(_order(BTC_PERP, false, uint64(btcRef + btcRef / 100), 100e8, HLConstants.LIMIT_ORDER_TIF_GTC));
    assertEq(_cumulative(), 0, "resting take-profit is free");

    _placeLimitOrder(_order(BTC_PERP, true, uint64(btcRef), 100e8, HLConstants.LIMIT_ORDER_TIF_IOC));
    assertEq(_cumulative(), 0, "order at the reference is free");
  }

  /// @notice Spot orders are charged against the spot mark the same way.
  function test_spot_order_concession_is_charged() public {
    _bridgeUSDCToCore(5_000e6, HLConstants.SPOT_DEX);
    CoreSimulatorLib.nextBlock();

    uint64 ref = XAUT0_PX * 100;
    uint64 limitPx = ref + (ref * 19) / 1000;

    // 20 XAUT0 at 1.9% over the mark concede about $1,064, over the budget.
    vm.expectRevert("slippage impact exceeded");
    _placeLimitOrder(_order(XAUT0_ASSET_ID, true, limitPx, 20e8, HLConstants.LIMIT_ORDER_TIF_IOC));

    // 10 XAUT0 concede about $532, 5.3%, and are recorded.
    uint256 expected = _expectedCharge(ref, limitPx, 10e8);
    _placeLimitOrder(_order(XAUT0_ASSET_ID, true, limitPx, 10e8, HLConstants.LIMIT_ORDER_TIF_IOC));
    assertEq(_cumulative(), expected, "spot concession recorded");
  }

  /// @notice 20 BTC round trips at the band edge in one transaction, 1,000 BTC each, revert: the first order
  ///         already concedes more than the whole budget.
  function test_revert_batched_band_edge_round_trips() public {
    uint256 slip = (btcRef * 19) / 1000;
    uint64 buyPx = uint64(btcRef + slip);
    uint64 sellPx = uint64(btcRef - slip);
    uint64 sz = 1_000e8;

    uint256 roundTrips = 20;
    TxToExecute[] memory txs = new TxToExecute[](roundTrips * 2);
    for (uint256 i; i < roundTrips; ++i) {
      txs[2 * i] = TxToExecute(
        coreWriter,
        abi.encodeWithSignature(
          "sendRawAction(bytes)",
          _order(BTC_PERP, true, buyPx, sz, HLConstants.LIMIT_ORDER_TIF_IOC)
        )
      );
      txs[2 * i + 1] = TxToExecute(
        coreWriter,
        abi.encodeWithSignature(
          "sendRawAction(bytes)",
          _order(BTC_PERP, false, sellPx, sz, HLConstants.LIMIT_ORDER_TIF_IOC)
        )
      );
    }

    vm.prank(manager);
    (bool ok, bytes memory err) = hyperliquidTestPool.call(
      abi.encodeWithSignature("execTransactions((address,bytes)[])", txs)
    );

    assertFalse(ok, "batch rejected");
    assertEq(err, abi.encodeWithSignature("Error(string)", "slippage impact exceeded"));
  }
}
