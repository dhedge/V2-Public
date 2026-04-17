// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {console} from "forge-std/Test.sol";

import {SwapdataCacheManager} from "test/integration/ffi/common/helpers/SwapdataCacheManager.sol";

abstract contract OdosAPIHelper is SwapdataCacheManager {
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
    uint256 chainId,
    bool compact,
    string memory version
  ) public returns (uint256 destAmount_, bytes memory calldata_) {
    {
      if (useCachedSwapData) {
        bool exists;
        (exists, destAmount_, calldata_) = _checkAndGetSwapDatas(
          odosFunctionStruct.srcToken,
          odosFunctionStruct.destToken,
          odosFunctionStruct.srcAmount,
          odosFunctionStruct.user,
          odosFunctionStruct.slippage,
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

      (uint256 status, bytes memory data) = _postAndRetry(_getQuoteEndpoint(version), headers, quoteBody);

      if (status != 200) {
        console.log("Status: ", uint256(status));
        console.log("Data: ", string(data));

        revert("Failed to fetch quote data from Odos API");
      }

      string[] memory outputTokenAmountArr = vm.parseJsonStringArray(string(data), ".outAmounts");
      destAmount_ = vm.parseUint(outputTokenAmountArr[0]);

      string memory transactionBody = buildTransactionBody(string(data), odosFunctionStruct);

      (status, data) = _postAndRetry("https://api.odos.xyz/sor/assemble", headers, transactionBody);

      if (status != 200) {
        console.log("Status: ", uint256(status));
        console.log("Data: ", string(data));

        revert("Failed to fetch transaction data from Odos API");
      }

      calldata_ = vm.parseJsonBytes(string(data), ".transaction.data");
    }

    _appendNewObj(
      odosFunctionStruct.srcToken,
      odosFunctionStruct.destToken,
      odosFunctionStruct.srcAmount,
      odosFunctionStruct.slippage,
      destAmount_,
      odosFunctionStruct.user,
      compact,
      calldata_
    );
  }

  function _getQuoteEndpoint(string memory version) internal pure returns (string memory quoteEndpoint) {
    if (keccak256(abi.encodePacked((version))) == keccak256(abi.encodePacked(("v2")))) {
      quoteEndpoint = "https://api.odos.xyz/sor/quote/v2";
    } else if (keccak256(abi.encodePacked((version))) == keccak256(abi.encodePacked(("v3")))) {
      quoteEndpoint = "https://api.odos.xyz/sor/quote/v3";
    } else {
      revert("Unknown Odos API version");
    }
  }
}
