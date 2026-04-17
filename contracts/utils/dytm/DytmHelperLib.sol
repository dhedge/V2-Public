// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

import {IDytmOffice} from "../../interfaces/dytm/IDytmOffice.sol";

library DytmHelperLib {
  /// @dev Accrue interest for all collateral and debt reserves of a single position
  /// @return collateralCount Number of collateral entries in this position
  function accruePositionInterest(
    IDytmOffice _dytmOffice,
    uint256 _account,
    uint88 _marketId
  ) internal returns (uint256 collateralCount) {
    uint256[] memory collateralIds = _dytmOffice.getAllCollateralIds(_account, _marketId);
    for (uint256 j; j < collateralIds.length; ++j) {
      _dytmOffice.accrueInterest(getReserveKey(collateralIds[j]));
    }
    uint256 debtId = _dytmOffice.getDebtId(_account, _marketId);
    if (debtId > 0) {
      _dytmOffice.accrueInterest(getReserveKey(debtId));
    }
    collateralCount = collateralIds.length;
  }

  function getAssetFromTokenId(uint256 tokenId) internal pure returns (address asset) {
    return address(uint160(tokenId));
  }
  function getReserveKey(uint256 tokenId) internal pure returns (uint248 rawReserveKey) {
    return uint248(tokenId);
  }

  function getMarketId(uint248 rawReserveKey) internal pure returns (uint88 rawMarketId) {
    rawMarketId = uint88(rawReserveKey >> 160);
  }

  function getAsset(uint248 rawReserveKey) internal pure returns (address asset) {
    return address(uint160(rawReserveKey));
  }

  enum AccountType {
    INVALID_ACCOUNT, // 0
    USER_ACCOUNT, // 1
    ISOLATED_ACCOUNT // 2
  }

  function getAccountType(uint256 rawAccount) internal pure returns (AccountType accountType) {
    uint160 addressField = uint160(rawAccount);
    uint96 accountCount = uint96(rawAccount >> 160);

    if (addressField == 0 && accountCount != 0) {
      return AccountType.ISOLATED_ACCOUNT; // Isolated account
    } else if (addressField != 0 && accountCount == 0) {
      return AccountType.USER_ACCOUNT; // User account
    } else {
      revert("Invalid raw account ID");
    }
  }

  function isUserAccount(uint256 rawAccount) internal pure returns (bool isUser) {
    return getAccountType(rawAccount) == AccountType.USER_ACCOUNT;
  }

  function toUserAddress(uint256 rawAccount) internal pure returns (address user) {
    // Validate that the account is a user account.
    require(isUserAccount(rawAccount), "invalid account type");

    return address(uint160(rawAccount));
  }

  function toUserAccount(address user) internal pure returns (uint256 account) {
    require(user != address(0), "empty user account");
    return uint256(uint160(user));
  }
}
