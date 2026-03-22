// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CowSwapOrderTypeHashLib} from "contracts/validators/cowSwap/CowSwapOrderTypeHashLib.sol";
import {BaseConfig} from "test/integration/utils/foundry/config/BaseConfig.sol";
import {Surl} from "test/integration/utils/foundry/scripts/Surl.sol";

/// @notice Validates that our CowSwapOrderTypeHashLib computes the same EIP-712 hash as CoWSwap API
contract CowSwapHashValidationTestFFIBase is Test {
  using Surl for string;

  /// @dev CoWSwap API endpoint for Base chain
  string public constant COWSWAP_API_BASE = "https://api.cow.fi/base/api/v1";

  /// @dev Order UID length: orderDigest (32) + owner (20) + validTo (4) = 56 bytes
  uint256 private constant ORDER_UID_LENGTH = 56;

  function setUp() public {
    vm.createSelectFork("base");
  }

  /// @notice Test that our hash computation matches CoWSwap API's hash
  /// @dev Submits an order to CoWSwap API and verifies our computed hash matches
  function test_hash_computation_matches_cowswap_api() public {
    // Build typed data using the real structs from CowSwapOrderTypeHashLib
    address orderOwner = makeAddr("orderOwner");
    uint32 validTo = uint32(block.timestamp + 1 hours);

    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData = _buildTypedData(orderOwner, validTo);

    // Step 1: Compute hash using CowSwapOrderTypeHashLib.getDigest()
    bytes32 localHash = CowSwapOrderTypeHashLib.getDigest(typedData);

    // Step 2: Build JSON payload and submit to CoWSwap API
    (uint256 status, bytes memory response) = _submitOrderToApi(typedData, orderOwner);

    // Step 3: Validate the hash
    _validateHashResponse(status, response, localHash);
  }

  // ============ Helper Functions ============

  /// @dev Build typed data for testing
  function _buildTypedData(
    address orderOwner,
    uint32 validTo
  ) internal pure returns (CowSwapOrderTypeHashLib.CowSwapTypedData memory) {
    return
      CowSwapOrderTypeHashLib.CowSwapTypedData({
        domain: CowSwapOrderTypeHashLib.EIP712Domain({
          name: "Gnosis Protocol",
          version: "v2",
          chainId: BaseConfig.CHAIN_ID,
          verifyingContract: BaseConfig.GPV2_SETTLEMENT
        }),
        order: CowSwapOrderTypeHashLib.GPv2Order({
          sellToken: BaseConfig.USDC,
          buyToken: BaseConfig.WETH,
          receiver: orderOwner, // receiver = owner
          sellAmount: 1000e6, // 1000 USDC
          buyAmount: 0.4 ether, // 0.4 WETH
          validTo: validTo,
          appData: bytes32(0),
          feeAmount: 0,
          kind: CowSwapOrderTypeHashLib.KIND_SELL,
          partiallyFillable: false,
          sellTokenBalance: CowSwapOrderTypeHashLib.BALANCE_ERC20,
          buyTokenBalance: CowSwapOrderTypeHashLib.BALANCE_ERC20
        })
      });
  }

  /// @dev Submit order to CoWSwap API using Surl
  function _submitOrderToApi(
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData,
    address from
  ) internal returns (uint256 status, bytes memory response) {
    string memory orderJson = _buildOrderJson(typedData, from);
    string memory url = string.concat(COWSWAP_API_BASE, "/orders");

    string[] memory headers = new string[](1);
    headers[0] = "Content-Type: application/json";

    return url.post(headers, orderJson);
  }

  /// @dev Validate hash from API response
  function _validateHashResponse(uint256 status, bytes memory response, bytes32 localHash) internal pure {
    if (status == 201) {
      // Response is the orderUid as a hex string
      bytes memory orderUid = _hexStringToBytes(string(response));
      require(orderUid.length == ORDER_UID_LENGTH, "Invalid orderUid length");

      // Extract orderDigest from orderUid (first 32 bytes)
      bytes32 apiHash;
      assembly {
        apiHash := mload(add(orderUid, 32))
      }

      assertEq(localHash, apiHash, "Local hash should match API hash");
    } else {
      revert(string.concat("CoWSwap API returned non-201 status: ", string(response)));
    }
  }

  /// @dev Build JSON payload for CoWSwap order API
  function _buildOrderJson(
    CowSwapOrderTypeHashLib.CowSwapTypedData memory typedData,
    address from
  ) internal pure returns (string memory) {
    CowSwapOrderTypeHashLib.GPv2Order memory order = typedData.order;

    string memory part1 = string.concat(
      '{"sellToken":"',
      _addressToHexString(order.sellToken),
      '","buyToken":"',
      _addressToHexString(order.buyToken),
      '","receiver":"',
      _addressToHexString(order.receiver),
      '","sellAmount":"',
      vm.toString(order.sellAmount)
    );

    string memory part2 = string.concat(
      '","buyAmount":"',
      vm.toString(order.buyAmount),
      '","validTo":',
      vm.toString(uint256(order.validTo)),
      ',"appData":"',
      _bytes32ToHexString(order.appData),
      '","feeAmount":"',
      vm.toString(order.feeAmount)
    );

    string memory kind = order.kind == CowSwapOrderTypeHashLib.KIND_SELL ? "sell" : "buy";

    string memory part3 = string.concat(
      '","kind":"',
      kind,
      '","partiallyFillable":',
      order.partiallyFillable ? "true" : "false",
      ',"sellTokenBalance":"erc20","buyTokenBalance":"erc20"',
      ',"signingScheme":"presign","signature":"0x","from":"',
      _addressToHexString(from),
      '"}'
    );

    return string.concat(part1, part2, part3);
  }

  /// @dev Convert address to hex string
  function _addressToHexString(address addr) internal pure returns (string memory) {
    bytes memory alphabet = "0123456789abcdef";
    bytes20 value = bytes20(addr);
    bytes memory str = new bytes(42);
    str[0] = "0";
    str[1] = "x";
    for (uint256 i = 0; i < 20; i++) {
      str[2 + i * 2] = alphabet[uint8(value[i] >> 4)];
      str[3 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
    }
    return string(str);
  }

  /// @dev Convert bytes32 to hex string
  function _bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
    bytes memory alphabet = "0123456789abcdef";
    bytes memory str = new bytes(66);
    str[0] = "0";
    str[1] = "x";
    for (uint256 i = 0; i < 32; i++) {
      str[2 + i * 2] = alphabet[uint8(value[i] >> 4)];
      str[3 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
    }
    return string(str);
  }

  /// @dev Convert hex string to bytes (simplified, assumes valid input)
  function _hexStringToBytes(string memory s) internal pure returns (bytes memory) {
    bytes memory ss = bytes(s);
    // Remove quotes if present
    uint256 start = 0;
    uint256 end = ss.length;
    if (ss.length > 0 && ss[0] == '"') start = 1;
    if (ss.length > 1 && ss[ss.length - 1] == '"') end = ss.length - 1;
    // Remove 0x prefix if present
    if (end - start >= 2 && ss[start] == "0" && (ss[start + 1] == "x" || ss[start + 1] == "X")) {
      start += 2;
    }

    require((end - start) % 2 == 0, "Invalid hex string length");
    bytes memory result = new bytes((end - start) / 2);

    for (uint256 i = 0; i < result.length; i++) {
      result[i] = bytes1(
        uint8(_hexCharToUint8(ss[start + i * 2])) * 16 + uint8(_hexCharToUint8(ss[start + i * 2 + 1]))
      );
    }
    return result;
  }

  function _hexCharToUint8(bytes1 c) internal pure returns (uint8) {
    if (c >= "0" && c <= "9") return uint8(c) - 48;
    if (c >= "a" && c <= "f") return uint8(c) - 87;
    if (c >= "A" && c <= "F") return uint8(c) - 55;
    revert("Invalid hex char");
  }
}
