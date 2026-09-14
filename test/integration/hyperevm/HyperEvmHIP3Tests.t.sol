// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {HyperEVMSetup} from "../utils/foundry/chains/HyperEVMSetup.t.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {PrecompileHelper} from "contracts/utils/hyperliquid/PrecompileHelper.sol";
import {IHyperliquidCoreWriterContractGuard} from "contracts/interfaces/hyperliquid/IHyperliquidCoreWriterContractGuard.sol";
import {ICoreWriter} from "contracts/interfaces/hyperliquid/ICoreWriter.sol";
import {ICoreDepositWallet} from "contracts/interfaces/hyperliquid/ICoreDepositWallet.sol";
import {FixedPointMathLib} from "contracts/utils/FixedPointMathLib.sol";

/// @title HyperEVM HIP-3 Integration Tests
/// @notice Tests for HIP-3 dex ID approval and limit order functionality
contract HyperEvmHIP3Tests is HyperEVMSetup, PrecompileHelper {
  using FixedPointMathLib for uint256;

  // HIP-3 test constants
  uint256 public constant TEST_DEX_ID = 1; // xyz dex
  uint64 public constant HIP3_ASSET_ID = 110000; // xyz:XYZ100 asset ID
  uint64 public constant HIP3_ASSET_INDEX = 0; // Index within xyz dex

  /////////////////////////////////////////////
  //       HIP-3 Dex ID Approval Tests       //
  /////////////////////////////////////////////

  /// @notice Test that HIP-3 limit orders are rejected when dex ID is not approved
  function test_revert_hip3_order_when_dex_not_approved() public {
    // Setup: Approve the asset but not the dex ID
    vm.startPrank(owner);

    // First need to enable the dex temporarily to approve the asset
    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory tempDexSettings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    tempDexSettings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: TEST_DEX_ID,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.ENABLED
    });
    hyperliquidCoreWriterContractGuard.setDexIdStatus(tempDexSettings);

    // Approve the asset
    IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[]
      memory assetSettings = new IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[](1);
    assetSettings[0] = IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting({
      assetId: HIP3_ASSET_ID,
      approved: true
    });
    hyperliquidCoreWriterContractGuard.setApprovedAssets(assetSettings);

    // Now remove the dex ID
    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory settings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: TEST_DEX_ID,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.NO_OP
    });
    hyperliquidCoreWriterContractGuard.setDexIdStatus(settings);
    vm.stopPrank();

    // Verify dex ID is not enabled
    assertFalse(hyperliquidCoreWriterContractGuard.isEnabledDexId(TEST_DEX_ID), "Test dex ID should not be enabled");

    // Prepare a HIP-3 limit order
    vm.startPrank(manager);

    // Build the limit order action data
    bytes memory limitOrderAction = _buildHIP3LimitOrder({
      assetId: HIP3_ASSET_ID,
      isBuy: true,
      limitPx: 1000_0000_0000, // 1000 USD (8 decimals)
      sz: 1_0000_0000, // 1.0 size (8 decimals)
      reduceOnly: false
    });

    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, limitOrderAction);

    // Attempt to place the order - should revert
    vm.expectRevert("unsupported dex id");
    IPoolLogic(hyperliquidTestPool).execTransaction(coreWriter, txData);

    vm.stopPrank();
  }

  /// @notice Test that HIP-3 reduce-only limit orders are allowed even when the dex ID is disabled
  function test_hip3_reduce_only_order_allowed_when_dex_disabled() public {
    // Setup: Enable dex temporarily to approve the asset, then disable it
    vm.startPrank(owner);

    // Enable the dex ID first so the asset can be approved
    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory dexSettings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    dexSettings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: TEST_DEX_ID,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.ENABLED
    });
    hyperliquidCoreWriterContractGuard.setDexIdStatus(dexSettings);

    // Approve the HIP-3 asset while dex is enabled
    IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[]
      memory assetSettings = new IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[](1);
    assetSettings[0] = IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting({
      assetId: HIP3_ASSET_ID,
      approved: true
    });
    hyperliquidCoreWriterContractGuard.setApprovedAssets(assetSettings);

    // Now disable the dex ID
    dexSettings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: TEST_DEX_ID,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.DISABLED
    });
    hyperliquidCoreWriterContractGuard.setDexIdStatus(dexSettings);
    vm.stopPrank();

    // Verify dex ID is disabled
    assertFalse(hyperliquidCoreWriterContractGuard.isEnabledDexId(TEST_DEX_ID), "Test dex ID should be disabled");

    // Prepare a HIP-3 reduce-only limit order
    vm.startPrank(manager);

    bytes memory limitOrderAction = _buildHIP3LimitOrder({
      assetId: HIP3_ASSET_ID,
      isBuy: true,
      limitPx: 1000_0000_0000, // 1000 USD (8 decimals)
      sz: 1_0000_0000, // 1.0 size (8 decimals)
      reduceOnly: true
    });

    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, limitOrderAction);

    uint256 poolValueBefore = _getTotalFundValue();

    // Reduce-only orders are allowed even with a disabled dex to enable position closure
    IPoolLogic(hyperliquidTestPool).execTransaction(coreWriter, txData);

    vm.stopPrank();

    // Guard state must not have been mutated by the transaction
    assertFalse(
      hyperliquidCoreWriterContractGuard.isEnabledDexId(TEST_DEX_ID),
      "Dex should remain disabled after reduce-only order"
    );
    // No funds should have been drained
    assertEq(_getTotalFundValue(), poolValueBefore, "Pool value should be unchanged after reduce-only order");
  }

  /// @notice Test that HIP-3 non-reduce-only limit orders are also allowed when dex ID is approved
  function test_hip3_non_reduce_only_order_when_dex_approved() public {
    // Setup: Approve TEST_DEX_ID and the HIP-3 asset
    vm.startPrank(owner);

    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory dexSettings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    dexSettings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: TEST_DEX_ID,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.ENABLED
    });
    hyperliquidCoreWriterContractGuard.setDexIdStatus(dexSettings);

    IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[]
      memory assetSettings = new IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[](1);
    assetSettings[0] = IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting({
      assetId: HIP3_ASSET_ID,
      approved: true
    });
    hyperliquidCoreWriterContractGuard.setApprovedAssets(assetSettings);
    vm.stopPrank();

    // Place a non-reduce-only order
    vm.startPrank(manager);

    bytes memory limitOrderAction = _buildHIP3LimitOrder({
      assetId: HIP3_ASSET_ID,
      isBuy: true,
      limitPx: 1000_0000_0000,
      sz: 1_0000_0000,
      reduceOnly: false
    });

    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, limitOrderAction);

    uint256 poolValueBefore = _getTotalFundValue();

    // Non-reduce-only orders are allowed when the dex ID is enabled
    IPoolLogic(hyperliquidTestPool).execTransaction(coreWriter, txData);

    vm.stopPrank();

    // Guard state must not have been mutated by the transaction
    assertTrue(
      hyperliquidCoreWriterContractGuard.isEnabledDexId(TEST_DEX_ID),
      "Dex should remain enabled after placing order"
    );
    // No funds should have been drained
    assertEq(_getTotalFundValue(), poolValueBefore, "Pool value should be unchanged after placing order");
  }

  /// @notice A GTC perp buy priced aggressively through the book crosses immediately like an IOC,
  ///         so it must be bounded by the same oracle slippage check rather than bypassing it.
  function test_revert_hip3_gtc_buy_above_slippage_bound() public {
    // Setup: Approve TEST_DEX_ID and the HIP-3 asset
    vm.startPrank(owner);

    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory dexSettings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    dexSettings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: TEST_DEX_ID,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.ENABLED
    });
    hyperliquidCoreWriterContractGuard.setDexIdStatus(dexSettings);

    IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[]
      memory assetSettings = new IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[](1);
    assetSettings[0] = IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting({
      assetId: HIP3_ASSET_ID,
      approved: true
    });
    hyperliquidCoreWriterContractGuard.setApprovedAssets(assetSettings);
    vm.stopPrank();

    vm.startPrank(manager);

    // GTC (orderType 2) buy priced far above the oracle (~1000 USD, see the IOC tests above) so it
    // would cross the book at a huge premium. Previously GTC skipped the slippage check entirely.
    bytes memory limitOrderAction = _buildHIP3LimitOrder({
      assetId: HIP3_ASSET_ID,
      isBuy: true,
      limitPx: 100000_0000_0000, // 100,000 USD, far beyond oracle + slippage
      sz: 1_0000_0000,
      reduceOnly: false,
      orderType: 2 // GTC
    });

    bytes memory txData = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, limitOrderAction);

    vm.expectRevert("Slippage exceeds limit");
    IPoolLogic(hyperliquidTestPool).execTransaction(coreWriter, txData);

    vm.stopPrank();
  }

  /////////////////////////////////////////////
  //       Pool Valuation Tests              //
  /////////////////////////////////////////////

  /// @notice Test that pool value is unchanged when an empty HIP-3 dex ID is added
  function test_pool_value_unchanged_when_empty_dex_id_added() public {
    // Setup: Activate the pool account and bridge some USDC
    uint256 bridgeAmount = 10_000e6; // 10,000 USDC

    // Make a deposit first
    vm.startPrank(investor);
    IERC20(usdc).approve(hyperliquidTestPool, bridgeAmount);
    IPoolLogic(hyperliquidTestPool).deposit(usdc, bridgeAmount);
    vm.stopPrank();

    // Bridge USDC to core perp dex (dex ID 0)
    vm.startPrank(manager);
    bytes memory depositTxData = abi.encodeWithSelector(
      ICoreDepositWallet.deposit.selector,
      bridgeAmount,
      uint32(_DEX_ID_CORE_PERP)
    );
    IPoolLogic(hyperliquidTestPool).execTransaction(coreDepositWallet, depositTxData);
    vm.stopPrank();

    // Get initial pool value with only core dex
    uint256 poolValueBefore = _getTotalFundValue();

    // Now enable a HIP-3 dex (without actually having positions on it)
    vm.startPrank(owner);
    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory settings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: TEST_DEX_ID,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.ENABLED
    });
    hyperliquidCoreWriterContractGuard.setDexIdStatus(settings);
    vm.stopPrank();

    // Verify the dex ID is in the approved list
    uint256[] memory approvedDexIds = hyperliquidCoreWriterContractGuard.getApprovedDexIds();
    bool foundTestDex = false;
    for (uint256 i; i < approvedDexIds.length; ++i) {
      if (approvedDexIds[i] == TEST_DEX_ID) {
        foundTestDex = true;
        break;
      }
    }
    assertTrue(foundTestDex, "Test dex ID should be in approved list");

    // Get pool value after adding dex ID (should be same since no positions on new dex)
    uint256 poolValueAfter = _getTotalFundValue();

    // Pool value should remain the same (no positions on the new dex)
    assertEq(poolValueAfter, poolValueBefore, "Pool value should not change when adding empty dex ID");
  }

  /// @notice Test that core dex IDs cannot be removed
  function test_revert_cannot_remove_core_dex_ids() public {
    vm.startPrank(owner);

    // Attempt to remove core perp dex (ID 0)
    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory settings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    settings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: _DEX_ID_CORE_PERP,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.NO_OP
    });

    vm.expectRevert("cannot modify core dex IDs");
    hyperliquidCoreWriterContractGuard.setDexIdStatus(settings);

    // Attempt to remove core spot dex (ID max uint32)
    settings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: _DEX_ID_CORE_SPOT,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.NO_OP
    });

    vm.expectRevert("cannot modify core dex IDs");
    hyperliquidCoreWriterContractGuard.setDexIdStatus(settings);

    vm.stopPrank();
  }

  /// @notice Test that approving HIP-3 asset requires dex ID to be approved first
  function test_revert_approve_hip3_asset_without_dex_approval() public {
    // Ensure TEST_DEX_ID is not approved
    vm.startPrank(owner);

    IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[]
      memory dexSettings = new IHyperliquidCoreWriterContractGuard.DexIdStatusSettings[](1);
    dexSettings[0] = IHyperliquidCoreWriterContractGuard.DexIdStatusSettings({
      dexId: TEST_DEX_ID,
      status: IHyperliquidCoreWriterContractGuard.DexStatus.NO_OP
    });
    hyperliquidCoreWriterContractGuard.setDexIdStatus(dexSettings);

    // Attempt to approve HIP-3 asset without dex approval
    IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[]
      memory assetSettings = new IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting[](1);
    assetSettings[0] = IHyperliquidCoreWriterContractGuard.ApprovedAssetSetting({
      assetId: HIP3_ASSET_ID,
      approved: true
    });

    vm.expectRevert("unapproved dex id");
    hyperliquidCoreWriterContractGuard.setApprovedAssets(assetSettings);

    vm.stopPrank();
  }

  /////////////////////////////////////////////
  //         Helper Functions                //
  /////////////////////////////////////////////

  /// @notice Helper to build a HIP-3 limit order action (IOC by default)
  function _buildHIP3LimitOrder(
    uint64 assetId,
    bool isBuy,
    uint64 limitPx,
    uint64 sz,
    bool reduceOnly
  ) internal pure returns (bytes memory) {
    return _buildHIP3LimitOrder(assetId, isBuy, limitPx, sz, reduceOnly, 3); // orderType: GTC = 2, IOC = 3
  }

  /// @notice Helper to build a HIP-3 limit order action with an explicit time-in-force
  function _buildHIP3LimitOrder(
    uint64 assetId,
    bool isBuy,
    uint64 limitPx,
    uint64 sz,
    bool reduceOnly,
    uint8 orderType
  ) internal pure returns (bytes memory) {
    // Action ID 1 = Limit order
    // Version 1
    bytes memory action = new bytes(1 + 3); // 1 byte version + 3 bytes action ID
    action[0] = 0x01; // Version
    action[1] = 0x00; // Action ID byte 1
    action[2] = 0x00; // Action ID byte 2
    action[3] = 0x01; // Action ID byte 3 (action ID = 1)

    // Encode limit order parameters
    bytes memory params = abi.encode(
      assetId, // asset (uint64)
      isBuy, // isBuy (bool)
      limitPx, // limitPx (uint64)
      sz, // sz (uint64)
      reduceOnly, // reduceOnly (bool)
      orderType, // orderType: GTC = 2, IOC = 3
      address(0) // builder (address) - null for no builder fee
    );

    return bytes.concat(action, params);
  }
}
