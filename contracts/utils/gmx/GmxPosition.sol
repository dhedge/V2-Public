// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

library GmxPosition {
  function getPositionKey(
    address _account,
    address _market,
    address _collateralToken,
    bool _isLong
  ) internal pure returns (bytes32) {
    bytes32 _key = keccak256(abi.encode(_account, _market, _collateralToken, _isLong));
    return _key;
  }
}
