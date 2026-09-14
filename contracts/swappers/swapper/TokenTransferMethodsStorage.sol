//
//    ===========  ======     ======         =         ====          ====   =========    ==========   ==========
//   ==        ==    ===        ==          ===          ===         ===     ==    ==     ===    ==     ==   ====
// ===          =    ===        ==         = ===         ====       ====     ==    ==     ===           ==    ===
// ====              =============        =   ===        = ===    == ===     ========     ========      =======
// ====              ===        ==       =========       =  ===  ==  ===     ==    ===    ===    =      ==  ===
// ==                ===        ==      =       ===      =   === ==  ===     ==     ===   ===           ==   ===
//   ===       ==    ===        ==     ==        ====    =    ===    ===     ==     ==    ===     ==    ==     ====
//     ==========  ======     ====== =====       ===== ====    ==    ====  ==========    ===========  ======     ====
//
// Chamber Finance - https://chamberfi.com
//
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IWETH} from "../../interfaces/IWETH.sol";

abstract contract TokenTransferMethodsStorage {
  /// @custom:storage-location erc7201:Swapper.TokenTransferMethods
  struct TokenTransferMethodsStorageData {
    address permit2;
    IWETH wrappedNativeToken;
  }

  // keccak256(abi.encode(uint256(keccak256("Swapper.TokenTransferMethods")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant _TOKEN_TRANSFER_METHODS_STORAGE_LOCATION =
    0xf443e521187c51ec1e29e6d8262f76dbe7d41015741854199897c2f773019d00;

  function getPermit2Address() public view returns (address permit2Address_) {
    return _getTokenTransferMethodsStorage().permit2;
  }

  function getWrappedNativeToken() public view returns (IWETH wrappedNativeToken_) {
    return _getTokenTransferMethodsStorage().wrappedNativeToken;
  }

  function _setPermit2Address(address permit2_) internal {
    _getTokenTransferMethodsStorage().permit2 = permit2_;
  }

  function _setWrappedNativeTokenAddress(IWETH wrappedNativeToken_) internal {
    _getTokenTransferMethodsStorage().wrappedNativeToken = wrappedNativeToken_;
  }

  function _getTokenTransferMethodsStorage() private pure returns (TokenTransferMethodsStorageData storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := _TOKEN_TRANSFER_METHODS_STORAGE_LOCATION
    }
  }
}
