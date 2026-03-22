// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";
import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";

import {DeploymentDryRunArbitrum} from "test/integration/utils/foundry/dryRun/DeploymentDryRunArbitrum.t.sol";
import {ArbitrumConfig} from "test/integration/utils/foundry/config/ArbitrumConfig.sol";
import {IntegrationDeployer} from "test/integration/utils/foundry/dryRun/IntegrationDeployer.t.sol";
import {GmxExchangeRouterContractGuard} from "contracts/guards/contractGuards/gmx/GmxExchangeRouterContractGuard.sol";
import {GmxPerpMarketAssetGuard} from "contracts/guards/assetGuards/gmx/GmxPerpMarketAssetGuard.sol";
import {Governance} from "contracts/Governance.sol";
import {PoolFactory} from "contracts/PoolFactory.sol";
import {GmxTestSharedData} from "test/integration/arbitrum/gmx/GmxTestSharedData.sol";
import {AssetHandler} from "contracts/priceAggregators/AssetHandler.sol";
import {console} from "forge-std/console.sol";

contract GmxTestDryRunArbitrum is DeploymentDryRunArbitrum, IntegrationDeployer {
  constructor() DeploymentDryRunArbitrum(GmxTestSharedData.FORK_BLOCK_NUMBER, getTorosVaults()) {}

  function setUp() public override {
    super.setUp();

    this.deployIntegration(poolFactory, nftTracker, slippageAccumulator, usdPriceAggregator);
  }

  function getTorosVaults() internal pure returns (address[] memory torosVaults) {
    torosVaults = new address[](49);

    torosVaults[0] = ArbitrumConfig.ETHBULL3X;
    torosVaults[1] = ArbitrumConfig.ETHBULL2X;
    torosVaults[2] = ArbitrumConfig.ETHBEAR1X;
    torosVaults[3] = ArbitrumConfig.SOLBULL3X;
    torosVaults[4] = ArbitrumConfig.SOLBULL2X;
    torosVaults[5] = ArbitrumConfig.SOLBEAR1X;
    torosVaults[6] = ArbitrumConfig.USDy;
    torosVaults[7] = ArbitrumConfig.ETHy;
    torosVaults[8] = ArbitrumConfig.ETHBULL4X;
    torosVaults[9] = ArbitrumConfig.BTCBULL4X;
    torosVaults[10] = ArbitrumConfig.BTCy;
    torosVaults[11] = ArbitrumConfig.SOL1X;
    torosVaults[12] = ArbitrumConfig.DOGEBULL2X;
    torosVaults[13] = ArbitrumConfig.DOGE1X;
    torosVaults[14] = ArbitrumConfig.XRP1X;
    torosVaults[15] = ArbitrumConfig.BTCBULL3X;
    torosVaults[16] = ArbitrumConfig.BTCBULL2X;
    torosVaults[17] = ArbitrumConfig.BTCBEAR1X;
    torosVaults[18] = ArbitrumConfig.CRV1X;
    torosVaults[19] = ArbitrumConfig.CRVBULL2X;
    torosVaults[20] = ArbitrumConfig.HYPE1X;
    torosVaults[21] = ArbitrumConfig.XRPBULL2X;
    torosVaults[22] = ArbitrumConfig.BNB1X;
    torosVaults[23] = ArbitrumConfig.LINKBULL2X;
    torosVaults[24] = ArbitrumConfig.LINK1X;
    torosVaults[25] = ArbitrumConfig.SUIBULL2X;
    torosVaults[26] = ArbitrumConfig.SUI1X;
    torosVaults[27] = ArbitrumConfig.HYPEBULL2X;
    torosVaults[28] = ArbitrumConfig.PUMP1X;
    torosVaults[29] = ArbitrumConfig.PUMPBULL2X;
    torosVaults[30] = ArbitrumConfig.BNBBULL2X;
    torosVaults[31] = ArbitrumConfig.XRPBEAR1X;
    torosVaults[32] = ArbitrumConfig.BNBBEAR1X;
    torosVaults[33] = ArbitrumConfig.DOGEBEAR1X;
    torosVaults[34] = ArbitrumConfig.LINKBEAR1X;
    torosVaults[35] = ArbitrumConfig.HYPEBEAR1X;
    torosVaults[36] = ArbitrumConfig.SUIBEAR1X;
    torosVaults[37] = ArbitrumConfig.PUMPBEAR1X;
    torosVaults[38] = ArbitrumConfig.CRVBEAR1X;
    torosVaults[39] = ArbitrumConfig.ETHBEAR2X;
    torosVaults[40] = ArbitrumConfig.BTCBEAR2X;
    torosVaults[41] = ArbitrumConfig.SUIBULL3X;
    torosVaults[42] = ArbitrumConfig.XRPBULL3X;
    torosVaults[43] = ArbitrumConfig.GOLDBULL3X;
    torosVaults[44] = ArbitrumConfig.GOLDBULL2X;
    torosVaults[45] = ArbitrumConfig.GOLD1X;
    torosVaults[46] = ArbitrumConfig.GOLDBEAR1X;
    torosVaults[47] = ArbitrumConfig.AAVEBEAR1X;
    torosVaults[48] = ArbitrumConfig.AAVEBULL2X;

    return torosVaults;
  }

  function deployIntegration(
    PoolFactory _poolFactory,
    address _nftTracker,
    address _slippageAccumulator,
    address /* _usdPriceAggregator */
  ) external override {
    Governance governance = Governance(_poolFactory.governanceAddress());
    AssetHandler assetHandler = AssetHandler(_poolFactory.getAssetHandler());

    vm.startPrank(_poolFactory.owner());

    address latestPoolLogic = address(new PoolLogic());
    address latestPoolManagerLogic = address(new PoolManagerLogic());
    address latestPoolFactory = address(new PoolFactory());
    proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(_poolFactory))), latestPoolFactory);
    _poolFactory.setLogic(latestPoolLogic, latestPoolManagerLogic);

    GmxExchangeRouterContractGuard gmxExchangeRouterContractGuard = new GmxExchangeRouterContractGuard(
      GmxTestSharedData.getGmxContractGuardConfig(),
      GmxTestSharedData.getDHedgeVaultsWhitelist(),
      GmxTestSharedData.getVirtualTokenResolver(),
      _slippageAccumulator,
      _nftTracker
    );

    governance.setContractGuard(GmxTestSharedData.GMX_EXCHANGE_ROUTER, address(gmxExchangeRouterContractGuard));

    GmxPerpMarketAssetGuard gmxAssetGuard = new GmxPerpMarketAssetGuard(GmxTestSharedData.GMX_EXCHANGE_ROUTER);
    governance.setAssetGuard(GmxTestSharedData.GMX_PEPRS_MARKET_ASSET_TYPE, address(gmxAssetGuard));

    AssetHandler.Asset[] memory assets = GmxTestSharedData.getAdditonalAssetSetupData();
    assetHandler.addAssets(assets);
    vm.stopPrank();
  }

  function _formatDecimals(uint256 value, uint256 decimals) internal pure returns (string memory) {
    string memory s = vm.toString(value);
    while (bytes(s).length < decimals) {
      s = string(abi.encodePacked("0", s));
    }
    return s;
  }

  function test_token_prices_should_stay_same_after_new_deployment() public view override {
    uint256 toleranceBps = 150; // 150 bps = 1.5%
    for (uint256 i; i < torosVaultsToCheck.length; ++i) {
      uint256 beforePrice = tokenPricesBeforeTheUpgrade[i];
      uint256 afterPrice = PoolLogic(torosVaultsToCheck[i]).tokenPrice();

      uint256 diff = beforePrice > afterPrice ? beforePrice - afterPrice : afterPrice - beforePrice;

      uint256 maxAllowedDiff = (beforePrice * toleranceBps) / 10_000;

      // diff scaled to 0.0001% precision (4 decimals)
      uint256 diffScaled = (diff * 1_000_000) / beforePrice;

      // query ERC20 symbol
      string memory symbol = PoolLogic(torosVaultsToCheck[i]).symbol();

      if (toleranceBps > 0) {
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
              ", Diff: ",
              _formatDecimals(diff, 18),
              "  (",
              symbol,
              ")  "
            )
          )
        );
      }

      assertGe(
        maxAllowedDiff,
        diff,
        string(
          abi.encodePacked("tokenPrice allowed diff out of bounds for vault: ", _addressToString(torosVaultsToCheck[i]))
        )
      );
    }
  }
}
