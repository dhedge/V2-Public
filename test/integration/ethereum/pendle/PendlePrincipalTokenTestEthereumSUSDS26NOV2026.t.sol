// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {PendlePrincipalTokenTestSetup} from "test/integration/common/pendle/PendlePrincipalTokenTestSetup.t.sol";
import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";

interface IPendleChainlinkOracleFactory {
  function createOracle(address market, uint32 twapDuration, uint8 baseOracleType) external returns (address);
}

contract PendlePrincipalTokenTestEthereumSUSDS26NOV2026 is PendlePrincipalTokenTestSetup, EthereumSetup {
  uint32 private constant PENDLE_ORACLE_TWAP_DURATION = 1800;
  uint8 private constant PENDLE_ORACLE_PT_TO_SY = 0;

  constructor()
    PendlePrincipalTokenTestSetup(
      EthereumConfig.PENDLE_ROUTER_V4,
      EthereumConfig.sUSDS,
      EthereumConfig.USDS_CHAINLINK_ORACLE, // feed of the ERC4626 underlying (USDS), see _underlyingYieldTokenAggregator
      EthereumConfig.PENDLE_MARKET_sUSDS_NOV_2026,
      address(0) // no PendleChainlinkOracle exists onchain for the market, see _createPendleChainlinkOracle
    )
    EthereumSetup(25674308)
  {}

  function setUp() public override(PendlePrincipalTokenTestSetup, EthereumSetup) {
    super.setUp();
  }

  /// @dev Mirrors what the deployment does when no PT_TO_SY oracle exists for the market yet
  function _createPendleChainlinkOracle() internal override returns (address) {
    return
      IPendleChainlinkOracleFactory(EthereumConfig.PENDLE_CHAINLINK_ORACLE_FACTORY).createOracle(
        EthereumConfig.PENDLE_MARKET_sUSDS_NOV_2026,
        PENDLE_ORACLE_TWAP_DURATION,
        PENDLE_ORACLE_PT_TO_SY
      );
  }

  /// @dev sUSDS has no USD chainlink feed onchain; price it as ERC4626 over USDS, mirroring production config
  function _underlyingYieldTokenAggregator(IAssetHandler _assetHandler) internal override returns (address) {
    IAssetHandler.Asset[] memory assets = new IAssetHandler.Asset[](1);
    assets[0] = IAssetHandler.Asset({
      asset: EthereumConfig.USDS,
      assetType: uint16(AssetTypeIncomplete.CHAINLINK),
      aggregator: underlyingYieldTokenPriceFeed
    });
    _assetHandler.addAssets(assets);

    return deployCode("ERC4626PriceAggregator.sol", abi.encode(EthereumConfig.sUSDS, address(_assetHandler)));
  }
}
