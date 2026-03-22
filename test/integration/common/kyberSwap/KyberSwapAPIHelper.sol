// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {console} from "forge-std/Test.sol";

import {SwapdataCacheManager} from "test/integration/ffi/common/helpers/SwapdataCacheManager.sol";

abstract contract KyberSwapAPIHelper is SwapdataCacheManager {
  // Doesn't matter for KyberSwap, just to follow base interfaces structure
  bool public constant COMPACT = true;

  struct KyberSwapData {
    address user;
    address srcToken;
    address destToken;
    uint256 srcAmount;
    uint8 slippageBPS;
  }

  function __KyberSwapAPIHelper_init(bool useCachedSwapData_) public {
    __SwapdataCacheManager_init(useCachedSwapData_);
  }

  function getDataFromKyberSwap(
    KyberSwapData memory swapData,
    uint256 chainId
  ) public returns (uint256 destAmount_, bytes memory calldata_) {
    if (useCachedSwapData) {
      bool exists;
      (exists, destAmount_, calldata_) = _checkAndGetSwapDatas(
        swapData.srcToken,
        swapData.destToken,
        swapData.srcAmount,
        swapData.user,
        swapData.slippageBPS,
        COMPACT
      );

      if (exists) {
        return (destAmount_, calldata_);
      }
    }

    {
      string[] memory headers = new string[](3);
      headers[0] = "accept: */*";
      headers[1] = "content-type: application/json";
      headers[2] = "X-Client-Id: KyberSwapAPIHelper";

      string memory url = string(
        abi.encodePacked(
          "https://aggregator-api.kyberswap.com/",
          _getKyberSwapAPIChainName(chainId),
          "/api/v1/routes?tokenIn=",
          vm.toString(swapData.srcToken),
          "&tokenOut=",
          vm.toString(swapData.destToken),
          "&amountIn=",
          vm.toString(swapData.srcAmount)
        )
      );
      (uint256 status, bytes memory data) = _getAndRetry(url, headers);

      if (status != 200) {
        console.log("Status: ", uint256(status));
        console.log("Data: ", string(data));

        revert("Failed to fetch swap route data from KyberSwap API");
      }

      string[] memory inputs = new string[](3);
      inputs[0] = "bash";
      inputs[1] = "-c";
      inputs[2] = string(abi.encodePacked("echo '", string(data), "' | jq -c '.data.routeSummary'"));
      bytes memory routeSummary = vm.ffi(inputs);

      url = string(
        abi.encodePacked(
          "https://aggregator-api.kyberswap.com/",
          _getKyberSwapAPIChainName(chainId),
          "/api/v1/route/build"
        )
      );
      string memory body = string(
        abi.encodePacked(
          "{",
          '"routeSummary":',
          string(routeSummary),
          ",",
          '"sender":',
          '"',
          vm.toString(swapData.user),
          '"',
          ",",
          '"recipient":',
          '"',
          vm.toString(swapData.user),
          '"',
          ",",
          '"slippageTolerance":',
          vm.toString(uint256(swapData.slippageBPS)),
          "}"
        )
      );
      (status, data) = _postAndRetry(url, headers, body);

      if (status != 200) {
        console.log("Status: ", uint256(status));
        console.log("Data: ", string(data));

        revert("Failed to fetch transaction data from KyberSwap API");
      }

      destAmount_ = vm.parseJsonUint(string(data), ".data.amountOut");
      calldata_ = vm.parseJsonBytes(string(data), ".data.data");
    }

    _appendNewObj(
      swapData.srcToken,
      swapData.destToken,
      swapData.srcAmount,
      swapData.slippageBPS,
      destAmount_,
      swapData.user,
      COMPACT,
      calldata_
    );
  }

  function _getKyberSwapAPIChainName(uint256 chainId) internal pure returns (string memory) {
    if (chainId == 1) return "ethereum";
    if (chainId == 42161) return "arbitrum";
    if (chainId == 137) return "polygon";
    if (chainId == 10) return "optimism";
    if (chainId == 8453) return "base";
    if (chainId == 9745) return "plasma";

    revert("Unknown KyberSwap API chainId");
  }
}
