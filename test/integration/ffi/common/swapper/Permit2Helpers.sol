// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "contracts/interfaces/permit2/ISignatureTransfer.sol";

import {Vm} from "forge-std/Vm.sol";

/// @dev Adapted from <https://github.com/Uniswap/permit2/blob/cc56ad0f3439c502c246fc5cfcc3db92bb8b7219/test/utils/PermitSignature.sol#L10>
abstract contract Permit2Helpers {
  Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

  bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

  bytes32 public constant _PERMIT_TRANSFER_FROM_TYPEHASH =
    keccak256(
      "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

  bytes32 public constant _PERMIT_BATCH_TRANSFER_FROM_TYPEHASH =
    keccak256(
      "PermitBatchTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

  function defaultERC20PermitTransfer(
    address token,
    uint256 amount,
    uint256 nonce
  ) internal view returns (ISignatureTransfer.PermitTransferFrom memory) {
    return
      ISignatureTransfer.PermitTransferFrom({
        permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
        nonce: nonce,
        deadline: block.timestamp + 100
      });
  }

  function defaultERC20PermitMultiple(
    IERC20[] memory srcTokens,
    uint256[] memory srcAmounts,
    uint256 nonce
  ) internal view returns (ISignatureTransfer.PermitBatchTransferFrom memory) {
    ISignatureTransfer.TokenPermissions[] memory permitted = new ISignatureTransfer.TokenPermissions[](
      srcTokens.length
    );
    for (uint256 i = 0; i < srcTokens.length; ++i) {
      permitted[i] = ISignatureTransfer.TokenPermissions({token: address(srcTokens[i]), amount: srcAmounts[i]});
    }
    return
      ISignatureTransfer.PermitBatchTransferFrom({permitted: permitted, nonce: nonce, deadline: block.timestamp + 100});
  }

  function fillSigTransferDetails(
    address to,
    uint256[] memory srcAmounts
  ) internal pure returns (ISignatureTransfer.SignatureTransferDetails[] memory transferDetails) {
    transferDetails = new ISignatureTransfer.SignatureTransferDetails[](srcAmounts.length);
    for (uint256 i = 0; i < srcAmounts.length; ++i) {
      transferDetails[i] = ISignatureTransfer.SignatureTransferDetails({to: to, requestedAmount: srcAmounts[i]});
    }
  }

  function getTransferDetails(
    address to,
    uint256 amount
  ) internal pure returns (ISignatureTransfer.SignatureTransferDetails memory) {
    return ISignatureTransfer.SignatureTransferDetails({to: to, requestedAmount: amount});
  }

  function getPermitTransferSignature(
    ISignatureTransfer.PermitTransferFrom memory permit,
    address to,
    uint256 privateKey,
    bytes32 domainSeparator
  ) internal pure returns (bytes memory sig) {
    bytes32 tokenPermissions = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
    bytes32 msgHash = keccak256(
      abi.encodePacked(
        "\x19\x01",
        domainSeparator,
        keccak256(abi.encode(_PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissions, to, permit.nonce, permit.deadline))
      )
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
    return bytes.concat(r, s, bytes1(v));
  }

  function getPermitBatchTransferSignature(
    ISignatureTransfer.PermitBatchTransferFrom memory permit,
    address to,
    uint256 privateKey,
    bytes32 domainSeparator
  ) internal pure returns (bytes memory sig) {
    bytes32[] memory tokenPermissions = new bytes32[](permit.permitted.length);
    for (uint256 i = 0; i < permit.permitted.length; ++i) {
      tokenPermissions[i] = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted[i]));
    }
    bytes32 msgHash = keccak256(
      abi.encodePacked(
        "\x19\x01",
        domainSeparator,
        keccak256(
          abi.encode(
            _PERMIT_BATCH_TRANSFER_FROM_TYPEHASH,
            keccak256(abi.encodePacked(tokenPermissions)),
            to,
            permit.nonce,
            permit.deadline
          )
        )
      )
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
    return bytes.concat(r, s, bytes1(v));
  }
}
