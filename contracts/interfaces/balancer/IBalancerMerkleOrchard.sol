// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBalancerMerkleOrchard {
  struct Claim {
    uint256 distributionId;
    uint256 balance;
    address distributor;
    uint256 tokenIndex;
    bytes32[] merkleProof;
  }

  function claimDistributions(address claimer, Claim[] memory claims, IERC20[] memory tokens) external;
}
