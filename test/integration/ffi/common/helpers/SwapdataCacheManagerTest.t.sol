// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {console} from "forge-std/console.sol";
import {SwapdataCacheManager} from "./SwapdataCacheManager.sol";

contract SwapdataCacheManagerTestFFI is SwapdataCacheManager {
  function setUp() public {
    vm.skip(true);

    // Initialize with caching enabled
    __SwapdataCacheManager_init(true);
  }

  function testSimpleCache() public {
    // Start with a completely fresh cache by removing the file first
    string memory filePath = _getCacheFilePath();
    if (vm.isFile(filePath)) {
      vm.removeFile(filePath);
    }

    // Add some swap data
    _appendNewObj(address(0x1), address(0x2), 100, 5, 95, address(0x3), false, hex"1234");

    // Verify we can read the data back
    (bool exists, uint256 destAmount, bytes memory swapData) = _checkAndGetSwapDatas(
      address(0x1),
      address(0x2),
      100,
      address(0x3),
      5,
      false
    );

    assertTrue(exists, "Data should exist");
    assertEq(destAmount, 95, "Dest amount should match");
    assertEq(swapData, hex"1234", "Swap data should match");

    // Check the file structure
    string memory cacheJson = _getCacheJson();
    console.log("Final cache JSON:");
    console.log(cacheJson);
  }

  function testDebugMultipleForkBlocks() public {
    // Start with a completely fresh cache
    string memory filePath = _getCacheFilePath();
    if (vm.isFile(filePath)) {
      vm.removeFile(filePath);
    }

    console.log("Starting test with fresh cache");

    // Test with first fork block
    vm.roll(1000000);

    console.log("After init, current block:", vm.getBlockNumber());

    _appendNewObj(address(0x1), address(0x2), 100, 5, 95, address(0x3), false, hex"1234");

    string memory cacheAfterFirst = _getCacheJson();
    console.log("Cache after first append:");
    console.log(cacheAfterFirst);

    // Test with second fork block
    vm.roll(2000000);
    __SwapdataCacheManager_init(true);

    console.log("After roll to block:", vm.getBlockNumber());

    _appendNewObj(address(0x4), address(0x5), 200, 3, 190, address(0x6), true, hex"5678");

    string memory cacheAfterSecond = _getCacheJson();
    console.log("Cache after second append:");
    console.log(cacheAfterSecond);

    // Test isolation from block 2000000
    (bool exists3, , ) = _checkAndGetSwapDatas(address(0x1), address(0x2), 100, address(0x3), 5, false);

    console.log("Does data from block 1000000 exist when querying from 2000000?", exists3);

    // Change back to block 1000000 and test
    vm.roll(1000000);
    (bool exists1, , ) = _checkAndGetSwapDatas(address(0x1), address(0x2), 100, address(0x3), 5, false);

    console.log("Does data exist when querying from correct block 1000000?", exists1);

    assertFalse(exists3, "Cross-block data should not exist");
  }
}
