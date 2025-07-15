// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Surl} from "../../utils/foundry/scripts/Surl.sol";
import {SwapdataCacheManager} from "./SwapdataCacheManager.sol";
import {console} from "forge-std/Test.sol";

abstract contract OdosAPIHelper is SwapdataCacheManager {
  using Surl for string;

  // APIs related constants
  uint8 public constant RETRIES = 10;
  uint16 public constant DEFAULT_HALT_MILLISECONDS = 2000;

  struct OdosFunctionStruct {
    address user;
    address srcToken;
    address destToken;
    uint256 srcAmount;
    uint8 slippage;
  }

  function __OdosAPIHelper_init(bool useCachedSwapData_) public {
    __SwapdataCacheManager_init(useCachedSwapData_);
  }

  function _fetchAndRetry(
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

  function _fetchAndRetry(
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

  function buildQuoteBody(
    OdosFunctionStruct memory odosFunctionStruct,
    uint256 chainId,
    bool compact
  ) internal pure returns (string memory) {
    // Convert values to strings first to reduce inline calls
    string memory chainIdStr = vm.toString(chainId);

    string memory inputToken;
    string memory outputToken;
    string memory otherParams;

    {
      string memory srcAmount = vm.toString(odosFunctionStruct.srcAmount);
      string memory srcToken = vm.toString(address(odosFunctionStruct.srcToken));
      // Encode JSON parts separately to reduce stack pressure
      inputToken = string(
        abi.encodePacked('"inputTokens":[{', '"amount":"', srcAmount, '",', '"tokenAddress":"', srcToken, '"', "}]")
      );
    }

    {
      string memory destToken = vm.toString(address(odosFunctionStruct.destToken));
      outputToken = string(
        abi.encodePacked('"outputTokens":[{', '"proportion":"1",', '"tokenAddress":"', destToken, '"', "}]")
      );
    }

    {
      string memory compactStr = vm.toString(compact);
      string memory userAddr = vm.toString(odosFunctionStruct.user);
      string memory slippageStr = vm.toString(uint256(odosFunctionStruct.slippage));
      otherParams = string(
        abi.encodePacked(
          '"userAddr":"',
          userAddr,
          '",',
          '"compact":',
          compactStr,
          ",",
          '"slippageLimitPercent":',
          slippageStr
        )
      );
    }

    // Final encoding with fewer inline calls
    return
      string(abi.encodePacked("{", '"chainId":', chainIdStr, ",", inputToken, ",", outputToken, ",", otherParams, "}"));
  }

  function buildTransactionBody(
    string memory data,
    OdosFunctionStruct memory odosFunctionStruct
  ) internal pure returns (string memory) {
    // Extract values first to avoid inline function calls
    string memory pathId = vm.parseJsonString(string(data), ".pathId");
    string memory userAddr = vm.toString(odosFunctionStruct.user);

    // Construct the JSON body in fewer steps
    return string(abi.encodePacked("{", '"pathId":"', pathId, '",', '"userAddr":"', userAddr, '"', "}"));
  }

  function getDataFromOdos(
    OdosFunctionStruct memory odosFunctionStruct,
    address user,
    uint8 slippage,
    uint256 chainId,
    bool compact
  ) public returns (uint256 destAmount_, bytes memory calldata_) {
    {
      if (useCachedSwapData) {
        bool exists;
        (exists, destAmount_, calldata_) = checkAndGetSwapDatas(
          odosFunctionStruct.srcToken,
          odosFunctionStruct.destToken,
          odosFunctionStruct.srcAmount,
          user,
          slippage,
          compact
        );

        if (exists) {
          return (destAmount_, calldata_);
        }
      }
    }
    string memory quoteBody = buildQuoteBody(odosFunctionStruct, chainId, compact);

    {
      string[] memory headers = new string[](2);
      headers[0] = "accept: application/json";
      headers[1] = "content-type: application/json";

      string memory url = "https://api.odos.xyz/sor/quote/v2";
      (uint256 status, bytes memory data) = _fetchAndRetry(url, headers, quoteBody);

      if (status != 200) {
        console.log("Status: ", uint256(status));
        console.log("Data: ", string(data));

        revert("Failed to fetch quote data from Odos API");
      }

      string[] memory outputTokenAmountArr = vm.parseJsonStringArray(string(data), ".outAmounts");
      destAmount_ = vm.parseUint(outputTokenAmountArr[0]);

      string memory transactionBody = buildTransactionBody(string(data), odosFunctionStruct);

      url = "https://api.odos.xyz/sor/assemble";
      (status, data) = _fetchAndRetry(url, headers, transactionBody);

      if (status != 200) {
        console.log("Status: ", uint256(status));
        console.log("Data: ", string(data));

        revert("Failed to fetch transaction data from Odos API");
      }

      calldata_ = vm.parseJsonBytes(string(data), ".transaction.data");
    }

    appendNewObj(
      odosFunctionStruct.srcToken,
      odosFunctionStruct.destToken,
      odosFunctionStruct.srcAmount,
      slippage,
      destAmount_,
      user,
      compact,
      calldata_
    );
  }
}
