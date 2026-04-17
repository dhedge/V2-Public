// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ITokenRegistry} from "../../interfaces/hyperliquid/ITokenRegistry.sol";

/// @title PrecompileHelper
/// @notice Hyperliquid Precompile helper functions.
/// @author dHEDGE DAO
abstract contract PrecompileHelper {
  /////////////////////////////////////////////
  //             Enums & Structs             //
  /////////////////////////////////////////////

  // Time-in-force order types
  enum OrderType {
    INVALID,
    ALO,
    GTC,
    IOC
  }

  struct SpotBalance {
    uint64 total;
    uint64 hold;
    uint64 entryNtl;
  }

  struct TokenInfo {
    string name;
    uint64[] spots;
    uint64 deployerTradingFeeShare;
    address deployer;
    address evmContract;
    uint8 szDecimals;
    uint8 weiDecimals;
    int8 evmExtraWeiDecimals;
  }

  /// @param accountValue The total value of the account (margin + unrealised pnl + funding in USD with 6 decimals).
  /// @param marginUsed The total margin used by all positions (in USD with 6 decimals).
  /// @param ntlPos The notional size of all positions (in USD with 6 decimals).
  struct AccountMarginSummary {
    int64 accountValue;
    uint64 marginUsed;
    uint64 ntlPos;
    int64 rawUsd;
  }

  /* Param structs */

  struct LimitOrderParams {
    uint32 asset;
    bool isBuy;
    uint64 limitPx;
    uint64 sz;
    bool reduceOnly;
    uint8 encodedTif;
    uint128 cloid;
  }

  struct SpotSendParams {
    address destinationAddress;
    uint64 token;
    uint64 amount;
  }

  struct SendAssetParams {
    address destinationAddress;
    address subAccountAddress;
    uint32 sourceDexId;
    uint32 destinationDexId;
    uint64 token;
    uint64 amount;
  }

  struct PerpAssetInfo {
    string coin;
    uint32 marginTableId;
    uint8 szDecimals;
    uint8 maxLeverage;
    bool onlyIsolated;
  }

  struct SpotInfo {
    string name;
    uint64[2] tokens;
  }

  struct CoreUserExists {
    bool exists;
  }

  /////////////////////////////////////////////
  //             Custom Errors              //
  /////////////////////////////////////////////

  error PrecompileHelper__L1BlockNumberFetchFailed();
  error PrecompileHelper__CoreUserExistsPrecompileFailed();
  error PrecompileHelper__TokenInfoFetchFailed(uint64 token);
  error PrecompileHelper__SpotIndexNotFound(uint64 tokenIndex);
  error PrecompileHelper__SpotPxPrecompileFailed(uint64 spotIndex);
  error PrecompileHelper__SpotInfoPrecompileFailed(uint64 spotIndex);
  error PrecompileHelper__OraclePxPrecompileFailed(uint32 perpIndex);
  error PrecompileHelper__SummaryFetchFailed(address user, uint256 dexId);
  error PrecompileHelper__PerpAssetInfoPrecompileFailed(uint32 perpIndex);
  error PrecompileHelper__SpotBalanceFetchFailed(address user, uint64 token);

  /////////////////////////////////////////////
  //                  State                  //
  /////////////////////////////////////////////

  /// @notice Onchain token registry contract by Obsidian
  ITokenRegistry public constant TOKEN_REGISTRY = ITokenRegistry(0x0b51d1A9098cf8a72C325003F44C194D41d7A85B);

  // System addresses
  uint24 internal constant _MAINNET_HYPE_TOKEN_INDEX = 150;
  uint24 internal constant _TESTNET_HYPE_TOKEN_INDEX = 1105;
  address internal constant _HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;
  uint160 internal constant _BASE_SYSTEM_ADDRESS = uint160(0x2000000000000000000000000000000000000000);
  address internal constant _CORE_WRITER = 0x3333333333333333333333333333333333333333;

  // Precompile addresses
  address internal constant _SPOT_BALANCE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000801;
  address internal constant _POSITION_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;
  address internal constant _PERP_ASSET_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080a;
  address internal constant _TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;
  address internal constant _ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080F;
  address internal constant _L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;
  address internal constant _ORACLE_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000807;
  address internal constant _SPOT_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;
  address internal constant _SPOT_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080b;
  address internal constant _CORE_USER_EXISTS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000810;

  // USDC related information

  /// @dev Fetched from the CoreDepositWallet contract by calling `token()`.
  address internal constant _USDC_ADDRESS = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

  /// @dev Fetched from <https://developers.circle.com/cctp/references/hypercore-contract-addresses#coredepositwallet:-mainnet>
  address internal constant _CORE_DEPOSIT_WALLET = 0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24;

  /// @dev USDC token index on Hyperliquid mainnet.
  uint64 internal constant _USDC_TOKEN_INDEX = 0;

  // Important dex IDs
  uint32 internal constant _DEX_ID_CORE_SPOT = type(uint32).max;
  uint32 internal constant _DEX_ID_CORE_PERP = 0;

  ///////////////////////////////////////////////
  //             Helper Functions              //
  ///////////////////////////////////////////////

  /// @notice Checks if a HyperCore account has been activated or not.
  /// @param user The address of the HyperCore account.
  /// @return exists `true` if the account exists (activated), `false` otherwise.
  function coreUserExists(address user) internal view returns (bool) {
    (bool success, bytes memory result) = _CORE_USER_EXISTS_PRECOMPILE_ADDRESS.staticcall(abi.encode(user));

    if (!success) revert PrecompileHelper__CoreUserExistsPrecompileFailed();

    return abi.decode(result, (CoreUserExists)).exists;
  }

  /// @notice Fetches the account margin summary of a Hyperliquid perps account.
  /// @param user Address of the Hyperliquid perps account.
  /// @param dexId The dex ID of the Hyperliquid perps account.
  /// @return summary Account margin summary of the Hyperliquid perps account.
  function accountMarginSummary(address user, uint256 dexId) public view returns (AccountMarginSummary memory) {
    (bool success, bytes memory result) = _ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS.staticcall(
      abi.encode(dexId, user)
    );

    if (!success) revert PrecompileHelper__SummaryFetchFailed(user, dexId);

    return abi.decode(result, (AccountMarginSummary));
  }

  /// @notice Fetches spot balance information from the `SPOT_BALANCE_PRECOMPILE_ADDRESS`.
  /// @dev The amounts returned are in the `token`'s `weiDecimals` format.
  ///      This can be different from the corresponding EVM token's decimals.
  /// @param user The user address.
  /// @param token The token index.
  /// @return balance The spot balance information.
  function spotBalance(address user, uint64 token) internal view returns (SpotBalance memory) {
    (bool success, bytes memory result) = _SPOT_BALANCE_PRECOMPILE_ADDRESS.staticcall(abi.encode(user, token));

    if (!success) revert PrecompileHelper__SpotBalanceFetchFailed(user, token);

    return abi.decode(result, (SpotBalance));
  }

  /// @notice Fetches spot asset information from the `SPOT_INFO_PRECOMPILE_ADDRESS`.
  /// @param index The spot token index.
  /// @return info The spot asset information.
  function spotInfo(uint64 index) internal view returns (SpotInfo memory) {
    (bool success, bytes memory result) = _SPOT_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
    if (!success) revert PrecompileHelper__SpotInfoPrecompileFailed(index);
    return abi.decode(result, (SpotInfo));
  }

  /// @notice Fetches perp asset information from the `PERP_ASSET_INFO_PRECOMPILE_ADDRESS`.
  /// @param perp The perp asset index.
  /// @return info The perp asset information.
  function perpAssetInfo(uint32 perp) internal view returns (PerpAssetInfo memory) {
    (bool success, bytes memory result) = _PERP_ASSET_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(perp));
    if (!success) revert PrecompileHelper__PerpAssetInfoPrecompileFailed(perp);
    return abi.decode(result, (PerpAssetInfo));
  }

  /// @notice Fetches token information from the `TOKEN_INFO_PRECOMPILE_ADDRESS`.
  /// @param index The token index.
  /// @return info The token information.
  function tokenInfo(uint64 index) internal view returns (TokenInfo memory) {
    (bool success, bytes memory result) = _TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));

    if (!success) revert PrecompileHelper__TokenInfoFetchFailed(index);

    return abi.decode(result, (TokenInfo));
  }

  /// @notice Checks if a token index exists by calling the `TOKEN_INFO_PRECOMPILE_ADDRESS`.
  /// @dev Assumes that if the call reverts, the token does not exist and vice-versa.
  /// @param token The token index.
  /// @return exists `true` if the token exists, `false` otherwise.
  function tokenExists(uint64 token) internal view returns (bool) {
    (bool success, ) = _TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(token));
    return success;
  }

  /// @notice Fetches the Hyperliquid L1 block number from the `L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS`.
  /// @return The L1 block number.
  function l1BlockNumber() internal view returns (uint64) {
    (bool success, bytes memory result) = _L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS.staticcall(abi.encode());
    if (!success) revert PrecompileHelper__L1BlockNumberFetchFailed();

    return abi.decode(result, (uint64));
  }

  /// @notice Checks if an address is a Hyperliquid system address as described in the Hyperliquid documentation.
  /// @param addr The address to check.
  /// @return isSystemAddress `true` if the address is a Hyperliquid system address, `false` otherwise.
  function isSystemAddress(address addr) internal view returns (bool) {
    // Check if it's the HYPE system address.
    if (addr == _HYPE_SYSTEM_ADDRESS) {
      return true;
    }

    // Check if it's a token system address (0x2000...0000 + index).
    uint160 baseAddr = uint160(_BASE_SYSTEM_ADDRESS);
    uint160 addrInt = uint160(addr);

    if (addrInt >= baseAddr && addrInt < baseAddr + 10_000) {
      uint64 tokenIndex = uint64(addrInt - baseAddr);

      return tokenExists(tokenIndex);
    }

    return false;
  }

  /// @notice Get the token index for a given Hyperliquid system address.
  /// @dev [!WARNING] Does not check if the system address is valid.
  /// @param systemAddr The Hyperliquid system address.
  /// @return tokenIndex The token index corresponding to the system address.
  function getTokenIndexFromSystemAddress(address systemAddr) internal pure returns (uint64) {
    if (systemAddr == _HYPE_SYSTEM_ADDRESS) {
      return _MAINNET_HYPE_TOKEN_INDEX;
    }
    return uint64(uint160(systemAddr) - uint160(_BASE_SYSTEM_ADDRESS));
  }

  /// @notice Get the system address for a given token index.
  /// @param index The token index.
  /// @return systemAddress The system address of the token.
  function getSystemAddress(uint64 index) internal pure returns (address systemAddress) {
    if (index == _MAINNET_HYPE_TOKEN_INDEX) {
      return _HYPE_SYSTEM_ADDRESS;
    }

    return address(uint160(_BASE_SYSTEM_ADDRESS) + uint160(index));
  }

  /// @notice Get the token index for a given EVM contract address.
  /// @dev Not related to Hyperliquid Precompiles and requires TokenRegistry.
  /// @param evmContract The EVM contract address of the spot token.
  /// @return index The spot token index.
  function getTokenIndex(address evmContract) internal view returns (uint64 index) {
    index = TOKEN_REGISTRY.getTokenIndex(evmContract);
  }

  /// @notice Returns the linked EVM contract for a given spot asset's system address.
  /// @param systemAddress The system address of the spot asset.
  /// @return evmContract The linked EVM contract address of the spot asset.
  function getLinkedContract(address systemAddress) internal view returns (address evmContract) {
    return tokenInfo(getTokenIndexFromSystemAddress(systemAddress)).evmContract;
  }

  /////////////////////////////////////////////
  //          Price Helper Functions         //
  /////////////////////////////////////////////

  /// @notice Returns spot price as a fixed-point integer with 8 decimals.
  /// @param spotIndex The index of the spot asset.
  /// @return normSpotPrice The normalized spot price.
  function normalizedSpotPx(uint64 spotIndex) internal view returns (uint256) {
    SpotInfo memory info = spotInfo(spotIndex);
    uint8 baseSzDecimals = tokenInfo(info.tokens[0]).szDecimals;
    return spotPx(spotIndex) * 10 ** baseSzDecimals;
  }

  /// @notice Returns perp oracle price as a fixed-point integer with 6 decimals.
  /// @param perpIndex The index of the perp asset.
  /// @return normOraclePrice The normalized oracle price.
  function normalizedOraclePx(uint32 perpIndex) internal view returns (uint256) {
    PerpAssetInfo memory info = perpAssetInfo(perpIndex);
    return oraclePx(perpIndex) * 10 ** info.szDecimals;
  }

  /// @notice Fetches spot asset information from the `SPOT_PX_PRECOMPILE_ADDRESS`.
  /// @param spotIndex The spot index of the asset.
  /// @return spotPrice The spot price of the asset as a fixed-point integer with 8 decimals.
  function spotPx(uint64 spotIndex) internal view returns (uint64) {
    (bool success, bytes memory result) = _SPOT_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(spotIndex));
    if (!success) revert PrecompileHelper__SpotPxPrecompileFailed(spotIndex);
    return abi.decode(result, (uint64));
  }

  /// @notice Fetches oracle price for a perp from the `ORACLE_PX_PRECOMPILE_ADDRESS`.
  /// @param perpIndex The perp index of the asset.
  /// @return oraclePrice The oracle price of the asset.
  function oraclePx(uint32 perpIndex) internal view returns (uint64 oraclePrice) {
    (bool success, bytes memory result) = _ORACLE_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(perpIndex));
    if (!success) revert PrecompileHelper__OraclePxPrecompileFailed(perpIndex);
    return abi.decode(result, (uint64));
  }
}
