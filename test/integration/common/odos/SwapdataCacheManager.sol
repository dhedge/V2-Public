// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Test} from "forge-std/Test.sol";

contract SwapdataCacheManager is Test {
  bool internal useCachedSwapData;
  string public constant CACHE_DIRECTORY_PATH = "swapdatas-cache/odos-v2/";

  function __SwapdataCacheManager_init(bool useCachedSwapData_) public {
    useCachedSwapData = useCachedSwapData_;

    // If we don't want to use cached swap data or we don't want to cache swap data, return.
    // This is particularly useful for integration tests run in a CI's environment.
    if (!useCachedSwapData_) {
      return;
    }

    uint256 forkBlockNumber = vm.getBlockNumber();
    string memory cacheFilePath = getCacheFilePath();

    // Create a directory if it doesn't exist.
    if (!vm.isDir(CACHE_DIRECTORY_PATH)) {
      vm.createDir(CACHE_DIRECTORY_PATH, true);
    } else if (vm.isFile(cacheFilePath)) {
      string memory jsonFile = vm.readFile(cacheFilePath);

      // If the file exists, check if the `forkBlockNumber` in the cache is same as the current `forkBlockNumber_`
      if (
        vm.keyExistsJson(jsonFile, ".forkBlockNumber") &&
        forkBlockNumber == vm.parseJsonUint(jsonFile, ".forkBlockNumber")
      ) {
        return;
      }
    }

    // Create a JSON with block number as key.
    string memory key = "new-cache";
    string memory output = vm.serializeUint(key, "forkBlockNumber", forkBlockNumber);

    vm.writeFile(cacheFilePath, output);
  }

  function appendNewObj(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    uint8 slippage,
    uint256 destAmount,
    address user,
    bool compact,
    bytes memory swapData
  ) internal {
    string memory key = getKey(srcToken, destToken, srcAmount, user, slippage, compact);
    string memory obj = getObjToAppend(srcToken, destToken, srcAmount, destAmount, user, swapData);
    string memory cacheJson = getCacheJson();

    string memory oldKey = "old-key";
    vm.serializeJson(oldKey, cacheJson);

    string memory output = vm.serializeJson(key, obj);

    string memory newCacheJson = vm.serializeString(oldKey, key, output);
    string memory filePath = getCacheFilePath();

    vm.writeFile(filePath, newCacheJson);
  }

  function getObjToAppend(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    uint256 destAmount,
    address user,
    bytes memory swapData
  ) internal returns (string memory obj) {
    string memory newKey = "new-key";

    vm.serializeAddress(newKey, "srcToken", address(srcToken));
    vm.serializeAddress(newKey, "destToken", address(destToken));
    vm.serializeUint(newKey, "srcAmount", srcAmount);
    vm.serializeUint(newKey, "destAmount", destAmount);
    vm.serializeAddress(newKey, "user", address(user));
    string memory finalOutput = vm.serializeBytes(newKey, "swapData", swapData);

    return finalOutput;
  }

  function checkAndGetSwapDatas(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    address user,
    uint8 slippage,
    bool compact
  ) internal view returns (bool exists, uint256 destAmount, bytes memory swapData) {
    string memory key = getKey(srcToken, destToken, srcAmount, user, slippage, compact);
    string memory cacheJson = getCacheJson();

    exists = vm.keyExistsJson(cacheJson, string(abi.encodePacked(".", key)));

    if (exists) {
      destAmount = vm.parseJsonUint(cacheJson, string(abi.encodePacked(".", key, ".destAmount")));
      swapData = vm.parseJsonBytes(cacheJson, string(abi.encodePacked(".", key, ".swapData")));
    }
  }

  function getCacheJson() internal view returns (string memory json) {
    string memory filePath = getCacheFilePath();

    return vm.readFile(filePath);
  }

  function getKey(
    address srcToken,
    address destToken,
    uint256 srcAmount,
    address user,
    uint8 slippage,
    bool compact
  ) internal pure returns (string memory key) {
    return vm.toString(keccak256(abi.encodePacked(srcToken, destToken, srcAmount, user, slippage, compact)));
  }

  function getChainId() public pure returns (uint256 chainId) {
    assembly {
      chainId := chainid()
    }
  }

  function getCacheFilePath() internal pure returns (string memory filePath) {
    return string(abi.encodePacked(CACHE_DIRECTORY_PATH, vm.toString(getChainId()), ".json"));
  }
}
