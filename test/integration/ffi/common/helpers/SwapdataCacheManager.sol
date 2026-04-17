// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {Test} from "forge-std/Test.sol";

import {Surl} from "test/integration/utils/foundry/scripts/Surl.sol";

contract SwapdataCacheManager is Test {
  using Surl for string;

  bool internal useCachedSwapData;
  string public constant CACHE_DIRECTORY_PATH = "swapdatas-cache/odos-v2/";

  // APIs related constants
  uint8 public constant RETRIES = 10;
  uint16 public constant DEFAULT_HALT_MILLISECONDS = 2000;

  function __SwapdataCacheManager_init(bool useCachedSwapData_) public {
    useCachedSwapData = useCachedSwapData_;

    if (!useCachedSwapData_) {
      return;
    }

    // Create a directory if it doesn't exist.
    if (!vm.isDir(CACHE_DIRECTORY_PATH)) {
      vm.createDir(CACHE_DIRECTORY_PATH, true);
    }

    string memory cacheFilePath = _getCacheFilePath();

    // Initialize the cache file if it doesn't exist
    if (!vm.isFile(cacheFilePath)) {
      _initializeCacheFile(cacheFilePath);
    }
  }

  function _initializeCacheFile(string memory cacheFilePath) private {
    string memory emptyObj = "{}";
    vm.writeFile(cacheFilePath, emptyObj);
  }

  function _appendNewObj(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    uint8 slippage,
    uint256 destAmount,
    address user,
    bool compact,
    bytes memory swapData
  ) internal {
    uint256 forkBlockNumber = vm.getBlockNumber();
    string memory forkBlockKey = vm.toString(forkBlockNumber);
    string memory swapKey = _getKey(srcToken, destToken, srcAmount, user, slippage, compact);
    string memory swapObj = _getObjToAppend(srcToken, destToken, srcAmount, destAmount, user, swapData);
    string memory filePath = _getCacheFilePath();

    // Use a simple flat structure: "forkBlock_swapKey" -> swapData
    // This avoids the complex JSON merging issues
    string memory rootKey = "root";
    string memory flatKey = string(abi.encodePacked(forkBlockKey, "_", swapKey));

    // Read existing cache if file exists to preserve other entries
    if (vm.isFile(filePath)) {
      string memory cacheJson = vm.readFile(filePath);
      if (bytes(cacheJson).length > 2) {
        // More than just "{}"
        vm.serializeJson(rootKey, cacheJson);
      }
    }

    // Add the new entry
    string memory finalJson = vm.serializeString(rootKey, flatKey, swapObj);

    vm.writeFile(filePath, finalJson);
  }

  function _getObjToAppend(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    uint256 destAmount,
    address user,
    bytes memory swapData
  ) private returns (string memory obj) {
    string memory newKey = "new-key";

    vm.serializeAddress(newKey, "srcToken", address(srcToken));
    vm.serializeAddress(newKey, "destToken", address(destToken));
    vm.serializeUint(newKey, "srcAmount", srcAmount);
    vm.serializeUint(newKey, "destAmount", destAmount);
    vm.serializeAddress(newKey, "user", address(user));
    string memory finalOutput = vm.serializeBytes(newKey, "swapData", swapData);

    return finalOutput;
  }

  function _checkAndGetSwapDatas(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    address user,
    uint8 slippage,
    bool compact
  ) internal view returns (bool exists, uint256 destAmount, bytes memory swapData) {
    uint256 forkBlockNumber = vm.getBlockNumber();
    string memory forkBlockKey = vm.toString(forkBlockNumber);
    string memory swapKey = _getKey(srcToken, destToken, srcAmount, user, slippage, compact);
    string memory cacheJson = _getCacheJson();

    // Use the same flat structure: "forkBlock_swapKey"
    string memory flatKey = string(abi.encodePacked(forkBlockKey, "_", swapKey));
    string memory fullPath = string(abi.encodePacked(".", flatKey));

    exists = vm.keyExistsJson(cacheJson, fullPath);

    if (exists) {
      destAmount = vm.parseJsonUint(cacheJson, string(abi.encodePacked(fullPath, ".destAmount")));
      swapData = vm.parseJsonBytes(cacheJson, string(abi.encodePacked(fullPath, ".swapData")));
    }
  }

  function _getCacheJson() internal view returns (string memory json) {
    string memory filePath = _getCacheFilePath();

    return vm.readFile(filePath);
  }

  function _getKey(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    address user,
    uint8 slippage,
    bool compact
  ) internal pure returns (string memory key) {
    return vm.toString(keccak256(abi.encodePacked(srcToken, destToken, srcAmount, user, slippage, compact)));
  }

  function _getChainId() private view returns (uint256 chainId) {
    assembly {
      chainId := chainid()
    }
  }

  function _getCacheFilePath() internal view returns (string memory filePath) {
    return string(abi.encodePacked(CACHE_DIRECTORY_PATH, vm.toString(_getChainId()), ".json"));
  }

  function _getAndRetry(
    string memory url,
    string[] memory headers
  ) internal returns (uint256 status, bytes memory data) {
    for (uint8 i; i < RETRIES; i++) {
      (status, data) = url.get(headers);
      if (status != 200) {
        vm.sleep(DEFAULT_HALT_MILLISECONDS * i); // Halts execution for 2 seconds the first time and increases by 2 seconds each time for `i` retries.
      } else {
        break;
      }
    }
  }

  function _postAndRetry(
    string memory url,
    string[] memory headers,
    string memory body
  ) internal returns (uint256 status, bytes memory data) {
    for (uint8 i; i < RETRIES; i++) {
      (status, data) = url.post(headers, body);
      if (status != 200) {
        vm.sleep(DEFAULT_HALT_MILLISECONDS * i); // Halts execution for 2 seconds the first time and increases by 2 seconds each time for `i` retries.
      } else {
        break;
      }
    }
  }
}
