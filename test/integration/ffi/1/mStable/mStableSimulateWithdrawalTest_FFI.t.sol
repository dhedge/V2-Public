// SPDX-License-Identifier: MIT
// solhint-disable contract-name-capwords
pragma solidity 0.7.6;
pragma abicoder v2;

import {ChainlinkTWAPAggregator} from "contracts/priceAggregators/ChainlinkTWAPAggregator.sol";
import {UniV3TWAPAggregator} from "contracts/priceAggregators/UniV3TWAPAggregator.sol";
import {IAggregatorV3Interface} from "contracts/interfaces/IAggregatorV3Interface.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";
import {OdosAPIHelper} from "test/integration/common/odos/OdosAPIHelper.sol";
import {AaveLendingPoolAssetGuard} from "contracts/guards/assetGuards/AaveLendingPoolAssetGuard.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {ISwapper} from "contracts/interfaces/flatMoney/swapper/ISwapper.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {mStableTroubleshootingTest} from "test/integration/ethereum/mStable/mStableTroubleshootingTest.t.sol";

import {console} from "forge-std/console.sol";

/// @dev FOUNDRY_PROFILE=ffi-tests forge test --mc mStableSimulateWithdrawalTestFFI to run only this test
contract mStableSimulateWithdrawalTestFFI is mStableTroubleshootingTest, OdosAPIHelper {
  uint32 public twapDuration = 1800; // 30 minutes
  uint256 public maxDifferencePercent = 3e15; // 0.3%

  constructor() mStableTroubleshootingTest(23626300, 0, "", twapDuration) {}

  function setUp() public virtual override {
    super.setUp();
    __OdosAPIHelper_init(true);
  }

  function test_can_withdraw_from_mstable_vault() public {
    _switchOracle();

    uint256 amountToWithdraw = 100_000e18;
    uint256 withdrawalValue = (vault.tokenPrice() * amountToWithdraw) / 1e18;
    console.log("Withdrawal value in USD:", withdrawalValue);

    AaveLendingPoolAssetGuard.ComplexAssetSwapData memory withdrawData;
    withdrawData.slippageTolerance = 100; // 1%

    AaveLendingPoolAssetGuard.SwapDataParams memory swapDataParams = AaveLendingPoolAssetGuard(
      0x8c2673aB7dad2C6f50D54B6FaFE5F67EaFa16810
    ).calculateSwapDataParams(address(vault), amountToWithdraw, withdrawData.slippageTolerance);

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
        user: EthereumConfig.SWAPPER,
        slippage: 1 // 1%
      });

      (, bytes memory swapData) = getDataFromOdos(params, EthereumConfig.CHAIN_ID, true, "v2");

      srcData[i].aggregatorData.swapData = swapData;
    }

    withdrawData.srcData = abi.encode(srcData);
    withdrawData.destData.minDestAmount = swapDataParams.dstData.amount;

    PoolManagerLogic poolManagerLogic = PoolManagerLogic(vault.poolManagerLogic());
    PoolManagerLogic.Asset[] memory poolAssets = poolManagerLogic.getSupportedAssets();
    IPoolLogic.ComplexAsset[] memory complexAssetsData = new IPoolLogic.ComplexAsset[](poolAssets.length);

    for (uint256 i = 0; i < complexAssetsData.length; i++) {
      complexAssetsData[i].supportedAsset = poolAssets[i].asset;

      if (complexAssetsData[i].supportedAsset == EthereumConfig.AAVE_V3_LENDING_POOL) {
        complexAssetsData[i].withdrawData = abi.encode(withdrawData);
        complexAssetsData[i].slippageTolerance = withdrawData.slippageTolerance;
      }
    }

    vm.startPrank(withdrawer);
    vault.withdrawSafe(amountToWithdraw, complexAssetsData);

    uint256 valueWithdrawn = poolManagerLogic.assetValue(
      EthereumConfig.sUSDe,
      PoolLogic(EthereumConfig.sUSDe).balanceOf(withdrawer)
    ) +
      PoolManagerLogic(poolManagerLogic).assetValue(
        EthereumConfig.USDT,
        PoolLogic(EthereumConfig.USDT).balanceOf(withdrawer)
      ) +
      PoolManagerLogic(poolManagerLogic).assetValue(
        EthereumConfig.PT_sUSDe_NOV_2025,
        PoolLogic(EthereumConfig.PT_sUSDe_NOV_2025).balanceOf(withdrawer)
      );
    console.log("Value in USD received:", valueWithdrawn);

    assertApproxEqRel(
      withdrawalValue,
      valueWithdrawn,
      0.01e18, // 1%
      "Value withdrawn should be approximately equal to the value of the withdrawn pool share"
    );

    _logDifference(withdrawalValue, valueWithdrawn);
  }

  function _switchOracle() internal override {
    UniV3TWAPAggregator twapAggregator = new UniV3TWAPAggregator(
      sUSDeUSDTPool,
      EthereumConfig.sUSDe,
      IAggregatorV3Interface(EthereumConfig.USDT_CHAINLINK_ORACLE),
      twapDuration
    );

    ChainlinkTWAPAggregator newAggregator = new ChainlinkTWAPAggregator(
      IAggregatorV3Interface(existingsUSDeAggregator),
      IAggregatorV3Interface(address(twapAggregator)),
      maxDifferencePercent,
      ChainlinkTWAPAggregator.ResultingPrice.TWAP // Always returns the TWAP price
    );

    vm.prank(owner);
    AssetHandler(assetHandler).addAsset(EthereumConfig.sUSDe, 200, address(newAggregator));

    // The on-chain deployed PT aggregator still uses the old UnderlyingAssetOracleUpdater with stored state,
    // so we need to call updateUnderlyingAggregator() to refresh its cached reference after the oracle switch.
    (bool success, ) = EthereumConfig.PT_sUSDe_NOV_2025_PRICE_AGGREGATOR.call(
      abi.encodeWithSignature("updateUnderlyingAggregator()")
    );
    require(success, "updateUnderlyingAggregator failed");
  }
}
