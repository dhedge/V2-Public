// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface ITypedStructuredDataValidatorMock {
  enum StructuredDataSupported {
    ODOS_LIMIT_ORDER,
    COWSWAP_ORDER
  }

  function MAX_ORDERS_PER_POOL() external view returns (uint256);
  function cancelOrder(address _pool, bytes32 _orderHash) external;
  function configs(StructuredDataSupported dataType) external view returns (bytes memory config);
  function cowSwapFillInfo(address pool, bytes32 hash) external view returns (uint256 targetFillAmount);
  function getPoolOrderHashes(address _pool) external view returns (bytes32[] memory);
  function hasActiveOrderWithToken(address _pool, address _token) external view returns (bool);
  function initialize(address _owner, address _poolFactory) external;
  function isOrderFilled(address _pool, bytes32 _orderHash) external view returns (bool);
  function isValidatedHash(address _pool, bytes32 _hash) external view returns (bool);
  function orderTokens(
    address pool,
    bytes32 hash
  ) external view returns (address inputToken, address outputToken, uint256 expiry, StructuredDataSupported orderType);
  function owner() external view returns (address);
  function poolFactory() external view returns (address);
  function removeOrder(address _pool, bytes32 _orderHash) external;
  function renounceOwnership() external;
  function setPoolFactory(address _poolFactory) external;
  function setValidationConfig(StructuredDataSupported _dataType, bytes memory _config) external;
  function submit(address _poolLogic, StructuredDataSupported _dataType, bytes memory _structuredData) external;
  function transferOwnership(address newOwner) external;
  function validatedHashes(address pool, bytes32 hash) external view returns (bool exists);
}
