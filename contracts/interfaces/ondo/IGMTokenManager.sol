// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

import {IOndoSanityCheckOracle} from "./IOndoSanityCheckOracle.sol";

interface IGMTokenManager {
  enum QuoteSide {
    BUY,
    SELL
  }

  function sanityCheckOracle() external view returns (IOndoSanityCheckOracle);

  function gmTokenMintingPaused(address gmToken) external view returns (bool);

  function gmTokenRedemptionsPaused(address gmToken) external view returns (bool);

  struct Quote {
    uint256 chainId;
    uint256 attestationId;
    bytes32 userId;
    address asset;
    uint256 price;
    uint256 quantity;
    uint256 expiration;
    uint8 side;
    bytes32 additionalData;
  }

  function mintWithAttestation(
    Quote calldata quote,
    bytes calldata signature,
    address depositToken,
    uint256 depositTokenAmount
  ) external returns (uint256);

  function redeemWithAttestation(
    Quote calldata quote,
    bytes calldata signature,
    address receiveToken,
    uint256 minimumReceiveAmount
  ) external returns (uint256);

  function getDomainSeparator() external view returns (bytes32);

  function hasRole(bytes32 role, address account) external view returns (bool);

  // solhint-disable-next-line func-name-mixedcase
  function ATTESTATION_SIGNER_ROLE() external view returns (bytes32);
}
