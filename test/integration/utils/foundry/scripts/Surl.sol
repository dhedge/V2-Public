// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Vm} from "forge-std/Vm.sol";

/// @dev Fetched the file from: https://github.com/memester-xyz/surl/blob/034c912ae9b5e707a5afd21f145b452ad8e800df/src/Surl.sol#L6
library Surl {
  Vm public constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

  function get(string memory self) internal returns (uint256 status, bytes memory data) {
    string[] memory empty = new string[](0);
    return get(self, empty);
  }

  function get(string memory self, string[] memory headers) internal returns (uint256 status, bytes memory data) {
    return curl(self, headers, "", "GET");
  }

  function del(string memory self) internal returns (uint256 status, bytes memory data) {
    string[] memory empty = new string[](0);
    return curl(self, empty, "", "DELETE");
  }

  function del(string memory self, string memory body) internal returns (uint256 status, bytes memory data) {
    string[] memory empty = new string[](0);
    return curl(self, empty, body, "DELETE");
  }

  function del(
    string memory self,
    string[] memory headers,
    string memory body
  ) internal returns (uint256 status, bytes memory data) {
    return curl(self, headers, body, "DELETE");
  }

  function patch(string memory self) internal returns (uint256 status, bytes memory data) {
    string[] memory empty = new string[](0);
    return curl(self, empty, "", "PATCH");
  }

  function patch(string memory self, string memory body) internal returns (uint256 status, bytes memory data) {
    string[] memory empty = new string[](0);
    return curl(self, empty, body, "PATCH");
  }

  function patch(
    string memory self,
    string[] memory headers,
    string memory body
  ) internal returns (uint256 status, bytes memory data) {
    return curl(self, headers, body, "PATCH");
  }

  function post(string memory self) internal returns (uint256 status, bytes memory data) {
    string[] memory empty = new string[](0);
    return curl(self, empty, "", "POST");
  }

  function post(string memory self, string memory body) internal returns (uint256 status, bytes memory data) {
    string[] memory empty = new string[](0);
    return curl(self, empty, body, "POST");
  }

  function post(
    string memory self,
    string[] memory headers,
    string memory body
  ) internal returns (uint256 status, bytes memory data) {
    return curl(self, headers, body, "POST");
  }

  function put(string memory self) internal returns (uint256 status, bytes memory data) {
    string[] memory empty = new string[](0);
    return curl(self, empty, "", "PUT");
  }

  function put(string memory self, string memory body) internal returns (uint256 status, bytes memory data) {
    string[] memory empty = new string[](0);
    return curl(self, empty, body, "PUT");
  }

  function put(
    string memory self,
    string[] memory headers,
    string memory body
  ) internal returns (uint256 status, bytes memory data) {
    return curl(self, headers, body, "PUT");
  }

  function curl(
    string memory self,
    string[] memory headers,
    string memory body,
    string memory method
  ) internal returns (uint256 status, bytes memory data) {
    string memory scriptStart = 'response=$(curl -s -w "\\n%{http_code}" ';
    string
      memory scriptEnd = '); status=$(tail -n1 <<< "$response"); data=$(sed "$ d" <<< "$response");data=$(echo "$data" | tr -d "\\n"); cast abi-encode "response(uint256,string)" "$status" "$data";';

    string memory curlParams = "";

    for (uint256 i = 0; i < headers.length; i++) {
      curlParams = string(abi.encodePacked(curlParams, '-H "', headers[i], '" '));
    }

    curlParams = string(abi.encodePacked(curlParams, " -X ", method, " "));

    if (bytes(body).length > 0) {
      curlParams = string(abi.encodePacked(curlParams, " -d '", body, "' "));
    }

    string memory quotedURL = string(abi.encodePacked('"', self, '"'));

    string[] memory inputs = new string[](3);
    inputs[0] = "bash";
    inputs[1] = "-c";
    inputs[2] = string(abi.encodePacked(scriptStart, curlParams, quotedURL, scriptEnd, ""));
    bytes memory res = vm.ffi(inputs);

    (status, data) = abi.decode(res, (uint256, bytes));
  }
}
