// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";

import {DeploymentDryRunHyperEVM} from "test/integration/utils/foundry/dryRun/DeploymentDryRunHyperEVM.t.sol";
import {HyperEVMConfig} from "test/integration/utils/foundry/config/HyperEVMConfig.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";
import {console} from "forge-std/console.sol";

/// @notice Dry run test for switching HyperliquidPositionGuard (asset type 39) oracle
///         from USDPriceAggregator to USDC/USD Chainlink feed.
/// @dev HyperliquidPositionGuard.getBalance() returns value denominated in USDC, not USD.
///      Using USDPriceAggregator (hardcoded $1.00) is inaccurate during USDC depegs.
///      This test validates that swapping to the USDC/USD Chainlink feed doesn't break
///      existing vault token prices or deposits.
contract HyperliquidOracleDryRunHyperEVM is DeploymentDryRunHyperEVM, IntegrationDeployer {
  uint16 internal constant HYPERLIQUID_PERPS_ASSET_TYPE = 39;
  uint256 internal constant TOLERANCE_BPS = 40; // 0.4%

  constructor() DeploymentDryRunHyperEVM(0, _getVaults()) {}

  function setUp() public override {
    // Skipped: migration to USDC/USD Chainlink oracle has already been executed on-chain.
    // Additionally, these tests run against fresh live data on every execution rather than
    // fixed cached fork data, making them significantly slower than regular fork tests.
    vm.skip(true);

    super.setUp();

    this.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);
  }

  function deployIntegration(PoolFactory _poolFactory, address, address, address) external override {
    AssetHandler assetHandler = AssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());
    assetHandler.addAsset(HyperEVMConfig.CORE_WRITER, HYPERLIQUID_PERPS_ASSET_TYPE, HyperEVMConfig.USDC_USD_PRICE_FEED);
    vm.stopPrank();
  }

  function test_token_prices_should_stay_same_after_new_deployment() public view override {
    for (uint256 i; i < torosVaultsToCheck.length; ++i) {
      uint256 beforePrice = tokenPricesBeforeTheUpgrade[i];
      uint256 afterPrice = PoolLogic(torosVaultsToCheck[i]).tokenPrice();

      uint256 diff = beforePrice > afterPrice ? beforePrice - afterPrice : afterPrice - beforePrice;
      uint256 maxAllowedDiff = (beforePrice * TOLERANCE_BPS) / 10_000;

      uint256 diffScaled = (diff * 1_000_000) / beforePrice;

      string memory symbol = PoolLogic(torosVaultsToCheck[i]).symbol();

      console.log(
        string(
          abi.encodePacked(
            "Vault: ",
            _addressToString(torosVaultsToCheck[i]),
            ", Diff (%): ",
            vm.toString(diffScaled / 10_000),
            ".",
            _formatDecimals(diffScaled % 10_000, 4),
            "%, Diff (bps): ",
            vm.toString(diffScaled / 100),
            ".",
            _formatDecimals(diffScaled % 100, 2),
            " bps",
            "  (",
            symbol,
            ")  "
          )
        )
      );

      assertGe(
        maxAllowedDiff,
        diff,
        string(
          abi.encodePacked("tokenPrice allowed diff out of bounds for vault: ", _addressToString(torosVaultsToCheck[i]))
        )
      );
    }
  }

  function test_deposits_should_work_after_new_deployment() public override {
    for (uint256 i; i < torosVaultsToCheck.length; ++i) {
      uint256 tokenPriceBefore = PoolLogic(torosVaultsToCheck[i]).tokenPrice();
      _depositIntoVault(torosVaultsToCheck[i]);
      uint256 tokenPriceAfter = PoolLogic(torosVaultsToCheck[i]).tokenPrice();

      uint256 diff = tokenPriceBefore > tokenPriceAfter
        ? tokenPriceBefore - tokenPriceAfter
        : tokenPriceAfter - tokenPriceBefore;
      uint256 maxAllowedDiff = (tokenPriceBefore * TOLERANCE_BPS) / 10_000;

      assertGe(
        maxAllowedDiff,
        diff,
        string(
          abi.encodePacked(
            "after deposit tokenPrice diff out of bounds for vault: ",
            _addressToString(torosVaultsToCheck[i])
          )
        )
      );
    }
  }

  function _getVaults() internal pure returns (address[] memory vaults) {
    vaults = new address[](12);
    vaults[0] = HyperEVMConfig.SP500BULL2X;
    vaults[1] = HyperEVMConfig.NVDABULL2X;
    vaults[2] = HyperEVMConfig.NVDABULL3X;
    vaults[3] = HyperEVMConfig.SP500BULL3X;
    vaults[4] = HyperEVMConfig.GOLDBULL3X;
    vaults[5] = HyperEVMConfig.GOLDBULL2X;
    vaults[6] = HyperEVMConfig.SLVBULL2X;
    vaults[7] = HyperEVMConfig.SLVBULL3X;
    vaults[8] = HyperEVMConfig.NDXBULL2X;
    vaults[9] = HyperEVMConfig.NDXBULL3X;
    vaults[10] = HyperEVMConfig.RSPSG;
    vaults[11] = HyperEVMConfig.KARMA;
  }

  function _formatDecimals(uint256 value, uint256 decimals) internal pure returns (string memory) {
    string memory s = vm.toString(value);
    while (bytes(s).length < decimals) {
      s = string(abi.encodePacked("0", s));
    }
    return s;
  }
}
