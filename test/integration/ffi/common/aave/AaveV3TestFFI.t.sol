// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {OdosAPIHelper} from "test/integration/common/odos/OdosAPIHelper.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {AaveLendingPoolAssetGuard} from "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";
import {IERC20Extended} from "contracts/interfaces/IERC20Extended.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {AaveV3TestSetup} from "test/integration/common/aaveV3/AaveV3TestSetup.t.sol";
import {IPMarket} from "contracts/interfaces/pendle/IPMarket.sol";
import {IAaveV3Pool} from "contracts/interfaces/aave/v3/IAaveV3Pool.sol";

abstract contract AaveV3TestFFI is AaveV3TestSetup, OdosAPIHelper {
  uint256 private immutable chainId;

  constructor(uint256 _chainId) {
    chainId = _chainId;
  }

  function setUp() public virtual override {
    super.setUp();
    __OdosAPIHelper_init(true);
  }

  function test_can_withdraw_from_pool_with_assets_supplied_and_borrowed_in_aave_v3_with_swapdata_PT_not_expired()
    public
  {
    can_withdraw_from_pool_with_assets_supplied_and_borrowed_in_aave_v3_with_swapdata(block.timestamp + 1 days, false);
  }

  function test_can_withdraw_from_pool_with_assets_supplied_and_borrowed_in_aave_v3_with_swapdata_PT_expired() public {
    bool shouldSkip = token0ToLendPendleMarket == address(0);
    vm.skip(shouldSkip);

    uint256 expiry = IPMarket(token0ToLendPendleMarket).expiry();
    can_withdraw_from_pool_with_assets_supplied_and_borrowed_in_aave_v3_with_swapdata(expiry + 1 days, false);
  }

  function can_withdraw_from_pool_with_assets_supplied_and_borrowed_in_aave_v3_with_swapdata(
    uint256 _newTimestamp,
    bool _lendTwoTokens
  ) internal {
    vm.warp(_newTimestamp);

    if (_lendTwoTokens) {
      deal(
        token1ToLend,
        address(aaveTestPool),
        token1AmountNormalized * (10 ** IERC20Extended(token1ToLend).decimals())
      );
    }

    // 50% of the pool
    uint256 amountToWithdraw = IERC20Extended(address(aaveTestPool)).balanceOf(investor) / 2;
    uint256 valueToWithdraw = (aaveTestPool.tokenPrice() * amountToWithdraw) / 1e18;

    uint256 token0ToLendBalanceBefore = IERC20Extended(token0ToLend).balanceOf(investor);
    uint256 tokenToBorrowBalanceBefore = IERC20Extended(tokenToBorrow).balanceOf(investor);

    assertEq(tokenToBorrowBalanceBefore, 0, "Investor should have no token to borrow before withdraw");

    _supplyAndBorrow();

    if (_lendTwoTokens) {
      uint256 amountToSupply = IERC20Extended(token1ToLend).balanceOf(address(aaveTestPool));
      vm.prank(manager);
      aaveTestPool.execTransaction(
        aaveV3Pool,
        abi.encodeWithSelector(IAaveV3Pool.supply.selector, token1ToLend, amountToSupply, address(aaveTestPool), 0)
      );
    }

    if (token0ToLendUnderlying != address(0)) {
      uint256 token0ToLendUnderlyingPoolBalanceBeforeWithdraw = IERC20Extended(token0ToLendUnderlying).balanceOf(
        address(aaveTestPool)
      );
      assertEq(token0ToLendUnderlyingPoolBalanceBeforeWithdraw, 0, "Pool has no PT underlying sitting in the vault");
    }

    uint256 totalValueBefore = aaveTestPoolManagerLogic.totalFundValue();

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = aaveLendingPoolAssetGuard.calculateSwapDataParams(
      address(aaveTestPool),
      amountToWithdraw,
      withdrawData.slippageTolerance
    );

    withdrawData.destData.destToken = IERC20(swapDataParams.dstData.asset);

    ISwapper.SrcTokenSwapDetails[] memory srcData = new ISwapper.SrcTokenSwapDetails[](swapDataParams.srcData.length);

    for (uint256 i = 0; i < srcData.length; i++) {
      srcData[i].token = IERC20(swapDataParams.srcData[i].asset);
      srcData[i].amount = swapDataParams.srcData[i].amount;
      srcData[i].aggregatorData.routerKey = bytes32("ODOS_V2");

      OdosAPIHelper.OdosFunctionStruct memory params = OdosAPIHelper.OdosFunctionStruct({
        srcAmount: swapDataParams.srcData[i].amount,
        srcToken: swapDataParams.srcData[i].asset,
        destToken: swapDataParams.dstData.asset,
        user: swapper,
        slippage: 1
      });

      (uint256 destAmount, bytes memory swapData) = getDataFromOdos(params, swapper, 1, chainId, true);

      srcData[i].aggregatorData.swapData = swapData;
      withdrawData.destData.minDestAmount += destAmount;
    }

    withdrawData.srcData = abi.encode(srcData);

    PoolManagerLogic.Asset[] memory poolAssets = aaveTestPoolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == aaveV3Pool) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    vm.startPrank(investor);
    aaveTestPool.withdrawSafe(amountToWithdraw, complexAssetsData);

    uint256 totalValueAfter = aaveTestPoolManagerLogic.totalFundValue();
    uint256 token0ToLendBalanceAfter = IERC20Extended(token0ToLend).balanceOf(investor);
    uint256 tokenToBorrowBalanceAfter = IERC20Extended(tokenToBorrow).balanceOf(investor);
    uint256 valueWithdrawn = aaveTestPoolManagerLogic.assetValue(tokenToBorrow, tokenToBorrowBalanceAfter);

    assertApproxEqRel(
      totalValueAfter,
      totalValueBefore / 2,
      0.0001e18, // 0.01%
      "Total value should become twice less after withdraw"
    );
    assertEq(
      token0ToLendBalanceBefore,
      token0ToLendBalanceAfter,
      "Investor balance of token 0 to lend should not change after withdraw"
    );

    assertGt(tokenToBorrowBalanceAfter, 0, "Investor should receive token to borrow after withdraw");
    assertApproxEqRel(
      valueWithdrawn,
      valueToWithdraw,
      0.01e18, // 1% - according to withdrawData.slippageTolerance
      "Value withdrawn should be approximately equal to the value of the withdrawn pool share"
    );

    if (token0ToLendUnderlying != address(0)) {
      uint256 token0ToLendUnderlyingPoolBalanceAfterWithdraw = IERC20Extended(token0ToLendUnderlying).balanceOf(
        address(aaveTestPool)
      );

      assertGt(token0ToLendUnderlyingPoolBalanceAfterWithdraw, 0, "Pool should have PT underlying dust after withdraw");
    }
  }
}
