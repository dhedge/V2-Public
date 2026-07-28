// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import {IGMTokenManager} from "./IGMTokenManager.sol";

interface IOndoGMSwap {
  function gmTokenManager() external view returns (IGMTokenManager);

  function usdc() external view returns (address);

  function swapExactInWithAttestation(
    address tokenIn,
    uint256 amountIn,
    address tokenOut,
    uint256 amountOutMinimum,
    bytes calldata attestationSignature,
    IGMTokenManager.Quote calldata quote
  ) external;
}
