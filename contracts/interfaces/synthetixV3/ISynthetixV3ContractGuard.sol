// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "../../utils/synthetixV3/libraries/SynthetixV3Structs.sol";

interface ISynthetixV3ContractGuard {
  function dHedgeVaultsWhitelist(address _poolLogic) external view returns (SynthetixV3Structs.VaultSetting memory);

  function getAccountNftTokenId(address _poolLogic, address _to) external view returns (uint128 tokenId);

  function isVaultWhitelisted(address _poolLogic) external view returns (bool);
}
