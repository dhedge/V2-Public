// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {KyberSwapAPIHelper} from "test/integration/common/kyberSwap/KyberSwapAPIHelper.sol";
import {console2} from "forge-std/console2.sol";

/// @dev API calls target the chain of the selected fork.
abstract contract AggregatorsAPIHelper is KyberSwapAPIHelper {
  enum Aggregator {
    ONE_INCH_V6,
    PARASWAP_V6,
    KYBER_SWAP_V2
  }

  struct OneInchFunctionStruct {
    address holder;
    IERC20 srcToken;
    IERC20 destToken;
    uint256 srcAmount;
    uint8 slippage;
  }

  struct ParaswapFunctionStruct {
    address user;
    address holder;
    IERC20 srcToken;
    IERC20 destToken;
    uint256 srcAmount;
    uint8 slippage;
  }

  function __AggregatorsAPIHelper_init(bool useCachedSwapData_) public {
    __KyberSwapAPIHelper_init(useCachedSwapData_);
  }

  function getDataFromOneInchV6(
    OneInchFunctionStruct memory oneInchFunctionStruct
  ) internal returns (uint256 destAmount_, bytes memory calldata_) {
    {
      if (useCachedSwapData) {
        bool exists;
        (exists, destAmount_, calldata_) = checkAndGetSwapDatas(
          oneInchFunctionStruct.srcToken,
          oneInchFunctionStruct.destToken,
          oneInchFunctionStruct.srcAmount,
          Aggregator.ONE_INCH_V6
        );

        if (exists) {
          return (destAmount_, calldata_);
        }
      }
    }

    string memory APIKey = vm.envString("ONE_INCH_API_KEY");
    string[] memory headers = new string[](3);

    string memory url = string.concat(
      "https://api.1inch.dev/swap/v6.0/",
      vm.toString(block.chainid),
      "/swap?src=",
      vm.toString(address(oneInchFunctionStruct.srcToken)),
      "&dst=",
      vm.toString(address(oneInchFunctionStruct.destToken)),
      "&amount=",
      vm.toString(oneInchFunctionStruct.srcAmount),
      "&from=",
      vm.toString(oneInchFunctionStruct.holder),
      "&slippage=",
      vm.toString(oneInchFunctionStruct.slippage),
      "&disableEstimate=true"
    );

    headers[0] = string.concat("Authorization: Bearer ", APIKey);
    headers[1] = "accept: application/json";
    headers[2] = "content-type: application/json";

    (uint256 status, bytes memory data) = _getAndRetry(url, headers);

    if (status != 200) {
      console2.log("Status: ", status);
      console2.log("Data: ", string(data));

      revert("Failed to fetch data from 1inch API");
    }

    destAmount_ = vm.parseJsonUint(string(data), ".dstAmount");
    calldata_ = vm.parseJsonBytes(string(data), ".tx.data");

    if (useCachedSwapData) {
      appendNewObj(
        oneInchFunctionStruct.srcToken,
        oneInchFunctionStruct.destToken,
        oneInchFunctionStruct.srcAmount,
        destAmount_,
        Aggregator.ONE_INCH_V6,
        calldata_
      );
    }
  }

  /// @dev `slippage` is in basis points (Paraswap's convention), so 1% is 100.
  function getDataFromParaswapV6(
    ParaswapFunctionStruct memory paraswapFunctionStruct
  ) internal returns (uint256 destAmount_, bytes memory calldata_) {
    {
      if (useCachedSwapData) {
        bool exists;
        (exists, destAmount_, calldata_) = checkAndGetSwapDatas(
          paraswapFunctionStruct.srcToken,
          paraswapFunctionStruct.destToken,
          paraswapFunctionStruct.srcAmount,
          Aggregator.PARASWAP_V6
        );

        if (exists) {
          return (destAmount_, calldata_);
        }
      }
    }

    bytes memory priceRoute = _getPriceDataFromParaswap(
      paraswapFunctionStruct.srcToken,
      paraswapFunctionStruct.destToken,
      paraswapFunctionStruct.srcAmount
    );

    string memory body = string.concat(
      "{",
      '"srcToken":',
      '"',
      vm.toString(address(paraswapFunctionStruct.srcToken)),
      '"',
      ",",
      '"destToken":',
      '"',
      vm.toString(address(paraswapFunctionStruct.destToken)),
      '"',
      ",",
      '"srcAmount":',
      '"',
      vm.toString(paraswapFunctionStruct.srcAmount),
      '"',
      ",",
      '"userAddress":',
      '"',
      vm.toString(paraswapFunctionStruct.holder),
      '"',
      ",",
      '"txOrigin":',
      '"',
      vm.toString(paraswapFunctionStruct.user),
      '"',
      ",",
      '"slippage":',
      vm.toString(paraswapFunctionStruct.slippage),
      ",",
      '"priceRoute":',
      string(priceRoute),
      "}"
    );

    {
      string[] memory headers = new string[](2);
      headers[0] = "accept: application/json";
      headers[1] = "content-type: application/json";

      string memory url = string.concat(
        "https://api.paraswap.io/transactions/",
        vm.toString(block.chainid),
        "?ignoreChecks=true"
      );
      (uint256 status, bytes memory data) = _postAndRetry(url, headers, body);

      if (status != 200) {
        console2.log("Status: ", status);
        console2.log("Data: ", string(data));

        revert("Failed to fetch data from Paraswap API");
      }

      destAmount_ = vm.parseJsonUint(string(priceRoute), ".destAmount");
      calldata_ = vm.parseJsonBytes(string(data), ".data");
    }

    if (useCachedSwapData) {
      appendNewObj(
        paraswapFunctionStruct.srcToken,
        paraswapFunctionStruct.destToken,
        paraswapFunctionStruct.srcAmount,
        destAmount_,
        Aggregator.PARASWAP_V6,
        calldata_
      );
    }
  }

  function _getPriceDataFromParaswap(
    IERC20 srcToken,
    IERC20 destToken,
    uint256 srcAmount
  ) private returns (bytes memory priceData) {
    string[] memory headers = new string[](2);

    string memory url = string.concat(
      "https://api.paraswap.io/prices?",
      "srcToken=",
      vm.toString(address(srcToken)),
      "&destToken=",
      vm.toString(address(destToken)),
      "&srcDecimals=",
      vm.toString(IERC20Metadata(address(srcToken)).decimals()),
      "&destDecimals=",
      vm.toString(IERC20Metadata(address(destToken)).decimals()),
      "&amount=",
      vm.toString(srcAmount),
      "&version=6.2",
      "&side=SELL",
      "&network=",
      vm.toString(block.chainid)
    );

    headers[0] = "accept: application/json";
    headers[1] = "content-type: application/json";

    (uint256 status, bytes memory returnData) = _getAndRetry(url, headers);

    if (status != 200) {
      console2.log("Status: ", status);
      console2.log("Data: ", string(returnData));

      revert("Failed to fetch price data from Paraswap API");
    }

    return _extractJson(returnData, ".priceRoute");
  }

  /// @dev Returns the raw JSON at `path` (`vm.parseJson` would ABI-encode it instead).
  function _extractJson(bytes memory json, string memory path) private returns (bytes memory) {
    string[] memory inputs = new string[](3);

    inputs[0] = "bash";
    inputs[1] = "-c";
    inputs[2] = string.concat("echo '", string(json), "' | jq -c '", path, "'");

    return vm.ffi(inputs);
  }

  function _getCacheDirectoryPath() internal pure override returns (string memory directoryPath) {
    return "swapdatas-cache/swapper/";
  }

  function checkAndGetSwapDatas(
    IERC20 srcToken,
    IERC20 destToken,
    uint256 srcAmount,
    Aggregator aggregator
  ) private view returns (bool exists, uint256 destAmount, bytes memory swapData) {
    return _checkAndGetSwapDatas(getKey(srcToken, destToken, srcAmount, aggregator));
  }

  function appendNewObj(
    IERC20 srcToken,
    IERC20 destToken,
    uint256 srcAmount,
    uint256 destAmount,
    Aggregator aggregator,
    bytes memory swapData
  ) private {
    string memory newKey = "swapper-swapdata";

    vm.serializeAddress(newKey, "srcToken", address(srcToken));
    vm.serializeAddress(newKey, "destToken", address(destToken));
    vm.serializeUint(newKey, "srcAmount", srcAmount);
    vm.serializeUint(newKey, "destAmount", destAmount);
    vm.serializeUint(newKey, "aggregator", uint256(aggregator));
    string memory obj = vm.serializeBytes(newKey, "swapData", swapData);

    _appendNewObj(getKey(srcToken, destToken, srcAmount, aggregator), obj);
  }

  /// @dev Keyed per aggregator rather than per user/slippage like the base key; `SwapdataCacheManager` adds the fork block prefix.
  function getKey(
    IERC20 srcToken,
    IERC20 destToken,
    uint256 srcAmount,
    Aggregator aggregator
  ) private pure returns (string memory key) {
    return vm.toString(keccak256(abi.encodePacked(srcToken, destToken, srcAmount, aggregator)));
  }
}
