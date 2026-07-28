// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;

/// @notice Single source of truth for dHEDGE asset type indices.
/// @dev Inheriting from this contract (rather than defining the enum inline) keeps the
///      numeric values consistent across all test setups.
abstract contract AssetTypes {
  enum AssetTypeIncomplete {
    CHAINLINK, // 0
    SNX_SYNTH, // 1
    SUSHI_LP, // 2
    AAVE_V2, // 3
    LENDING_ENABLED, // 4
    QUICK_LP, // 5
    BALANCER_LP, // 6
    UNISWAP_V3, // 7
    AAVE_V3, // 8
    ARRAKIS_GAUGE, // 9
    BALANCER_V2_GAUGE, // 10
    NOT_ASSIGNED_0, // 11
    NOT_ASSIGNED_1, // 12
    NOT_ASSIGNED_2, // 13
    SNX_SYNTH_LENDING_ENABLED, // 14
    VELODROME_LP, // 15
    STARGATE_LP, // 16
    MAI_VAULT, // 17
    NOT_ASSIGNED_3, // 18
    NOT_ASSIGNED_4, // 19
    RAMSES_LP, // 20
    FLAT_MONEY_UNIT, // 21
    FLAT_MONEY_COLLATERAL, // 22
    NOT_ASSGIGNED_5, // 23
    NOT_ASSIGNED_6, // 24
    VELODROME_V2_LP, // 25
    VELODROME_CL, // 26
    FLAT_MONEY_LEVERAGE, // 27
    COMPOUND_V3_COMET, // 28
    RAMSES_CL, // 29
    EASYSWAPPER_V2_UNROLLED, // 30
    PANCAKE_CL, // 31
    FLAT_MONEY_OPTIONS_MARKET, // 32
    FLAT_MONEY_COLLATERAL_LENDING_ENABLED, // 33
    FLUID_TOKEN, // 34
    FLAT_MONEY_V2_UNIT, // 35
    FLAT_MONEY_V2_PERP_MARKET, // 36
    PENDLE_PRINCIPAL_TOKEN, // 37
    VIRTUAL_TOKEN, // 38
    HYPERLIQUID_PERPS_ASSET, // 39
    HYPERLIQUID_SPOT, // 40
    ONDO_GM_TOKEN, // 41
    MIDAS_MTOKEN, // 42
    MIDAS_PENDING_REDEMPTION // 43
  }
}
