// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import {IGmxDataStore} from "../../interfaces/gmx/IGmxDataStore.sol";

library GmxDataStoreLib {
  // @dev key for the address of the wrapped native token
  bytes32 public constant WNT = keccak256(abi.encode("WNT"));

  // @dev key for the nonce value used in NonceUtils
  bytes32 public constant NONCE = keccak256(abi.encode("NONCE"));

  // @dev key for price feed multiplier
  bytes32 public constant PRICE_FEED_MULTIPLIER = keccak256(abi.encode("PRICE_FEED_MULTIPLIER"));

  // @dev key for the account order list
  bytes32 public constant ACCOUNT_ORDER_LIST = keccak256(abi.encode("ACCOUNT_ORDER_LIST"));

  // @dev key for the account deposit list
  bytes32 public constant ACCOUNT_DEPOSIT_LIST = keccak256(abi.encode("ACCOUNT_DEPOSIT_LIST"));

  // @dev key for the account withdrawal list
  bytes32 public constant ACCOUNT_WITHDRAWAL_LIST = keccak256(abi.encode("ACCOUNT_WITHDRAWAL_LIST"));

  /**
   * @dev Returns the address of the WNT token.
   * @param dataStore DataStore contract instance where the address of the WNT token is stored.
   * @return The address of the WNT token.
   */
  function wnt(IGmxDataStore dataStore) internal view returns (address) {
    return dataStore.getAddress(WNT);
  }

  // library NonceUtils
  function getKey(IGmxDataStore dataStore, uint256 nonce) internal pure returns (bytes32) {
    return keccak256(abi.encode(address(dataStore), nonce));
  }

  // @dev get the current nonce value
  // @param dataStore DataStore
  function getCurrentNonce(IGmxDataStore dataStore) internal view returns (uint256) {
    return dataStore.getUint(NONCE);
  }

  // library NonceUtils
  function getCurrentKey(IGmxDataStore dataStore) internal view returns (bytes32) {
    uint256 nonce = getCurrentNonce(dataStore);
    bytes32 key = getKey(dataStore, nonce);

    return key;
  }

  // @dev get the multiplier value to convert the external price feed price to the price of 1 unit of the token
  // represented with 30 decimals
  // for example, if USDC has 6 decimals and a price of 1 USD, one unit of USDC would have a price of
  // 1 / (10 ^ 6) * (10 ^ 30) => 1 * (10 ^ 24)
  // if the external price feed has 8 decimals, the price feed price would be 1 * (10 ^ 8)
  // in this case the priceFeedMultiplier should be 10 ^ 46
  // the conversion of the price feed price would be 1 * (10 ^ 8) * (10 ^ 46) / (10 ^ 30) => 1 * (10 ^ 24)
  // formula for decimals for price feed multiplier: 60 - (external price feed decimals) - (token decimals)
  //
  // @param dataStore DataStore
  // @param token the token to get the price feed multiplier for
  // @return the price feed multipler
  function getPriceFeedMultiplier(IGmxDataStore dataStore, address token) internal view returns (uint256) {
    uint256 multiplier = dataStore.getUint(keccak256(abi.encode(PRICE_FEED_MULTIPLIER, token)));

    if (multiplier == 0) {
      revert("empty price feed multiplier");
    }

    return multiplier;
  }

  // @dev key for the account order list
  // @param account the account for the list
  function accountOrderListKey(address account) private pure returns (bytes32) {
    return keccak256(abi.encode(ACCOUNT_ORDER_LIST, account));
  }

  // @dev key for the account deposit list
  // @param account the account for the list
  function accountDepositListKey(address account) internal pure returns (bytes32) {
    return keccak256(abi.encode(ACCOUNT_DEPOSIT_LIST, account));
  }

  function getAccountOrderCount(IGmxDataStore dataStore, address account) internal view returns (uint256) {
    return dataStore.getBytes32Count(accountOrderListKey(account));
  }

  function getAccountDepositCount(IGmxDataStore dataStore, address account) internal view returns (uint256) {
    return dataStore.getBytes32Count(accountDepositListKey(account));
  }

  // @dev key for the account withdrawal list
  // @param account the account for the list
  function accountWithdrawalListKey(address account) internal pure returns (bytes32) {
    return keccak256(abi.encode(ACCOUNT_WITHDRAWAL_LIST, account));
  }

  function getAccountWithdrawalCount(IGmxDataStore dataStore, address account) internal view returns (uint256) {
    return dataStore.getBytes32Count(accountWithdrawalListKey(account));
  }
}
