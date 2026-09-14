// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import {Vm} from "forge-std/Vm.sol";

abstract contract GmxLivePrices {
  Vm private constant GMX_VM = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

  string internal constant GMX_LIVE_PRICES_SCRIPT = "test/integration/ffi/42161/gmx/gmxLivePrices.ts";
  // Keep this true for fast deterministic development runs. Set it to false to
  // fetch current GMX signed reports and select a matching live Arbitrum block.
  // If the archive RPC rate-limits parallel reads, run live mode with --threads 1.
  //
  // The fork block always comes from livePrices.forkBlockNumber, consumed at
  // GmxTestSetup.t.sol:149 (vm.createSelectFork). True: block from the cached
  // arbitrum.json fixture. False: script picks a fresh block for the new reports.
  bool internal constant USE_CACHED_GMX_DATA = true;

  struct LivePrices {
    uint256 forkBlockNumber;
    uint256[] reportTimestamps;
    address[] tokens;
    bytes[][] blobs;
    uint256[][] minPrices;
    uint256[][] maxPrices;
  }

  function _getLivePrices(address[] memory requestedTokens) internal returns (LivePrices memory prices) {
    string[] memory command = new string[](requestedTokens.length + 4);
    command[0] = GMX_VM.envOr("NODE_BINARY", string("node"));
    command[1] = "--experimental-strip-types";
    command[2] = GMX_LIVE_PRICES_SCRIPT;
    command[3] = USE_CACHED_GMX_DATA ? "true" : "false";

    for (uint256 i; i < requestedTokens.length; ++i) {
      command[i + 4] = GMX_VM.toString(requestedTokens[i]);
    }

    bytes memory result = GMX_VM.ffi(command);
    (
      prices.forkBlockNumber,
      prices.reportTimestamps,
      prices.tokens,
      prices.blobs,
      prices.minPrices,
      prices.maxPrices
    ) = abi.decode(result, (uint256, uint256[], address[], bytes[][], uint256[][], uint256[][]));

    require(prices.tokens.length == requestedTokens.length, "GMX price count mismatch");
    require(prices.reportTimestamps.length >= 3, "GMX price reports missing");
  }
}
