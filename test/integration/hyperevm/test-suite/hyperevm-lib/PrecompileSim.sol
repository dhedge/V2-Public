// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9.0;

import {HyperCore} from "./HyperCore.sol";
import {HLConstants} from "./lib/HLConstants.sol";

import {Vm} from "forge-std/Vm.sol";

/// @dev this contract is deployed for each different precompile address such that the fallback can be executed for each
contract PrecompileSim {
  Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
  HyperCore internal constant _hyperCore = HyperCore(payable(0x9999999999999999999999999999999999999999));

  receive() external payable {}

  // solhint-disable-next-line no-complex-fallback
  fallback(bytes calldata data) external returns (bytes memory) {
    if (address(this) == HLConstants.SPOT_BALANCE_PRECOMPILE_ADDRESS) {
      (address user, uint64 token) = abi.decode(data, (address, uint64));
      return abi.encode(_hyperCore.readSpotBalance(user, token));
    }

    if (address(this) == HLConstants.VAULT_EQUITY_PRECOMPILE_ADDRESS) {
      (address user, address vault) = abi.decode(data, (address, address));
      return abi.encode(_hyperCore.readUserVaultEquity(user, vault));
    }

    if (address(this) == HLConstants.WITHDRAWABLE_PRECOMPILE_ADDRESS) {
      address user = abi.decode(data, (address));
      return abi.encode(_hyperCore.readWithdrawable(user));
    }

    if (address(this) == HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS) {
      address user = abi.decode(data, (address));
      return abi.encode(_hyperCore.readDelegations(user));
    }

    if (address(this) == HLConstants.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS) {
      address user = abi.decode(data, (address));
      return abi.encode(_hyperCore.readDelegatorSummary(user));
    }

    if (address(this) == HLConstants.POSITION_PRECOMPILE_ADDRESS) {
      (address user, uint16 perp) = abi.decode(data, (address, uint16));
      return abi.encode(_hyperCore.readPosition(user, perp));
    }

    if (address(this) == HLConstants.CORE_USER_EXISTS_PRECOMPILE_ADDRESS) {
      address user = abi.decode(data, (address));
      return abi.encode(_hyperCore.coreUserExists(user));
    }

    if (address(this) == HLConstants.MARK_PX_PRECOMPILE_ADDRESS) {
      uint32 perp = abi.decode(data, (uint32));
      return abi.encode(_hyperCore.readMarkPx(perp));
    }

    if (address(this) == HLConstants.ORACLE_PX_PRECOMPILE_ADDRESS) {
      uint32 perp = abi.decode(data, (uint32));
      return abi.encode(_hyperCore.readOraclePx(perp));
    }

    if (address(this) == HLConstants.SPOT_PX_PRECOMPILE_ADDRESS) {
      uint64 spotIndex = abi.decode(data, (uint64));
      return abi.encode(_hyperCore.readSpotPx(uint32(spotIndex)));
    }
    if (address(this) == HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS) {
      uint32 perp = abi.decode(data, (uint32));
      return abi.encode(_hyperCore.readPerpAssetInfo(perp));
    }

    if (address(this) == HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS) {
      uint32 spotMarketId = abi.decode(data, (uint32));
      return abi.encode(_hyperCore.readSpotInfo(spotMarketId));
    }

    if (address(this) == HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS) {
      uint32 token = abi.decode(data, (uint32));
      return abi.encode(_hyperCore.readTokenInfo(token));
    }

    if (address(this) == HLConstants.ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS) {
      (uint16 perp_dex_index, address user) = abi.decode(data, (uint16, address));
      return abi.encode(_hyperCore.readAccountMarginSummary(perp_dex_index, user));
    }

    return _makeRpcCall(address(this), data);
  }

  function _makeRpcCall(address target, bytes memory params) internal returns (bytes memory) {
    // Construct the JSON-RPC payload
    string memory jsonPayload = string.concat(
      '[{"to":"',
      vm.toString(target),
      '","data":"',
      vm.toString(params),
      '"},"latest"]'
    );

    // Make the RPC call
    return vm.rpc("eth_call", jsonPayload);
  }
}
