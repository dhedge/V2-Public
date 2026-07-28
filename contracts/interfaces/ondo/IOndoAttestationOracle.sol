// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import {IGMTokenManager} from "./IGMTokenManager.sol";

interface IOndoAttestationOracle {
  function gmTokenManager() external view returns (IGMTokenManager);

  function getPrice(address gmToken) external view returns (uint256 price, uint256 updatedAt);

  function attestedPrices(address gmToken) external view returns (uint256 price, uint256 updatedAt, uint256 expiration);

  function updatePrices(IGMTokenManager.Quote[] calldata quotes, bytes[] calldata signatures) external;
}
