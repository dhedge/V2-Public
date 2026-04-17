//
//        __  __    __  ________  _______    ______   ________
//       /  |/  |  /  |/        |/       \  /      \ /        |
//   ____$$ |$$ |  $$ |$$$$$$$$/ $$$$$$$  |/$$$$$$  |$$$$$$$$/
//  /    $$ |$$ |__$$ |$$ |__    $$ |  $$ |$$ | _$$/ $$ |__
// /$$$$$$$ |$$    $$ |$$    |   $$ |  $$ |$$ |/    |$$    |
// $$ |  $$ |$$$$$$$$ |$$$$$/    $$ |  $$ |$$ |$$$$ |$$$$$/
// $$ \__$$ |$$ |  $$ |$$ |_____ $$ |__$$ |$$ \__$$ |$$ |_____
// $$    $$ |$$ |  $$ |$$       |$$    $$/ $$    $$/ $$       |
//  $$$$$$$/ $$/   $$/ $$$$$$$$/ $$$$$$$/   $$$$$$/  $$$$$$$$/
//
// dHEDGE DAO - https://dhedge.org
//
// Copyright (c) dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/v5/contracts/utils/structs/EnumerableSet.sol";

import {IDataValidator} from "../interfaces/IDataValidator.sol";
import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IPoolLogic} from "../interfaces/IPoolLogic.sol";
import {IManaged} from "../interfaces/IManaged.sol";
import {IGPv2Settlement} from "../interfaces/cowSwap/IGPv2Settlement.sol";
import {CowSwapOrderValidator} from "./cowSwap/CowSwapOrderValidator.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";

/// @title TypedStructuredDataValidator
/// @notice Validates EIP-712 typed structured data before orders can be placed on external protocols
/// @dev This contract implements a security layer for limit orders in dHEDGE pools.
///      Since pool managers are not fully trusted, we cannot allow them to place arbitrary orders.
///      This validator ensures that order data has been pre-validated to contain only safe
///      operations (e.g., supported tokens, valid receiver, acceptable rate vs oracle).
///
///      CoWSwap Order Flow:
///      1. Manager creates an off-chain order (CoWSwap limit order)
///      2. Manager calls submit() with the full order data → validator checks it's safe
///      3. If valid, the order hash is stored as approved in validatedHashes
///      4. Manager calls pool.execTransaction(GPv2Settlement.setPreSignature(orderUid, true))
///      5. GPv2SettlementContractGuard checks validatedHashes[pool][orderDigest] exists
///      6. If valid, the pre-sign transaction is allowed
///      7. CoWSwap solvers can now execute the order when market conditions are met
///
///      Token Locking & Cleanup:
///      Tokens involved in validated orders are locked (cannot be removed from pool's supported
///      assets) until the order is completed. An order is considered complete when either:
///      - The order has expired (validTo timestamp passed), OR
///      - The order has been fully filled (detected via protocol-specific on-chain queries)
///      For CoWSwap orders, fill status is checked by querying GPv2Settlement.filledAmount().
///      Completed orders are automatically cleaned up during submit() calls.
///      Managers can also manually cancel orders via cancelOrder() to unlock tokens early.
///
///      COWSWAP ORDER CONSIDERATIONS:
///      - Fill-or-Kill Orders (partiallyFillable=false): If the pool's token balance decreases
///        (e.g., due to depositor withdrawals) below the order's sellAmount, the order becomes
///        unfillable. Solvers will fail to execute it until sufficient balance is restored or
///        the order expires. Tokens remain locked until expiry.
///      - Partially Fillable Orders (partiallyFillable=true): Solvers can fill
///        whatever amount is available. If balance decreases, the order partially fills with
///        remaining balance. Tokens unlock once fully filled or expired.
///      - If a fill-or-kill order becomes stuck due to insufficient balance, the manager should
///        cancel it via cancelOrder() and create a new order with the correct amount.
///        Frontend alerts can help detect such situations.
contract TypedStructuredDataValidator is OwnableUpgradeable, IDataValidator, ICommonErrors {
  using EnumerableSet for EnumerableSet.Bytes32Set;

  /// @notice Thrown when the data type is not supported by this validator
  error UnsupportedDataType(uint8 dataType);
  /// @notice Thrown when the order hash is not found in the pool's order list
  error OrderNotFound(address pool, bytes32 orderHash);
  /// @notice Thrown when trying to add an order but pool has reached max orders limit
  error MaxOrdersReached(address pool);
  /// @notice Thrown when trying to remove an order that is still active on the external protocol
  /// @dev For CoWSwap orders, must call GPv2Settlement.invalidateOrder() before cancelling
  error OrderStillActive(address pool, bytes32 orderHash);

  /// @notice Emitted when structured data is validated and its hash is approved
  /// @param pool The pool address for which the data was validated
  /// @param dataType The type of structured data that was validated
  /// @param hash The EIP-712 hash that was approved
  event DataValidated(address indexed pool, StructuredDataSupported indexed dataType, bytes32 hash);

  /// @notice Emitted when an order is removed (by owner or cancelled by manager/trader)
  /// @param pool The pool address from which the order was removed
  /// @param orderHash The hash of the removed order
  event OrderRemoved(address indexed pool, bytes32 indexed orderHash);

  /// @notice Emitted when completed orders (expired or filled) are cleaned up
  /// @param pool The pool address from which orders were cleaned
  /// @param count The number of orders removed
  event OrdersCleanedUp(address indexed pool, uint256 count);

  /// @notice Struct to track tokens involved in an order and its expiry
  /// @param inputToken The token being sold
  /// @param outputToken The token being bought
  /// @param expiry The order expiration timestamp
  /// @param orderType The type of order (protocol that created it)
  struct OrderTokenInfo {
    address inputToken;
    address outputToken;
    uint256 expiry;
    StructuredDataSupported orderType;
  }

  /// @notice Struct to track CoWSwap-specific fill information
  /// @param targetFillAmount The amount that indicates the order is fully filled
  ///        (sellAmount for sell orders, buyAmount for buy orders)
  struct CowSwapFillInfo {
    uint256 targetFillAmount;
  }

  /// @notice Enum of supported structured data types for validation
  enum StructuredDataSupported {
    ODOS_LIMIT_ORDER, // Reserved (not implemented)
    COWSWAP_ORDER // CoWSwap (GPv2) order via pre-sign
  }

  /// @notice Maximum number of orders that can be tracked per pool
  /// @dev This limit ensures bounded gas costs for iteration and cleanup operations
  uint256 public constant MAX_ORDERS_PER_POOL = 10;

  /// @notice Reference to the dHEDGE PoolFactory contract
  IPoolFactory public poolFactory;

  /// @notice Configuration data for each supported data type
  /// @dev Contains protocol-specific addresses (e.g., GPv2Settlement for CoWSwap)
  mapping(StructuredDataSupported dataType => bytes config) public configs;

  /// @notice Mapping of validated order hashes per pool
  /// @dev Pool-specific to prevent hash collision across different pools.
  ///      A hash validated for Pool A cannot be used to authorize signatures for Pool B.
  mapping(address pool => mapping(bytes32 hash => bool exists)) public validatedHashes;

  /// @notice Mapping of order hashes to their token info per pool
  /// @dev Used to check if a token can be removed from a pool's supported assets
  mapping(address pool => mapping(bytes32 hash => OrderTokenInfo tokenInfo)) public orderTokens;

  /// @notice Set of active order hashes per pool
  /// @dev Used to iterate and check for active orders involving a specific token.
  ///      Using EnumerableSet for O(1) add/remove/contains and automatic duplicate prevention.
  mapping(address pool => EnumerableSet.Bytes32Set orderHashes) internal _poolOrderHashes;

  /// @notice CoWSwap-specific fill tracking information per order
  /// @dev Used to determine if a CoWSwap order has been filled by querying GPv2Settlement
  mapping(address pool => mapping(bytes32 hash => CowSwapFillInfo fillInfo)) public cowSwapFillInfo;

  /// @notice Ensures the provided address is a valid dHEDGE pool
  modifier onlyPool(address _pool) {
    _checkPool(_pool);
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initialize the validator contract
  /// @param _owner The owner address (typically dHEDGE multisig)
  /// @param _poolFactory The dHEDGE PoolFactory contract address
  function initialize(address _owner, address _poolFactory) external initializer {
    __Ownable_init(_owner);

    _setPoolFactory(_poolFactory);
  }

  /// @notice Submit and validate structured data for a pool
  /// @dev This function validates the order data and stores the hash if valid.
  ///      Only the pool's manager or trader can submit data for their pool.
  ///      The validation logic depends on the data type.
  ///      Note: Tokens in validated orders are locked until the order is completed
  ///      (expired or filled). See contract-level documentation for details.
  /// @param _poolLogic The address of the PoolLogic contract for which the order is being submitted
  /// @param _dataType The type of structured data being submitted
  /// @param _structuredData The ABI-encoded structured data (e.g., full EIP-712 typed data)
  function submit(
    address _poolLogic,
    StructuredDataSupported _dataType,
    bytes calldata _structuredData
  ) external onlyPool(_poolLogic) {
    address poolManagerLogic = _checkManagerOrTrader(_poolLogic);

    bytes32 validatedHash;
    address inputToken;
    address outputToken;
    uint256 expiry;
    uint256 targetFillAmount;

    if (_dataType == StructuredDataSupported.COWSWAP_ORDER) {
      bytes memory configData = configs[_dataType];
      (validatedHash, inputToken, outputToken, expiry, targetFillAmount) = CowSwapOrderValidator.validate(
        _structuredData,
        configData,
        _poolLogic,
        poolManagerLogic
      );

      // Store CoWSwap-specific fill tracking info
      cowSwapFillInfo[_poolLogic][validatedHash] = CowSwapFillInfo({targetFillAmount: targetFillAmount});
    } else {
      revert UnsupportedDataType(uint8(_dataType));
    }

    // Store the validated hash for this specific pool
    // This prevents hash reuse across different pools
    validatedHashes[_poolLogic][validatedHash] = true;

    // Cleanup completed orders (expired or fully filled) before adding new one
    // For CoWSwap orders, fill status is checked via GPv2Settlement.filledAmount()
    // This is bounded by MAX_ORDERS_PER_POOL, ensuring predictable gas costs
    _cleanupCompletedOrders(_poolLogic);

    // Check if we've reached the limit after cleanup
    if (_poolOrderHashes[_poolLogic].length() >= MAX_ORDERS_PER_POOL) {
      revert MaxOrdersReached(_poolLogic);
    }

    // Store token info for active order tracking
    // This allows us to prevent removal of tokens that are part of active orders
    orderTokens[_poolLogic][validatedHash] = OrderTokenInfo({
      inputToken: inputToken,
      outputToken: outputToken,
      expiry: expiry,
      orderType: _dataType
    });
    _poolOrderHashes[_poolLogic].add(validatedHash);

    emit DataValidated(_poolLogic, _dataType, validatedHash);
  }

  /// @notice Set the dHEDGE PoolFactory contract address
  /// @dev Only callable by the owner
  /// @param _poolFactory The pool factory contract address to set
  function setPoolFactory(address _poolFactory) external onlyOwner {
    _setPoolFactory(_poolFactory);
  }

  /// @notice Set the validation configuration for a specific data type
  /// @dev Configuration contains protocol-specific addresses needed for validation
  ///      For ODOS_LIMIT_ORDER: abi.encode(OdosLimitOrderValidationConfig)
  ///      For COWSWAP_ORDER: abi.encode(CowSwapValidationConfig)
  /// @param _dataType The data type to configure
  /// @param _config The ABI-encoded configuration data
  function setValidationConfig(StructuredDataSupported _dataType, bytes calldata _config) external onlyOwner {
    configs[_dataType] = _config;
  }

  /// @notice Remove an order from active tracking (owner-only emergency function)
  /// @dev This function allows the owner to manually remove orders from the active order tracking.
  ///      This is useful in edge cases where automatic cleanup doesn't apply.
  ///      Removes from all storage: validatedHashes, orderTokens, _poolOrderHashes,
  ///      and protocol-specific storage (e.g., cowSwapFillInfo).
  /// @param _pool The pool address from which to remove the order
  /// @param _orderHash The hash of the order to remove
  function removeOrder(address _pool, bytes32 _orderHash) external onlyOwner onlyPool(_pool) {
    _removeOrder(_pool, _orderHash);
  }

  /// @notice Cancel an order by invalidating its hash (manager/trader function)
  /// @dev This function allows the pool's manager or trader to cancel an order they submitted.
  ///      It removes the hash from validatedHashes and order tracking to unlock the involved tokens.
  ///
  ///      IMPORTANT: For CoWSwap orders, the order must first be invalidated on GPv2Settlement
  ///      by calling pool.execTransaction(GPv2Settlement.invalidateOrder(orderUid)) before
  ///      calling this function. Otherwise, this function will revert with OrderStillActive.
  ///      This prevents unlocking tokens while the order could still execute externally.
  /// @param _pool The pool address from which to cancel the order
  /// @param _orderHash The hash of the order to cancel
  function cancelOrder(address _pool, bytes32 _orderHash) external onlyPool(_pool) {
    _checkManagerOrTrader(_pool);
    _removeOrder(_pool, _orderHash);
  }

  /// @notice Get all order hashes for a pool
  /// @param _pool The pool address
  /// @return All order hashes for the pool
  function getPoolOrderHashes(address _pool) external view returns (bytes32[] memory) {
    return _poolOrderHashes[_pool].values();
  }

  /// @inheritdoc IDataValidator
  function isValidatedHash(address _pool, bytes32 _hash) external view override returns (bool) {
    return validatedHashes[_pool][_hash];
  }

  /// @inheritdoc IDataValidator
  function hasActiveOrderWithToken(address _pool, address _token) external view override returns (bool) {
    EnumerableSet.Bytes32Set storage hashes = _poolOrderHashes[_pool];
    uint256 length = hashes.length();

    for (uint256 i; i < length; ++i) {
      bytes32 orderHash = hashes.at(i);
      OrderTokenInfo storage info = orderTokens[_pool][orderHash];

      // Skip expired orders
      if (info.expiry <= block.timestamp) {
        continue;
      }

      // Skip filled orders
      if (_isOrderFilled(_pool, orderHash, info)) {
        continue;
      }

      // Check if token is involved in this active order
      if (info.inputToken == _token || info.outputToken == _token) {
        return true;
      }
    }

    return false;
  }

  /// @notice Check if a specific order has been filled
  /// @dev Uses protocol-specific logic to determine fill status
  /// @param _pool The pool address
  /// @param _orderHash The order hash
  /// @return True if the order is filled, false otherwise
  function isOrderFilled(address _pool, bytes32 _orderHash) external view returns (bool) {
    OrderTokenInfo storage info = orderTokens[_pool][_orderHash];
    return _isOrderFilled(_pool, _orderHash, info);
  }

  /// @notice Check if the provided address is a valid dHEDGE pool
  /// @dev Reverts if the pool is not valid
  /// @param _pool The pool address to check
  function _checkPool(address _pool) internal view {
    if (!poolFactory.isPool(_pool)) {
      revert InvalidPool(_pool);
    }
  }

  /// @notice Check if the caller is the manager or trader of the pool
  /// @dev Reverts if the caller is not authorized
  /// @param _pool The pool address to check
  /// @return poolManagerLogic The PoolManagerLogic address for the pool
  function _checkManagerOrTrader(address _pool) internal view returns (address poolManagerLogic) {
    poolManagerLogic = IPoolLogic(_pool).poolManagerLogic();
    if (msg.sender != IManaged(poolManagerLogic).manager() && msg.sender != IManaged(poolManagerLogic).trader()) {
      revert UnauthorizedCaller(msg.sender);
    }
  }

  /// @notice Clean up completed orders (expired or filled) for a pool
  /// @dev Iterates through all orders and removes completed ones.
  ///      Gas cost is bounded by MAX_ORDERS_PER_POOL.
  /// @param _pool The pool address to clean up
  function _cleanupCompletedOrders(address _pool) internal {
    EnumerableSet.Bytes32Set storage hashes = _poolOrderHashes[_pool];
    uint256 length = hashes.length();
    uint256 removed;

    // Iterate backwards to safely remove while iterating
    for (uint256 i = length; i > 0; ) {
      unchecked {
        --i;
      }
      bytes32 orderHash = hashes.at(i);
      OrderTokenInfo storage info = orderTokens[_pool][orderHash];

      bool isExpired = info.expiry <= block.timestamp;
      bool isFilled = _isOrderFilled(_pool, orderHash, info);

      if (isExpired || isFilled) {
        hashes.remove(orderHash);
        _cleanupOrderStorage(_pool, orderHash, info.orderType);
        unchecked {
          ++removed;
        }
      }
    }

    if (removed > 0) {
      emit OrdersCleanedUp(_pool, removed);
    }
  }

  /// @notice Internal function to remove an order and clean up all related storage
  /// @dev Removes from _poolOrderHashes, orderTokens, validatedHashes, and protocol-specific storage.
  ///      For CoWSwap orders, removal is only allowed if the order is complete (expired, filled,
  ///      or invalidated via GPv2Settlement.invalidateOrder()). This prevents unlocking tokens
  ///      while the order could still execute on the external protocol.
  /// @param _pool The pool address from which to remove the order
  /// @param _orderHash The hash of the order to remove
  function _removeOrder(address _pool, bytes32 _orderHash) internal {
    if (!_poolOrderHashes[_pool].contains(_orderHash)) {
      revert OrderNotFound(_pool, _orderHash);
    }

    OrderTokenInfo storage info = orderTokens[_pool][_orderHash];

    // For CoWSwap orders: only allow removal if order is complete
    // (expired, filled, or invalidated via GPv2Settlement.invalidateOrder)
    if (info.orderType == StructuredDataSupported.COWSWAP_ORDER) {
      bool notExpired = info.expiry > block.timestamp;
      bool notFilled = !_isOrderFilled(_pool, _orderHash, info);

      if (notExpired && notFilled) {
        revert OrderStillActive(_pool, _orderHash);
      }
    }

    _poolOrderHashes[_pool].remove(_orderHash);
    _cleanupOrderStorage(_pool, _orderHash, info.orderType);

    emit OrderRemoved(_pool, _orderHash);
  }

  /// @notice Clean up all storage associated with an order
  /// @dev Deletes orderTokens, validatedHashes, and protocol-specific storage
  /// @param _pool The pool address
  /// @param _orderHash The order hash
  /// @param _orderType The order type for protocol-specific cleanup
  function _cleanupOrderStorage(address _pool, bytes32 _orderHash, StructuredDataSupported _orderType) internal {
    // Clear the token info for this order (unlocks tokens)
    delete orderTokens[_pool][_orderHash];

    // Invalidate the hash
    delete validatedHashes[_pool][_orderHash];

    // Clean up protocol-specific storage
    if (_orderType == StructuredDataSupported.COWSWAP_ORDER) {
      delete cowSwapFillInfo[_pool][_orderHash];
    }
    // Future protocols: add their cleanup here
  }

  /// @notice Check if an order is filled based on its protocol type
  /// @dev Dispatches to protocol-specific fill checking logic
  /// @param _pool The pool address
  /// @param _orderHash The order hash
  /// @param _info The order token info containing order type
  /// @return True if the order is filled
  function _isOrderFilled(
    address _pool,
    bytes32 _orderHash,
    OrderTokenInfo storage _info
  ) internal view returns (bool) {
    if (_info.orderType == StructuredDataSupported.COWSWAP_ORDER) {
      return _isCowSwapOrderFilled(_pool, _orderHash, _info.expiry);
    }
    // Add future protocols in case any onchain fill tracking available
    // Return false - order is only "complete" when expired
    return false;
  }

  /// @notice Check if a CoWSwap order has been filled by querying GPv2Settlement
  /// @dev Computes orderUid from stored data and queries filledAmount
  /// @param _pool The pool address (also the order owner)
  /// @param _orderHash The order hash (EIP-712 digest)
  /// @param _expiry The order expiry timestamp (validTo)
  /// @return True if the order is fully filled
  function _isCowSwapOrderFilled(address _pool, bytes32 _orderHash, uint256 _expiry) internal view returns (bool) {
    CowSwapFillInfo storage fillInfo = cowSwapFillInfo[_pool][_orderHash];
    if (fillInfo.targetFillAmount == 0) {
      return false;
    }

    bytes memory configData = configs[StructuredDataSupported.COWSWAP_ORDER];
    if (configData.length == 0) {
      return false;
    }

    CowSwapOrderValidator.CowSwapValidationConfig memory config = abi.decode(
      configData,
      (CowSwapOrderValidator.CowSwapValidationConfig)
    );

    // Compute orderUid: orderHash + owner + validTo
    // owner = pool address, validTo = expiry (uint32)
    bytes memory orderUid = abi.encodePacked(_orderHash, _pool, uint32(_expiry));

    uint256 filled = IGPv2Settlement(config.gpv2Settlement).filledAmount(orderUid);
    return filled >= fillInfo.targetFillAmount;
  }

  function _setPoolFactory(address _poolFactory) internal {
    if (_poolFactory == address(0)) revert ZeroAddress("poolFactory");

    poolFactory = IPoolFactory(_poolFactory);
  }
}
