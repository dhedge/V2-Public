// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {OdosAPIHelper} from "test/integration/common/odos/OdosAPIHelper.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {Governance} from "contracts/Governance.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasGuardInfo} from "contracts/interfaces/IHasGuardInfo.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {AaveLendingPoolAssetGuard} from "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

/// @notice Tests that the dh26 net slippage check correctly handles leverage-amplified slippage.
/// With the updated AaveLendingPoolAssetGuard, the user passes their desired NET slippage tolerance.
/// The guard internally scales it down for the swap based on leverage.
/// The dh26 check in PoolLogic then verifies the user received value within their net tolerance.
contract AaveNetSlippageTestFFI is Test, OdosAPIHelper {
  PoolLogic public vault = PoolLogic(EthereumConfig.mPT_sUSDe);
  PoolFactory public factory = PoolFactory(EthereumConfig.POOL_FACTORY_PROD);
  AaveLendingPoolAssetGuard public aaveGuard;

  // Existing depositor with balance at fork block
  address public depositor = 0x714167f0075D49c2d5FF57DdF8C2F81F119Dfeb7;

  function setUp() public {
    vm.createSelectFork("ethereum", 24672158);
    __OdosAPIHelper_init(true);

    // Get existing guard to copy its constructor parameters
    AaveLendingPoolAssetGuard existingGuard = AaveLendingPoolAssetGuard(
      IHasGuardInfo(address(factory)).getAssetGuard(EthereumConfig.AAVE_V3_LENDING_POOL)
    );

    vm.startPrank(factory.owner());

    // Deploy new PoolLogic with the dh26 net slippage check and upgrade all pools via factory
    address newPoolLogic = address(new PoolLogic());
    address newPoolManagerLogic = address(new PoolManagerLogic());
    factory.setLogic(newPoolLogic, newPoolManagerLogic);

    // Deploy new AaveLendingPoolAssetGuard with leverage scaling logic
    aaveGuard = new AaveLendingPoolAssetGuard(
      existingGuard.aaveLendingPool(),
      existingGuard.swapper(),
      existingGuard.onchainSwapRouter(),
      existingGuard.pendleYieldContractFactory(),
      existingGuard.pendleRouterStatic(),
      5 // mismatchDelta - 0.05%
    );

    // Register the new guard via governance
    Governance governance = Governance(factory.governanceAddress());
    governance.setAssetGuard(uint16(BackboneSetup.AssetTypeIncomplete.AAVE_V3), address(aaveGuard));

    vm.stopPrank();

    // Verify depositor has balance
    uint256 balance = vault.balanceOf(depositor);
    require(balance > 0, "Investor has no vault tokens at this fork block");
  }

  function test_revert_withdrawSafe_with_tight_swap_slippage_tolerance() public {
    uint256 amountToWithdraw = vault.balanceOf(depositor);

    // When 0.2% scaled down at ~7x leverage, the swap will revert because of swap slippage being too tight.
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildWithdrawData(amountToWithdraw, 20);

    vm.prank(depositor);
    vm.expectPartialRevert(bytes4(keccak256("InsufficientAmountReceived(address,uint256,uint256)"))); // Error from Swapper contract
    vault.withdrawSafe(amountToWithdraw, complexAssetsData);
  }

  /// @notice With tight net tolerance, dh26 catches when actual slippage exceeds user's expectation.
  function test_revert_withdrawSafe_with_tight_net_slippage_tolerance() public {
    uint256 amountToWithdraw = vault.balanceOf(depositor);

    // 0.5% net tolerance is too tight for a leveraged position
    // Even though guard scales it down for swap and swaps are executed, actual swap slippage will likely exceed
    // what's needed to meet the net tolerance requirement
    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildWithdrawData(amountToWithdraw, 50);

    vm.prank(depositor);
    vm.expectRevert(bytes("dh26"));
    vault.withdrawSafe(amountToWithdraw, complexAssetsData);
  }

  /// @notice With adequate net tolerance, withdrawal succeeds.
  function test_withdrawSafe_succeeds_with_adequate_net_slippage_tolerance() public {
    uint256 amountToWithdraw = vault.balanceOf(depositor);
    uint256 netSlippageTolerance = 60; // 0.6% - adequate for stable pairs swap slippage at current vault leverage (~7x)

    // Store expected value before withdrawal
    uint256 expectedValue = (vault.tokenPrice() * amountToWithdraw) / 1e18;

    // Store token balances before withdrawal
    uint256 usdtBalanceBefore = IERC20(EthereumConfig.USDT).balanceOf(depositor);
    uint256 usdeBalanceBefore = IERC20(EthereumConfig.USDe).balanceOf(depositor);

    IPoolLogic.ComplexAsset[] memory complexAssetsData = _buildWithdrawData(amountToWithdraw, netSlippageTolerance);

    vm.prank(depositor);
    vault.withdrawSafe(amountToWithdraw, complexAssetsData);

    assertEq(vault.balanceOf(depositor), 0, "Investor should have no pool tokens after full withdrawal");

    // Calculate and assert received value
    _assertReceivedValue(usdtBalanceBefore, usdeBalanceBefore, expectedValue, netSlippageTolerance);
  }

  function _assertReceivedValue(
    uint256 _usdtBalanceBefore,
    uint256 _usdeBalanceBefore,
    uint256 _expectedValue,
    uint256 _netSlippageTolerance
  ) internal view {
    PoolManagerLogic pmLogic = PoolManagerLogic(vault.poolManagerLogic());
    uint256 usdtReceived = IERC20(EthereumConfig.USDT).balanceOf(depositor) - _usdtBalanceBefore;
    uint256 usdeReceived = IERC20(EthereumConfig.USDe).balanceOf(depositor) - _usdeBalanceBefore;

    uint256 totalReceivedValue = pmLogic.assetValue(EthereumConfig.USDT, usdtReceived) +
      pmLogic.assetValue(EthereumConfig.USDe, usdeReceived);

    uint256 minExpectedValue = (_expectedValue * (10_000 - _netSlippageTolerance)) / 10_000;
    assertGe(totalReceivedValue, minExpectedValue, "Received value should be within net slippage tolerance");
  }

  function _buildWithdrawData(
    uint256 _amountToWithdraw,
    uint256 _slippageTolerance
  ) internal returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    PoolManagerLogic pmLogic = PoolManagerLogic(vault.poolManagerLogic());
    PoolManagerLogic.Asset[] memory poolAssets = pmLogic.getSupportedAssets();
    complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == EthereumConfig.AAVE_V3_LENDING_POOL) {
        AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
        // User passes their desired NET slippage tolerance
        // Guard internally scales it down for the swap based on leverage
        withdrawData.slippageTolerance = _slippageTolerance;

        AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveGuard.calculateSwapDataParams(
          address(vault),
          _amountToWithdraw,
          withdrawData.slippageTolerance
        );

        require(swapDataParams.srcData.length > 0, "No leveraged position detected");

        withdrawData.destData.destToken = IERC20(swapDataParams.dstData.asset);

        ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](
          swapDataParams.srcData.length
        );

        for (uint256 j; j < srcData.length; j++) {
          srcData[j].token = IERC20(swapDataParams.srcData[j].asset);
          srcData[j].amount = swapDataParams.srcData[j].amount;
          srcData[j].aggregatorData.routerKey = bytes32("ODOS_V2");

          OdosAPIHelper.OdosFunctionStruct memory params = OdosAPIHelper.OdosFunctionStruct({
            srcAmount: swapDataParams.srcData[j].amount,
            srcToken: swapDataParams.srcData[j].asset,
            destToken: swapDataParams.dstData.asset,
            user: aaveGuard.swapper(),
            slippage: 1
          });

          (, bytes memory swapCalldata) = getDataFromOdos(params, EthereumConfig.CHAIN_ID, true, "v2");
          srcData[j].aggregatorData.swapData = swapCalldata;
        }

        withdrawData.srcData = abi.encode(srcData);
        withdrawData.destData.minDestAmount = swapDataParams.dstData.amount;

        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        // Same tolerance used for both - guard scales for swap, PoolLogic uses for net check
        complexAssetsData[i].slippageTolerance = _slippageTolerance;
      }
    }
  }
}
