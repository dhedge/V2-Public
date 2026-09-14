// SPDX-License-Identifier: MIT
// solhint-disable no-unused-vars

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {DytmDelegationCallTestSetup} from "./DytmDelegationCallTestSetup.t.sol";
import {DytmWithdrawLib} from "contracts/swappers/easySwapperV2/libraries/dytm/DytmWithdrawLib.sol";
import {DytmParamStructs} from "contracts/utils/dytm/DytmParamStructs.sol";
import {IWithdrawalVault} from "contracts/swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";
import {IDytmOffice} from "contracts/interfaces/dytm/IDytmOffice.sol";
import {IDytmPeriphery} from "contracts/interfaces/dytm/IDytmPeriphery.sol";
import {IDytmDelegatee} from "contracts/interfaces/dytm/IDytmDelegatee.sol";
import {IDytmWithdrawProcessor} from "contracts/interfaces/dytm/IDytmWithdrawProcessor.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {Governance} from "contracts/Governance.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";
import {PendlePTAssetGuard} from "contracts/guards/assetGuards/pendle/PendlePTAssetGuard.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {MockPendlePTChainlinkOracle} from "./MockPendlePTChainlinkOracle.sol";
import {OdosAPIHelper} from "../odos/OdosAPIHelper.sol";
import {IPActionMarketCoreStatic} from "contracts/interfaces/pendle/IPActionMarketCoreStatic.sol";
import {IPActionMiscV3} from "contracts/interfaces/pendle/IPActionMiscV3.sol";
import {createTokenOutputSimple, createEmptyLimitOrderData} from "contracts/interfaces/pendle/IPAllActionTypeV3.sol";
import {IHasAssetInfo} from "contracts/interfaces/IHasAssetInfo.sol";
import {IDytmWeights} from "./dytmInterface/IDytmWeights.sol";
import {IMarketConfig} from "./dytmInterface/IDytmMarketConfig.sol";

abstract contract DytmEasySwapperV2WithdrawalTestSetup is DytmDelegationCallTestSetup {
  address public constant PENDLE_ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;
  uint16 internal constant ASSET_TYPE_PENDLE_PT = 37;

  address public investorVault;

  function setUp() public virtual override {
    super.setUp();

    // Predict investor's withdrawal vault address (vault is the unwind executor in the new design)
    _computeInvestorWithdrawalVault();
  }

  // ========== Setup Helpers ==========

  function _computeInvestorWithdrawalVault() internal {
    address existingVault = easySwapperV2Instance.withdrawalContracts(investor);
    if (existingVault != address(0)) {
      investorVault = existingVault;
    } else {
      uint64 nonce = vm.getNonce(address(easySwapperV2Instance));
      investorVault = vm.computeCreateAddress(address(easySwapperV2Instance), nonce);
    }
  }

  // ========== Tests: Withdrawal with DYTM Position - No Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_no_debt() public {
    // Supply collateral to DYTM (no borrowing)
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    _supplyForEscrow({asset: collateralAsset, amountToSupply: initialCollateral});

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify pool has DYTM position
    uint256 collateralValueBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Pool should have collateral in DYTM");
      assertEq(pos.debt.debtAssets, 0, "Pool should have no debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
    }

    // Get investor's pool token balance and compute withdrawal amount
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    assertGt(investorPoolTokensBefore, 0, "Investor should have pool tokens");
    uint256 withdrawAmount = investorPoolTokensBefore / 2;

    // Build complexAssetsData for no-debt withdrawal
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmComplexAssetsData(withdrawAmount);

    // Capture token price before withdrawal (burning tokens can change it)
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    // Investor approves and initiates withdrawal
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault was created correctly
    assertEq(vault, investorVault, "Vault address should match prediction");

    // Verify tracked assets have balances
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify withdrawn value matches pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.01e18, // 1% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal (recover assets without swapping)
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor has fewer pool tokens
    assertLt(dytmTestPool.balanceOf(investor), investorPoolTokensBefore, "Investor should have fewer pool tokens");

    // Verify pool's DYTM position was reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
    }

    // Verify total value is preserved within tolerance
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.01e18, // 1% tolerance for fees and slippage
      "Remaining pool value should be approximately half"
    );
  }

  /// @dev An unhealthy-but-solvent market can't be split, so its equity would be silently forfeited
  ///      on withdrawal. The position's equity is far above MAX_FORFEIT_VALUE_USD, so the bound reverts.
  function test_revert_easyswapper_v2_withdrawal_dytm_unhealthy_position() public {
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    _supplyForEscrow({asset: collateralAsset, amountToSupply: initialCollateral});

    uint256 withdrawAmount = dytmTestPool.balanceOf(investor) / 2;
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmComplexAssetsData(withdrawAmount);

    // Force the position unhealthy while keeping collateral > debt (solvent).
    uint256 account = uint256(uint160(address(dytmTestPool)));
    DytmParamStructs.AccountPosition memory position = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      account,
      marketId
    );
    position.isHealthy = false;
    position.healthFactor = 0.9e18;
    vm.mockCall(
      dytmPeriphery,
      abi.encodeWithSelector(IDytmPeriphery.getAccountPosition.selector, account, marketId),
      abi.encode(position)
    );

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);
    vm.expectRevert("unhealthy position too large");
    easySwapperV2Instance.initWithdrawal(address(dytmTestPool), withdrawAmount, complexAssetsData);
    vm.stopPrank();
  }

  // ========== Tests: bounded dust remnant returned to the pool ==========

  /// @dev When a split account can't be fully drained (e.g. GM leg below Ondo's $1 attestation
  ///      minimum), the processor hands the bounded dust back to the pool.
  function test_easyswapper_v2_withdrawal_dytm_dustRemnant_returnedToPool() public {
    _dealAndSupplyUsdcEscrow(600e6);

    uint256 withdrawAmount = dytmTestPool.balanceOf(investor);
    uint256 investorUsdcBefore = IERC20Extended(borrowAsset).balanceOf(investor);
    uint256 investorPtUnderlyingBefore = IERC20Extended(pendlePTUnderlying).balanceOf(investor);
    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Snapshot pre-drain (assets, valueUSD) so the remnant assertion below can verify Dytm's
    // value-per-asset ratio is preserved post-drain.
    (uint256 usdcAssetsBefore, uint256 usdcValueUsdBefore) = _findUsdcCollateral(
      IDytmPeriphery(dytmPeriphery).getAccountPosition(uint256(uint160(address(dytmTestPool))), marketId)
    );

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildPlanLeavingUsdcRemnant(withdrawAmount, 2e6);

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);
    easySwapperV2Instance.initWithdrawal(address(dytmTestPool), withdrawAmount, complexAssetsData);
    vm.stopPrank();

    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Investor gets full pool value (USDC + wstETH from PT unroll) minus the $2 remnant;
    // 1% tolerance covers Odos slippage on the redemption leg.
    uint256 usdcReceived = IERC20Extended(borrowAsset).balanceOf(investor) - investorUsdcBefore;
    uint256 ptUnderlyingReceived = IERC20Extended(pendlePTUnderlying).balanceOf(investor) - investorPtUnderlyingBefore;
    uint256 totalUsdValueReceived = dytmTestPoolManagerLogic.assetValue(borrowAsset, usdcReceived) +
      dytmTestPoolManagerLogic.assetValue(pendlePTUnderlying, ptUnderlyingReceived);
    assertApproxEqRel(
      totalUsdValueReceived,
      totalValueBefore - 2e18,
      0.01e18,
      "investor should receive pool value minus dust remnant"
    );

    // The orphan split-account ERC-1155 must be owned by the pool, not stuck in the shared processor.
    uint256 splitAccountId = dytmOfficeAssetGuard.getSplitPositions(investorVault)[0].tokenId;
    (bool ok, bytes memory ret) = dytmOffice.staticcall(
      abi.encodeWithSignature("balanceOf(address,uint256)", address(dytmTestPool), splitAccountId)
    );
    assertTrue(ok && abi.decode(ret, (uint256)) == 1, "remnant should be owned by the pool");

    DytmParamStructs.AccountPosition memory remnant = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      splitAccountId,
      marketId
    );
    (uint256 usdcAssetsRemnant, uint256 usdcValueUsdRemnant) = _findUsdcCollateral(remnant);
    // Same asset/oracle ⇒ value-per-asset ratio preserved; cross-multiplied to avoid lossy division.
    assertEq(
      usdcValueUsdRemnant * usdcAssetsBefore,
      usdcValueUsdBefore * usdcAssetsRemnant,
      "remnant value-per-asset should match pre-drain ratio"
    );
    assertEq(remnant.totalCollateralValueUSD, usdcValueUsdRemnant, "totalCollateralValueUSD should sum collaterals");
  }

  /// @dev Plans leaving more than `MAX_REMNANT_VALUE_USD` ($3) of dust are rejected — can't
  ///      lazily orphan meaningful value into an untracked isolated account.
  function test_revert_easyswapper_v2_withdrawal_dytm_remnantTooLarge() public {
    _dealAndSupplyUsdcEscrow(600e6);

    uint256 withdrawAmount = dytmTestPool.balanceOf(investor) / 2;
    // ~$10 of dust — over the $3 cap.
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildPlanLeavingUsdcRemnant(withdrawAmount, 10e6);

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);
    vm.expectRevert("remnant too large");
    easySwapperV2Instance.initWithdrawal(address(dytmTestPool), withdrawAmount, complexAssetsData);
    vm.stopPrank();
  }

  // ========== Tests: Withdrawal with swapToAsset Collateral - No Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_swapToAsset_no_debt() public {
    // Supply swapToAsset (WETH) as escrow collateral, no borrowing
    uint256 wethAmount = 1e16; // 0.01 WETH
    deal(swapToAsset, address(dytmTestPool), wethAmount);

    // Supply WETH to DYTM via delegationCall (1 tx, no borrow)
    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](1);
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(swapToAsset),
          assets: wethAmount,
          extraData: ""
        })
      )
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(txs)
        })
      )
    );

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position: collateral > 0, no debt
    uint256 collateralValueBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Pool should have collateral in DYTM");
      assertEq(pos.debt.debtAssets, 0, "Pool should have no debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
    }

    // Investor withdraws 50%
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokensBefore / 2;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmComplexAssetsData(withdrawAmount);

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault and tracked assets
    assertEq(vault, investorVault, "Vault address should match prediction");
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify tracked assets value matches withdrawn pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.01e18, // 1% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal and verify investor received tokens
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor received withdrawn assets
    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        assertGt(
          IERC20Extended(trackedAssets[i].token).balanceOf(investor),
          0,
          "Investor should have received withdrawn tokens"
        );
      }
    }

    // Verify pool collateral reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
    }

    // Verify remaining pool value is approximately half
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.01e18, // 1% tolerance
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Tests: Withdrawal with DYTM Position - With Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_with_debt() public {
    // Step 1: Create a DYTM position with WETH collateral and USDC debt
    uint256 wethAmount = 1e16; // 0.01 WETH
    deal(swapToAsset, address(dytmTestPool), wethAmount);

    // Supply WETH as escrow collateral and borrow USDC via delegationCall
    uint256 borrowAmount = 5 * (10 ** IERC20Extended(borrowAsset).decimals()); // 5 USDC

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);

    // Supply WETH to DYTM
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(swapToAsset),
          assets: wethAmount,
          extraData: ""
        })
      )
    });

    // Borrow USDC
    txs[1] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: borrowAmount,
          extraData: ""
        })
      )
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(txs)
        })
      )
    );

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position has collateral and debt
    uint256 collateralValueBefore;
    uint256 debtAssetsBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Should have collateral");
      assertGt(pos.debt.debtAssets, 0, "Should have debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
      debtAssetsBefore = pos.debt.debtAssets;
    }

    // Step 2: Investor withdraws half
    uint256 withdrawAmount = dytmTestPool.balanceOf(investor) / 2;

    // Build complexAssetsData with swap data for WETH -> USDC (to repay debt)
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmComplexAssetsData(withdrawAmount);

    // Investor approves and initiates withdrawal
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault
    assertEq(vault, investorVault, "Vault address should match");
    assertGt(trackedAssets.length, 0, "Should have tracked assets");

    // Complete withdrawal
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify pool position is reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
      assertLt(posAfter.debt.debtAssets, debtAssetsBefore, "Pool debt should be reduced");
    }

    // Verify total value is approximately halved
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.05e18, // 5% tolerance
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Tests: Withdrawal with collateralAsset Collateral + Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_collateral_with_debt() public {
    // Supply collateralAsset as escrow + borrow borrowAsset via delegationCall
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    uint256 borrowAmount = borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals());

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);

    // Supply collateralAsset to DYTM as escrow
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          assets: initialCollateral,
          extraData: ""
        })
      )
    });

    // Borrow borrowAsset
    txs[1] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: borrowAmount,
          extraData: ""
        })
      )
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(txs)
        })
      )
    );

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position has collateral and debt
    uint256 collateralValueBefore;
    uint256 debtAssetsBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Should have collateral");
      assertGt(pos.debt.debtAssets, 0, "Should have debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
      debtAssetsBefore = pos.debt.debtAssets;
    }

    // Investor withdraws 50%
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokensBefore / 2;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmComplexAssetsData(withdrawAmount);

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault and tracked assets
    assertEq(vault, investorVault, "Vault address should match");
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify tracked assets value matches withdrawn pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.01e18, // 1% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal and verify investor received tokens
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor received withdrawn assets
    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        assertGt(
          IERC20Extended(trackedAssets[i].token).balanceOf(investor),
          0,
          "Investor should have received withdrawn tokens"
        );
      }
    }

    // Verify pool position is reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
      assertLt(posAfter.debt.debtAssets, debtAssetsBefore, "Pool debt should be reduced");
    }

    // Verify remaining pool value is approximately half
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.01e18, // 1% tolerance
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Tests: Edge Cases ==========

  function test_withdrawal_without_dytm_position_skips_processing() public {
    // Don't supply anything to DYTM - pool has no DYTM position
    uint256 investorPoolTokens = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokens / 2;

    // Build complexAssetsData without withdraw data for DYTM office
    IHasSupportedAsset.Asset[] memory supportedAssets = dytmTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](supportedAssets.length);

    for (uint256 i = 0; i < supportedAssets.length; i++) {
      complexAssetsData[i] = IPoolLogic.ComplexAsset({
        supportedAsset: supportedAssets[i].asset,
        withdrawData: new bytes(0),
        slippageTolerance: 100
      });
    }

    // Should not revert - DYTM processing is skipped when no positions exist
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    easySwapperV2Instance.initWithdrawal(address(dytmTestPool), withdrawAmount, complexAssetsData);
    vm.stopPrank();

    // Complete withdrawal to verify assets flow correctly
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();
  }

  // ========== Tests: Full Leverage Up + Withdrawal ==========

  function test_easyswapper_v2_withdrawal_after_leverage_up() public {
    // Leverage up (creates DYTM position with pool token collateral + USDC debt)
    _leverage_up();

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position has collateral and debt
    uint256 collateralValueBefore;
    uint256 debtAssetsBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Should have collateral");
      assertGt(pos.debt.debtAssets, 0, "Should have debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
      debtAssetsBefore = pos.debt.debtAssets;
    }

    // Investor withdraws a quarter (to reduce impact)
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokensBefore / 4;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    // Build a multi-step unwind plan that redeems the dHedge-pool-token collateral down to
    // USDC to fund the repay. The leverage shape is: collateral = dHedge pool token (no DEX
    // liquidity), debt = USDC. Plan:
    //   1. dytmOffice.withdraw         — vault receives collateral-pool tokens
    //   2. collateralPool.withdraw     — redeem pool tokens → proportional USDC + WETH
    //   3-4. WETH → USDC via Odos      — flatten the WETH leg
    //   5-6. approve + dytmOffice.repay — clear the debt
    // Output asset is USDC; any post-repay USDC is the user's payout.
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildLeverageUpUnwindComplexAssetsData(withdrawAmount);

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault and tracked assets
    assertEq(vault, investorVault, "Vault address should match");
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify tracked assets value matches withdrawn pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.01e18, // 1% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal and verify investor received tokens
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        assertGt(
          IERC20Extended(trackedAssets[i].token).balanceOf(investor),
          0,
          "Investor should have received withdrawn tokens"
        );
      }
    }

    // Verify pool position is reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
      assertLt(posAfter.debt.debtAssets, debtAssetsBefore, "Pool debt should be reduced");
    }

    // Verify remaining pool value is approximately 3/4 of original
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      (totalValueBefore * 3) / 4,
      0.01e18, // 1% tolerance
      "Remaining pool value should be approximately 3/4"
    );
  }

  // ========== Tests: Withdrawal with PT-Holding Collateral Vault - No Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_collateral_pt_no_debt() public {
    _setupPTInCollateralVault();

    // Supply collateral to DYTM (no borrowing)
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    _supplyForEscrow({asset: collateralAsset, amountToSupply: initialCollateral});

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify pool has DYTM position
    uint256 collateralValueBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Pool should have collateral in DYTM");
      assertEq(pos.debt.debtAssets, 0, "Pool should have no debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
    }

    // Get investor's pool token balance and compute withdrawal amount
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    assertGt(investorPoolTokensBefore, 0, "Investor should have pool tokens");
    uint256 withdrawAmount = investorPoolTokensBefore / 2;

    // Build complexAssetsData for no-debt withdrawal
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmComplexAssetsData(withdrawAmount);

    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    // Investor approves and initiates withdrawal
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault was created correctly
    assertEq(vault, investorVault, "Vault address should match prediction");

    // Verify tracked assets have balances
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify withdrawn value matches pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.02e18, // 2% tolerance (PT unrolling may incur minor slippage)
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor has fewer pool tokens
    assertLt(dytmTestPool.balanceOf(investor), investorPoolTokensBefore, "Investor should have fewer pool tokens");

    // Verify pool's DYTM position was reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
    }

    // Verify total value is preserved within tolerance
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.02e18, // 2% tolerance
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Tests: Withdrawal with PT-Holding Collateral Vault - With Debt ==========

  function test_easyswapper_v2_withdrawal_dytm_collateral_pt_with_debt() public {
    _setupPTInCollateralVault();

    // Supply collateralAsset as escrow + borrow borrowAsset via delegationCall
    uint256 initialCollateral = IERC20Extended(collateralAsset).balanceOf(address(dytmTestPool));
    uint256 borrowAmount = borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals());

    PoolLogic.TxToExecute[] memory txs = new PoolLogic.TxToExecute[](2);

    // Supply collateralAsset to DYTM as escrow
    txs[0] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForEscrow(collateralAsset),
          assets: initialCollateral,
          extraData: ""
        })
      )
    });

    // Borrow borrowAsset
    txs[1] = PoolLogic.TxToExecute({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: borrowAmount,
          extraData: ""
        })
      )
    });

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.delegationCall.selector,
        DytmParamStructs.DelegationCallParams({
          delegatee: IDytmDelegatee(address(dytmTestPool)),
          callbackData: abi.encode(txs)
        })
      )
    );

    uint256 totalValueBefore = dytmTestPoolManagerLogic.totalFundValue();

    // Verify position has collateral and debt
    uint256 collateralValueBefore;
    uint256 debtAssetsBefore;
    {
      DytmParamStructs.AccountPosition memory pos = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertGt(pos.totalCollateralValueUSD, 0, "Should have collateral");
      assertGt(pos.debt.debtAssets, 0, "Should have debt");
      collateralValueBefore = pos.totalCollateralValueUSD;
      debtAssetsBefore = pos.debt.debtAssets;
    }

    // Investor withdraws 50%
    uint256 investorPoolTokensBefore = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokensBefore / 2;
    uint256 tokenPriceBefore = dytmTestPool.tokenPrice();

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmComplexAssetsData(withdrawAmount);

    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);

    (IWithdrawalVault.TrackedAsset[] memory trackedAssets, address vault) = easySwapperV2Instance.initWithdrawal(
      address(dytmTestPool),
      withdrawAmount,
      complexAssetsData
    );
    vm.stopPrank();

    // Verify vault and tracked assets
    assertEq(vault, investorVault, "Vault address should match");
    _assertHasNonZeroTrackedAsset(trackedAssets);

    // Verify tracked assets value matches withdrawn pool token value
    {
      uint256 expectedValueD18 = (withdrawAmount * tokenPriceBefore) / 1e18;
      uint256 trackedAssetsValueD18;
      for (uint256 i = 0; i < trackedAssets.length; i++) {
        if (trackedAssets[i].balance > 0) {
          trackedAssetsValueD18 += dytmTestPoolManagerLogic.assetValue(
            trackedAssets[i].token,
            trackedAssets[i].balance
          );
        }
      }
      assertApproxEqRel(
        trackedAssetsValueD18,
        expectedValueD18,
        0.02e18, // 2% tolerance
        "Tracked assets value should match withdrawn pool token value"
      );
    }

    // Complete withdrawal and verify investor received tokens
    vm.prank(investor);
    easySwapperV2Instance.completeWithdrawal();

    // Verify investor received withdrawn assets
    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        assertGt(
          IERC20Extended(trackedAssets[i].token).balanceOf(investor),
          0,
          "Investor should have received withdrawn tokens"
        );
      }
    }

    // Verify pool position is reduced
    {
      DytmParamStructs.AccountPosition memory posAfter = IDytmPeriphery(dytmPeriphery).getAccountPosition(
        uint256(uint160(address(dytmTestPool))),
        marketId
      );
      assertLt(posAfter.totalCollateralValueUSD, collateralValueBefore, "Pool collateral should be reduced");
      assertLt(posAfter.debt.debtAssets, debtAssetsBefore, "Pool debt should be reduced");
    }

    // Verify remaining pool value is approximately half
    uint256 totalValueAfter = dytmTestPoolManagerLogic.totalFundValue();
    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.05e18, // 5% tolerance for swap slippage
      "Remaining pool value should be approximately half"
    );
  }

  // ========== Helpers ==========

  function _setupPTInCollateralVault() internal {
    require(pendlePT != address(0), "PT config not set");
    require(isCollateralDhedgePoolToken, "Collateral must be a dHedge pool token");

    Governance governance = Governance(dhedgePoolFactory.governanceAddress());
    IAssetHandler assetHandler = IAssetHandler(dhedgePoolFactory.getAssetHandler());

    vm.startPrank(dhedgePoolFactory.owner());

    // 1. Deploy PendlePTAssetGuard with the Pendle market
    address[] memory knownPendleMarkets = new address[](1);
    knownPendleMarkets[0] = pendleMarket;
    PendlePTAssetGuard pendlePTAssetGuard = new PendlePTAssetGuard(knownPendleMarkets);
    governance.setAssetGuard(37, address(pendlePTAssetGuard)); // Asset type 37 = PENDLE_PRINCIPAL_TOKEN

    // 2. Deploy mock PT/SY oracle using actual market rate (slightly discounted for slippage buffer)
    (uint256 netSyOut, , , ) = IPActionMarketCoreStatic(pendleStaticRouter).swapExactPtForSyStatic(
      pendleMarket,
      1e18 // 1 PT
    );
    // Use 99% of actual rate to ensure slippage check passes after market swap
    int256 ptRate = int256((netSyOut * 99) / 100);
    MockPendlePTChainlinkOracle mockPtOracle = new MockPendlePTChainlinkOracle(ptRate);
    address pendlePTPriceAggregator = deployCode(
      "PendlePTPriceAggregator.sol",
      abi.encode(pendlePTUnderlying, address(mockPtOracle), address(assetHandler))
    );

    // 3. Register PT in asset handler as type 37
    assetHandler.addAsset(
      pendlePT,
      37, // PENDLE_PRINCIPAL_TOKEN
      pendlePTPriceAggregator
    );

    vm.stopPrank();

    // 4. Add PT as supported asset in the collateral vault
    address collateralPoolManager = PoolLogic(collateralAsset).poolManagerLogic();
    vm.prank(PoolManagerLogic(collateralPoolManager).manager());
    PoolManagerLogic(collateralPoolManager).changeAssets(_toSupportedAssets(pendlePT, false), new address[](0));

    // 5. Deal PT tokens into the collateral vault
    uint256 ptAmount = 1e18; // 1 PT token
    deal(pendlePT, collateralAsset, ptAmount);
  }

  /// @dev Build the complex-assets withdraw payload for any DYTM pool position. `_buildPlanForPoolPosition`
  ///      is data-driven: it reads the live position via `previewWithdrawal`, fully drains each collateral
  ///      (exact predicted split shares — same math the on-chain splitter applies), auto-appends the
  ///      collateral→USDC conversion legs and, when the position has debt, the approve + repay legs. Every
  ///      unwind exits in USDC (the lib enforces `outputAsset == processor.usdc()`), so one builder covers
  ///      the no-debt, with-debt and swap scenarios — no per-scenario variant needed.
  function _buildDytmComplexAssetsData(
    uint256 _withdrawAmount
  ) internal returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    bytes memory withdrawData = abi.encode(_buildPlanForPoolPosition(_withdrawAmount, address(0)));
    complexAssetsData = _wrapComplexAssetsData(withdrawData);
  }

  /// @dev Build the realistic unwind plan for `test_easyswapper_v2_withdrawal_after_leverage_up`.
  ///      After `_leverage_up`, the pool's free balance of every asset is 0 (borrowed USDC was
  ///      swapped to WETH and redeposited into the collateral dHedge pool, then those pool
  ///      tokens were supplied to DYTM), so the vault inherits no USDC from the proportional
  ///      pool transfer and the plan must produce it itself.
  ///
  ///      The collateral is a dHedge pool token (no DEX liquidity — Odos returns 4016 "Routing
  ///      unavailable" when asked to swap it), so we redeem it for its underlying mix instead.
  ///      The collateral pool's USDC share alone exceeds the debt share at the leverage ratio
  ///      used here (`borrowAmountNormalized = 40 USDC` against `collateralAmountNormalized = 100`
  ///      pool tokens worth ~$0.88 each → ~$23 of underlying per 25% withdraw vs. $10 debt), so
  ///      no WETH→USDC swap is needed. Leftover WETH stays in the vault and is picked up by
  ///      `WithdrawalVault._unrollAssets` (it iterates the pool's supported assets and adds any
  ///      with a non-zero vault balance to `srcAssets`), so the investor still receives it.
  function _buildLeverageUpUnwindComplexAssetsData(
    uint256 _withdrawAmount
  ) internal returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    vm.prank(address(0), address(0));
    DytmParamStructs.AssetData[] memory assetData = dytmOfficeAssetGuard.previewWithdrawal(
      address(dytmTestPool),
      _withdrawAmount
    );
    (
      DytmParamStructs.AssetData[] memory collaterals,
      DytmParamStructs.AssetData memory debt,
      bool hasDebt
    ) = _partitionAssetData(assetData);
    require(hasDebt, "leverage-up unwind requires debt");
    require(collaterals.length == 1, "leverage-up unwind expects single collateral");
    require(collaterals[0].asset == collateralAsset, "collateral must be the dHedge pool token");
    require(debt.asset == borrowAsset, "debt asset must be borrowAsset (USDC)");

    address processor = dytmOfficeAssetGuard.dytmWithdrawProcessor();

    // Pre-DYTM-withdraw: dytmOffice.withdraw → DYTMT shares on processor.
    // Post-DYTM-withdraw: redeem DYTMT, handle each underlying (PT redemption + Odos swap to
    // USDC for non-debt assets), then approve + repay.
    DytmWithdrawLib.Action[] memory poolActs = _buildDhedgePoolUnwindActions(
      collateralAsset,
      collaterals[0].amount,
      borrowAsset,
      processor
    );

    DytmWithdrawLib.Action[] memory actions = new DytmWithdrawLib.Action[](poolActs.length + 3);
    actions[0] = DytmWithdrawLib.Action({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: collaterals[0].accountId,
          tokenId: collaterals[0].tokenId,
          receiver: processor,
          assets: 0,
          shares: type(uint256).max,
          extraData: ""
        })
      )
    });
    for (uint256 i; i < poolActs.length; ++i) {
      actions[i + 1] = poolActs[i];
    }
    actions[poolActs.length + 1] = DytmWithdrawLib.Action({
      to: borrowAsset,
      data: abi.encodeWithSelector(IERC20.approve.selector, dytmOffice, type(uint256).max)
    });
    actions[poolActs.length + 2] = DytmWithdrawLib.Action({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.repay.selector,
        DytmParamStructs.RepayParams({
          account: collaterals[0].accountId,
          key: debt.debtKey,
          withCollateralType: DytmParamStructs.TokenType.NONE,
          assets: type(uint256).max,
          shares: 0,
          extraData: ""
        })
      )
    });

    DytmWithdrawLib.UnwindPlan memory plan = DytmWithdrawLib.UnwindPlan({
      actions: actions,
      outputAsset: borrowAsset,
      minOutputAmount: 0
    });
    complexAssetsData = _wrapComplexAssetsData(abi.encode(plan));
  }

  /// @dev Build an `UnwindPlan` for the pool's current DYTM position. If `_outputAsset` is zero,
  ///      uses the first collateral's asset as the output (no debt path); otherwise expects
  ///      `_outputAsset == borrowAsset` and adds approve+repay actions.
  ///
  ///      Uses `previewWithdrawal` (callStatic on the asset guard) to get a flat
  ///      `AssetData[]` covering all withdrawable collaterals + debt with their post-split
  ///      shares, tokenIds, and debtKeys — no rounding-prediction-mismatch issues vs raw
  ///      portion math.
  function _buildPlanForPoolPosition(
    uint256 _withdrawAmount,
    address _outputAsset
  ) internal returns (DytmWithdrawLib.UnwindPlan memory plan) {
    vm.prank(address(0), address(0));
    DytmParamStructs.AssetData[] memory assetData = dytmOfficeAssetGuard.previewWithdrawal(
      address(dytmTestPool),
      _withdrawAmount
    );
    require(assetData.length > 0, "test helper expects at least one entry");

    // Test helper assumption: single market — all entries share the same accountId.
    uint256 splitAccountId = assetData[0].accountId;
    for (uint256 i = 1; i < assetData.length; ++i) {
      require(assetData[i].accountId == splitAccountId, "test helper expects single market");
    }

    // Partition entries into collateral / debt views.
    (
      DytmParamStructs.AssetData[] memory collaterals,
      DytmParamStructs.AssetData memory debt,
      bool hasDebt
    ) = _partitionAssetData(assetData);

    address processor = dytmOfficeAssetGuard.dytmWithdrawProcessor();
    address processorUsdc = IDytmWithdrawProcessor(processor).usdc();

    // Every unwind exits in USDC (enforced by the lib). Convert any non-USDC collateral into
    // USDC after `dytmOffice.withdraw`. For dHedge-pool collateral, `_buildConvertCollateralsToDebtActions`
    // redeems the pool (and unrolls PT) and Odos-swaps each underlying to USDC. Same helper handles
    // the with-debt and no-debt cases — the resulting USDC settles the repay (if any) and the
    // residual is forwarded to the vault as `outputAsset`.
    bool needsConversion;
    for (uint256 i; i < collaterals.length; ++i) {
      if (collaterals[i].asset != processorUsdc) {
        needsConversion = true;
        break;
      }
    }

    DytmWithdrawLib.Action[] memory convertActs;
    if (needsConversion) {
      convertActs = _buildConvertCollateralsToDebtActions(collaterals, processorUsdc, processor);
    }

    uint256 baseActionCount = collaterals.length + (hasDebt ? 2 : 0);
    DytmWithdrawLib.Action[] memory actions = new DytmWithdrawLib.Action[](baseActionCount + convertActs.length);

    // Withdraw each collateral (drain semantics — preview shares is buffered, so use uint256.max).
    // Receiver = processor (the actor running the action plan); processor.process() then forwards
    // the `outputAsset` delta back to the WithdrawalVault that called it.
    for (uint256 i; i < collaterals.length; ++i) {
      actions[i] = DytmWithdrawLib.Action({
        to: dytmOffice,
        data: abi.encodeWithSelector(
          IDytmOffice.withdraw.selector,
          DytmParamStructs.WithdrawParams({
            account: splitAccountId,
            tokenId: collaterals[i].tokenId,
            receiver: processor,
            assets: 0,
            shares: type(uint256).max,
            extraData: ""
          })
        )
      });
    }

    // Splice conversion legs in after the withdraws.
    for (uint256 i; i < convertActs.length; ++i) {
      actions[collaterals.length + i] = convertActs[i];
    }

    // For with-debt path: approve + repay the predicted split debt amount.
    if (hasDebt) {
      uint256 repayBase = collaterals.length + convertActs.length;
      actions[repayBase] = DytmWithdrawLib.Action({
        to: debt.asset,
        data: abi.encodeWithSelector(IERC20.approve.selector, dytmOffice, type(uint256).max)
      });
      actions[repayBase + 1] = DytmWithdrawLib.Action({
        to: dytmOffice,
        data: abi.encodeWithSelector(
          IDytmOffice.repay.selector,
          DytmParamStructs.RepayParams({
            account: splitAccountId,
            key: debt.debtKey,
            withCollateralType: DytmParamStructs.TokenType.NONE,
            assets: type(uint256).max, // burn all debt shares
            shares: 0,
            extraData: ""
          })
        )
      });
    }

    // The lib enforces `outputAsset == processor.usdc()`. Callers can pass `_outputAsset` only as a
    // sanity check (must match USDC) or `address(0)` to use the default.
    address effectiveOutput = _outputAsset == address(0) ? processorUsdc : _outputAsset;

    // Use 0 minOutputAmount — the test asserts on actual received amounts itself.
    plan = DytmWithdrawLib.UnwindPlan({actions: actions, outputAsset: effectiveOutput, minOutputAmount: 0});
  }

  function _findUsdcCollateral(
    DytmParamStructs.AccountPosition memory _position
  ) internal view returns (uint256 assets, uint256 valueUSD) {
    for (uint256 i; i < _position.collaterals.length; ++i) {
      if (_position.collaterals[i].asset == borrowAsset) {
        return (_position.collaterals[i].assets, _position.collaterals[i].valueUSD);
      }
    }
    revert("no USDC collateral on position");
  }

  /// @dev Deal USDC to the pool and supply all of it as DYTM escrow collateral (no debt).
  function _dealAndSupplyUsdcEscrow(uint256 _amount) internal {
    deal(borrowAsset, address(dytmTestPool), _amount);
    _supplyForEscrow({asset: borrowAsset, amountToSupply: _amount});
  }

  /// @dev Build a no-debt unwind plan that withdraws all but `_remnantAssets` of the split
  ///      account's (single, USDC) collateral — deliberately leaving a dust remnant the processor
  ///      must hand back to the pool. No conversion: USDC is already the processor's output asset.
  function _buildPlanLeavingUsdcRemnant(
    uint256 _withdrawAmount,
    uint256 _remnantAssets
  ) internal returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    vm.prank(address(0), address(0));
    DytmParamStructs.AssetData[] memory assetData = dytmOfficeAssetGuard.previewWithdrawal(
      address(dytmTestPool),
      _withdrawAmount
    );
    require(assetData.length == 1 && !assetData[0].isDebt, "helper expects a single USDC collateral, no debt");
    require(assetData[0].asset == borrowAsset, "helper expects USDC collateral");
    require(assetData[0].amount > _remnantAssets, "remnant exceeds split collateral");

    address processor = dytmOfficeAssetGuard.dytmWithdrawProcessor();
    DytmWithdrawLib.Action[] memory actions = new DytmWithdrawLib.Action[](1);
    actions[0] = DytmWithdrawLib.Action({
      to: dytmOffice,
      data: abi.encodeWithSelector(
        IDytmOffice.withdraw.selector,
        DytmParamStructs.WithdrawParams({
          account: assetData[0].accountId,
          tokenId: assetData[0].tokenId,
          receiver: processor,
          assets: assetData[0].amount - _remnantAssets,
          shares: 0,
          extraData: ""
        })
      )
    });

    DytmWithdrawLib.UnwindPlan memory plan = DytmWithdrawLib.UnwindPlan({
      actions: actions,
      outputAsset: IDytmWithdrawProcessor(processor).usdc(),
      minOutputAmount: 0
    });
    complexAssetsData = _wrapComplexAssetsData(abi.encode(plan), 200); // 2% slippage tolerance
  }

  /// @dev For each non-debt collateral, build the action(s) that convert it into the debt asset
  ///      on the processor: dHedge-pool collaterals are redeemed (+ PT-handled) via
  ///      `_buildDhedgePoolUnwindActions`; plain ERC20 collaterals are Odos-swapped directly.
  function _buildConvertCollateralsToDebtActions(
    DytmParamStructs.AssetData[] memory _collaterals,
    address _debtAsset,
    address _recipient
  ) internal returns (DytmWithdrawLib.Action[] memory actions) {
    // Two passes: count, then fill.
    uint256 count;
    DytmWithdrawLib.Action[][] memory chunks = new DytmWithdrawLib.Action[][](_collaterals.length);
    for (uint256 i; i < _collaterals.length; ++i) {
      if (_collaterals[i].asset == _debtAsset) continue;
      DytmWithdrawLib.Action[] memory chunk;
      if (_isDhedgePool(_collaterals[i].asset)) {
        chunk = _buildDhedgePoolUnwindActions(_collaterals[i].asset, _collaterals[i].amount, _debtAsset, _recipient);
      } else {
        chunk = _buildOdosSwapActions(_collaterals[i].asset, _debtAsset, _collaterals[i].amount, _recipient);
      }
      chunks[i] = chunk;
      count += chunk.length;
    }

    actions = new DytmWithdrawLib.Action[](count);
    uint256 idx;
    for (uint256 i; i < chunks.length; ++i) {
      for (uint256 j; j < chunks[i].length; ++j) {
        actions[idx++] = chunks[i][j];
      }
    }
  }

  /// @dev Split a flat `AssetData[]` into a collateral-only view and the (at most one, for the
  ///      single-market case) debt entry. Reverts if multiple debt entries appear.
  function _partitionAssetData(
    DytmParamStructs.AssetData[] memory _entries
  )
    private
    pure
    returns (DytmParamStructs.AssetData[] memory collaterals, DytmParamStructs.AssetData memory debt, bool hasDebt)
  {
    uint256 collateralCount;
    for (uint256 i; i < _entries.length; ++i) {
      if (!_entries[i].isDebt) collateralCount++;
    }
    collaterals = new DytmParamStructs.AssetData[](collateralCount);
    uint256 j;
    for (uint256 i; i < _entries.length; ++i) {
      if (_entries[i].isDebt) {
        require(!hasDebt, "test helper expects at most one debt entry");
        debt = _entries[i];
        hasDebt = true;
      } else {
        collaterals[j++] = _entries[i];
      }
    }
  }

  function _wrapComplexAssetsData(
    bytes memory _withdrawData
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    return _wrapComplexAssetsData(_withdrawData, 100);
  }

  /// @dev Overload that takes an explicit slippage tolerance (in bps). Cross-asset unwinds that
  ///      route through Odos can lose more than 1% to the swap aggregator's allowed slippage and
  ///      need a wider tolerance to clear PoolLogic's per-asset slippage check (`dh26`).
  function _wrapComplexAssetsData(
    bytes memory _withdrawData,
    uint256 _slippageTolerance
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    IHasSupportedAsset.Asset[] memory supportedAssets = dytmTestPoolManagerLogic.getSupportedAssets();
    complexAssetsData = new IPoolLogic.ComplexAsset[](supportedAssets.length);
    for (uint256 i = 0; i < supportedAssets.length; i++) {
      bytes memory assetWithdrawData;
      if (supportedAssets[i].asset == dytmOffice) {
        assetWithdrawData = _withdrawData;
      }
      complexAssetsData[i] = IPoolLogic.ComplexAsset({
        supportedAsset: supportedAssets[i].asset,
        withdrawData: assetWithdrawData,
        slippageTolerance: _slippageTolerance
      });
    }
  }

  function _assertHasNonZeroTrackedAsset(IWithdrawalVault.TrackedAsset[] memory trackedAssets) internal pure {
    assertGt(trackedAssets.length, 0, "Should have tracked assets");
    bool hasNonZeroBalance;
    for (uint256 i = 0; i < trackedAssets.length; i++) {
      if (trackedAssets[i].balance > 0) {
        hasNonZeroBalance = true;
        break;
      }
    }
    assertTrue(hasNonZeroBalance, "At least one tracked asset should have balance");
  }

  function _getSwapDataForSwapper(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    address _swapper
  ) internal returns (uint256 destAmount, bytes memory swapData) {
    OdosAPIHelper.OdosFunctionStruct memory params = OdosAPIHelper.OdosFunctionStruct({
      srcAmount: srcAmount,
      srcToken: srcToken,
      destToken: destToken,
      user: _swapper,
      slippage: 5 // Higher slippage for fork block price differences
    });
    (destAmount, swapData) = getDataFromOdos(params, chainId, true, "v3");
  }

  /// @dev Build an `approve` + Odos `swap` action pair so the processor can convert a non-debt
  ///      asset into the debt asset (or any output asset) during the unwind. Recipient of the
  ///      Odos swap is `_recipient`, which is typically the processor itself.
  function _buildOdosSwapActions(
    address _srcToken,
    address _destToken,
    uint256 _srcAmount,
    address _recipient
  ) internal returns (DytmWithdrawLib.Action[] memory swapActions) {
    (, bytes memory swapData) = _getSwapDataForSwapper(_srcToken, _destToken, _srcAmount, _recipient);
    swapActions = new DytmWithdrawLib.Action[](2);
    swapActions[0] = DytmWithdrawLib.Action({
      to: _srcToken,
      data: abi.encodeWithSelector(IERC20.approve.selector, odosRouter, _srcAmount)
    });
    swapActions[1] = DytmWithdrawLib.Action({to: odosRouter, data: swapData});
  }

  /// @dev Build an `approve` + `exitPreExpToToken` action pair so the processor can redeem PT
  ///      to its underlying via Pendle Router V4. `_recipient` is the address that ends up
  ///      holding the underlying (typically the processor).
  function _buildPtRedeemActions(
    address _pt,
    uint256 _ptAmount,
    address _market,
    address _underlying,
    address _recipient
  ) internal pure returns (DytmWithdrawLib.Action[] memory ptActions) {
    ptActions = new DytmWithdrawLib.Action[](2);
    ptActions[0] = DytmWithdrawLib.Action({
      to: _pt,
      data: abi.encodeWithSelector(IERC20.approve.selector, PENDLE_ROUTER_V4, _ptAmount)
    });
    ptActions[1] = DytmWithdrawLib.Action({
      to: PENDLE_ROUTER_V4,
      data: abi.encodeWithSelector(
        IPActionMiscV3.exitPreExpToToken.selector,
        _recipient,
        _market,
        _ptAmount,
        uint256(0),
        uint256(0),
        createTokenOutputSimple(_underlying, 0),
        createEmptyLimitOrderData()
      )
    });
  }

  /// @dev Predict the amount of `_underlying` that `IPoolLogic(_pool).withdraw(_shareAmount)`
  ///      will deliver. `previewWithdrawal` only returns the post-split DYTM-asset amount
  ///      (i.e. the collateral-pool share), so this proportional split has to be computed here
  ///      to size the subsequent Odos swap. In a fork test no time passes between the prediction
  ///      and execution, so `supplyAfterMint == totalSupply` and the theoretical math is exact.
  function _predictDhedgePoolUnderlying(
    address _pool,
    address _underlying,
    uint256 _shareAmount
  ) internal view returns (uint256) {
    uint256 totalSupply = IERC20Extended(_pool).totalSupply();
    if (totalSupply == 0) return 0;
    uint256 poolBalance = IERC20Extended(_underlying).balanceOf(_pool);
    return (_shareAmount * poolBalance) / totalSupply;
  }

  /// @dev Predict the `_tokenOut` amount from `ROUTER_V4.exitPreExpToToken(... PT ...)` via the
  ///      Pendle static router. Used to size the post-redeem Odos swap leg.
  function _predictPtToTokenOut(
    address _market,
    uint256 _ptIn,
    address _tokenOut
  ) internal view returns (uint256 netTokenOut) {
    (netTokenOut, , , , ) = IPActionMarketCoreStatic(pendleStaticRouter).swapExactPtForTokenStatic(
      _market,
      _ptIn,
      _tokenOut
    );
  }

  /// @dev Build the post-`dytmOffice.withdraw` action sequence for a dHedge-pool collateral:
  ///        1. `IPoolLogic(_dhedgePool).withdraw(_redeemAmount)` — burns the processor's shares
  ///           and delivers each underlying proportionally to the processor.
  ///        2. For each non-debt underlying:
  ///             - If it's a Pendle PT (asset type 37): approve + `ROUTER_V4.exitPreExpToToken`
  ///               → `pendlePTUnderlying`; then swap that to `_debtAsset` via Odos.
  ///             - Else: directly swap underlying → `_debtAsset` via Odos.
  ///      The processor ends holding only `_debtAsset` (any leftover from PT-vs-static slippage
  ///      or Odos slippage stays as small dust covered by `slippageTolerance`).
  function _buildDhedgePoolUnwindActions(
    address _dhedgePool,
    uint256 _redeemAmount,
    address _debtAsset,
    address _recipient
  ) internal returns (DytmWithdrawLib.Action[] memory actions) {
    IHasSupportedAsset.Asset[] memory underlyings = IHasSupportedAsset(PoolLogic(_dhedgePool).poolManagerLogic())
      .getSupportedAssets();

    actions = new DytmWithdrawLib.Action[](
      _countDhedgePoolUnwindActions(_dhedgePool, _redeemAmount, underlyings, _debtAsset)
    );
    actions[0] = DytmWithdrawLib.Action({
      to: _dhedgePool,
      data: abi.encodeWithSelector(IPoolLogic.withdraw.selector, _redeemAmount)
    });

    uint256 idx = 1;
    for (uint256 i; i < underlyings.length; ++i) {
      address ua = underlyings[i].asset;
      if (ua == _debtAsset) continue;
      uint256 uaAmount = _predictDhedgePoolUnderlying(_dhedgePool, ua, _redeemAmount);
      if (uaAmount == 0) continue; // pool holds 0 of this underlying — no swap to encode
      idx = _appendUnderlyingToDebtActions(actions, idx, ua, uaAmount, _debtAsset, _recipient);
    }
  }

  function _countDhedgePoolUnwindActions(
    address _dhedgePool,
    uint256 _redeemAmount,
    IHasSupportedAsset.Asset[] memory _underlyings,
    address _debtAsset
  ) private view returns (uint256 count) {
    address poolFactory = address(dhedgePoolFactory);
    count = 1; // the redeem action
    for (uint256 i; i < _underlyings.length; ++i) {
      address ua = _underlyings[i].asset;
      if (ua == _debtAsset) continue;
      if (_predictDhedgePoolUnderlying(_dhedgePool, ua, _redeemAmount) == 0) continue;
      if (IHasAssetInfo(poolFactory).getAssetType(ua) == ASSET_TYPE_PENDLE_PT) {
        count += 2; // PT approve + PT redeem
      }
      count += 2; // Odos approve + Odos swap
    }
  }

  function _appendUnderlyingToDebtActions(
    DytmWithdrawLib.Action[] memory _actions,
    uint256 _idx,
    address _ua,
    uint256 _uaAmount,
    address _debtAsset,
    address _recipient
  ) private returns (uint256) {
    if (IHasAssetInfo(address(dhedgePoolFactory)).getAssetType(_ua) == ASSET_TYPE_PENDLE_PT) {
      DytmWithdrawLib.Action[] memory ptActs = _buildPtRedeemActions(
        _ua,
        _uaAmount,
        pendleMarket,
        pendlePTUnderlying,
        _recipient
      );
      _actions[_idx++] = ptActs[0];
      _actions[_idx++] = ptActs[1];
      DytmWithdrawLib.Action[] memory swapActs = _buildOdosSwapActions(
        pendlePTUnderlying,
        _debtAsset,
        _predictPtToTokenOut(pendleMarket, _uaAmount, pendlePTUnderlying),
        _recipient
      );
      _actions[_idx++] = swapActs[0];
      _actions[_idx++] = swapActs[1];
    } else {
      DytmWithdrawLib.Action[] memory swapActs = _buildOdosSwapActions(_ua, _debtAsset, _uaAmount, _recipient);
      _actions[_idx++] = swapActs[0];
      _actions[_idx++] = swapActs[1];
    }
    return _idx;
  }

  // ========== Tests: Debt with no swap needed ==========

  function test_easyswapper_withdraw_dytm_with_debt_no_swap_needed() public {
    // Setup: supply borrowAsset (USDC) as both collateral and debt on market 1
    // After filterSrcDataAndCalculateMinDst, srcData will be empty (collateral == debt asset)

    // 1. Configure USDC-ESCROW / USDC-debt weight
    IDytmWeights weights = IDytmWeights(IMarketConfig(dytmMarketConfig).weights());
    vm.prank(marketCreator);
    weights.setWeight(_getTokenIdForMarket(borrowAsset, marketId, 1), _getReserveKey(borrowAsset), uint64(0.85e18));

    // 2. Deal USDC to the pool and supply as ESCROW collateral (ONLY USDC, no other collateral)
    uint256 usdcSupplyAmount = borrowAmountNormalized * 10 * (10 ** IERC20Extended(borrowAsset).decimals());
    deal(borrowAsset, address(dytmTestPool), usdcSupplyAmount);

    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.supply.selector,
        DytmParamStructs.SupplyParams({
          account: uint256(uint160(address(dytmTestPool))),
          tokenId: _getTokenIdForMarket(borrowAsset, marketId, 1), // ESCROW
          assets: usdcSupplyAmount,
          extraData: ""
        })
      )
    );

    // 3. Borrow USDC (same asset as collateral)
    uint256 borrowAmount = borrowAmountNormalized * (10 ** IERC20Extended(borrowAsset).decimals());
    vm.prank(manager);
    dytmTestPool.execTransaction(
      dytmOffice,
      abi.encodeWithSelector(
        IDytmOffice.borrow.selector,
        DytmParamStructs.BorrowParams({
          account: uint256(uint160(address(dytmTestPool))),
          key: _getReserveKey(borrowAsset),
          receiver: address(dytmTestPool),
          assets: borrowAmount,
          extraData: ""
        })
      )
    );

    // Verify position: has ONLY USDC collateral and USDC debt
    DytmParamStructs.AccountPosition memory position = IDytmPeriphery(dytmPeriphery).getAccountPosition(
      uint256(uint160(address(dytmTestPool))),
      marketId
    );
    assertGt(position.totalCollateralValueUSD, 0, "Should have collateral");
    assertGt(position.debt.debtAssets, 0, "Should have debt");
    assertEq(position.debt.debtAsset, borrowAsset, "Debt asset should be borrowAsset");

    // 4. Withdrawal via EasySwapperV2.initWithdrawal (unwinds via DytmWithdrawLib in the vault)
    // filterSrcDataAndCalculateMinDst filters out USDC (== debt asset) → srcData is empty.
    // The unwind library handles this via _processDebtNoSwapCase (repay without swapping).
    uint256 investorPoolTokens = dytmTestPool.balanceOf(investor);
    uint256 withdrawAmount = investorPoolTokens / 2;
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildDytmComplexAssetsData(withdrawAmount);

    vm.warp(block.timestamp + 86401);
    vm.startPrank(investor);
    IERC20Extended(address(dytmTestPool)).approve(address(easySwapperV2Instance), withdrawAmount);
    easySwapperV2Instance.initWithdrawal(address(dytmTestPool), withdrawAmount, complexAssetsData);
    vm.stopPrank();
  }
}
