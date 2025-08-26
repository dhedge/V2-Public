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
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/v5/contracts/utils/structs/EnumerableSet.sol";

import {ISwapDataConsumingGuard} from "../interfaces/guards/ISwapDataConsumingGuard.sol";
import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IPoolLogic} from "../interfaces/IPoolLogic.sol";
import {IEasySwapperV2} from "../swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "../swappers/easySwapperV2/interfaces/IWithdrawalVault.sol";

contract PoolLimitOrderManager is OwnableUpgradeable {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableSet for EnumerableSet.AddressSet;

  ////////////////////////////////
  //           Events           //
  ////////////////////////////////

  event LimitOrderCreated(address indexed user, address indexed pool, bytes32 id);
  event LimitOrderDeleted(address indexed user, address indexed pool, bytes32 id);
  event LimitOrderModified(address indexed user, address indexed pool, bytes32 id);
  event LimitOrderExecuted(address indexed user, address indexed pool, bytes32 id);
  event LimitOrderExecutedPartially(address indexed user, address indexed pool, bytes32 id, uint256 amount);
  event LimitOrderExecutionFailed(bytes32 id, bytes reason);
  event SettlementOrderCreated(address indexed user);
  event SettlementOrderDeleted(address indexed user);
  event SettlementOrderExecuted(address indexed user, uint256 destTokenAmountReceived);
  event SettlementOrderExecutionFailed(address user, bytes reason);
  event AuthorizedKeeperAdded(address keeper);
  event AuthorizedKeeperRemoved(address keeper);
  event SlippageToleranceSet(uint16 slippageTolerance);
  event SettlementTokenSet(address token);

  ////////////////////////////////
  //           Errors           //
  ////////////////////////////////

  error InvalidPool(address pool);
  error InvalidAsset(address asset);
  error ZeroAddress(string varName);
  error InvalidValue(string varName);
  error NotAuthorizedKeeper(address caller);
  error SettlementOrderNotFound(address user);
  error LimitOrderNotFound(bytes32 id);
  error LimitOrderAlreadyExists(address user, address pool);
  error LimitOrderNotFillable(uint256 currentPriceD18, uint256 stopLossPriceD18, uint256 takeProfitPriceD18);
  error InvalidPrices(uint256 stopLossPriceD18, uint256 takeProfitPriceD18, uint256 currentPrice);
  error ExternalCallerNotAllowed();
  error LimitOrderNotDeletable(address user, address pool);

  ////////////////////////////////
  //      Structs & Enums       //
  ////////////////////////////////

  /// @notice Struct containing information about a limit order as provided by the user.
  /// @param amount The amount of pool tokens to redeem for the limit order.
  /// @param stopLossPriceD18 The price at which to execute a stop-loss order.
  /// @param takeProfitPriceD18 The price at which to execute a take-profit order.
  /// @param user The address of the user who created the limit order.
  /// @param pool The address of the pool for which the limit order is created.
  /// @param pricingAsset The address of the asset to determine the price at which to execute a limit order.
  struct LimitOrderInfo {
    uint256 amount;
    uint256 stopLossPriceD18;
    uint256 takeProfitPriceD18;
    address user;
    address pool;
    address pricingAsset;
  }

  struct LimitOrderExecution {
    bytes32 orderId;
    IPoolLogic.ComplexAsset[] complexAssetsData;
    uint256 amount;
  }

  struct SettlementOrderExecution {
    address user;
    IWithdrawalVault.MultiInSingleOutData swapData;
  }

  uint16 public constant SLIPPAGE_DENOMINATOR = 10_000;

  ////////////////////////////////
  //          State             //
  ////////////////////////////////

  IPoolFactory public poolFactory;

  IEasySwapperV2 public easySwapper;

  /// @notice Default slippage tolerance for all swaps in all order executions.
  /// @dev Must be a value greater than 0 and less than 10_000.
  uint16 public defaultSlippageTolerance;

  /// @notice The address of the token to receive when a settlement order is executed, e.g. USDC.
  address public limitOrderSettlementToken;

  /// @notice Used to add and remove limit orders.
  /// @dev Mapping of order identifier to the limit order details if one exists.
  mapping(bytes32 orderId => LimitOrderInfo limitOrder) public limitOrders;

  /// @notice Mapping for storing authorized keeper addresses.
  mapping(address keeper => bool isAuthorized) public isAuthorizedKeeper;

  /// @dev Mostly useful for fetching all the limit order IDs.
  EnumerableSet.Bytes32Set private limitOrderIds;

  /// @dev Mostly useful for fetching all the users to settle.
  EnumerableSet.AddressSet private usersToSettle;

  ////////////////////////////////
  //          Modifiers         //
  ////////////////////////////////

  modifier onlyAuthorizedKeeper() {
    if (!isAuthorizedKeeper[msg.sender]) revert NotAuthorizedKeeper(msg.sender);
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  ////////////////////////////////
  //          Functions         //
  ////////////////////////////////

  function initialize(
    address admin_,
    IPoolFactory poolFactory_,
    IEasySwapperV2 easySwapper_,
    uint16 defaultSlippageTolerance_,
    address limitOrderSettlementToken_
  ) external initializer {
    __Ownable_init(admin_);

    _setPoolFactory(poolFactory_);
    _setEasySwapper(easySwapper_);
    _setDefaultSlippageTolerance(defaultSlippageTolerance_);
    _setLimitOrderSettlementToken(limitOrderSettlementToken_, poolFactory_);
  }

  ////////////////////////////////
  //       User Functions       //
  ////////////////////////////////

  /// @notice Function to create a new limit order.
  /// @param limitOrderInfo_ The limit order information.
  function createLimitOrder(LimitOrderInfo calldata limitOrderInfo_) external {
    _validateLimitOrderInfo(limitOrderInfo_);

    bytes32 newLimitOrderId = _getLimitOrderId(msg.sender, limitOrderInfo_.pool);

    // Check that a limit order for the same pool and user doesn't already exist.
    if (limitOrderIds.contains(newLimitOrderId))
      revert LimitOrderAlreadyExists(limitOrderInfo_.user, limitOrderInfo_.pool);

    limitOrders[newLimitOrderId] = limitOrderInfo_;
    limitOrderIds.add(newLimitOrderId);

    emit LimitOrderCreated(msg.sender, limitOrderInfo_.pool, newLimitOrderId);
  }

  /// @notice Function to modify any or all parameters of a limit order.
  /// @dev Note that if a user doesn't want to change a particular price (eg, stopLossPriceD18) then they should pass the existing
  ///      price as the new price.
  /// @dev Technically, a user can modify an existing limit order such that it becomes unexecutable.
  /// @param modificationInfo_ The limit order modification information.
  function modifyLimitOrder(LimitOrderInfo calldata modificationInfo_) external {
    _validateLimitOrderInfo(modificationInfo_);

    bytes32 orderId = _getLimitOrderId(msg.sender, modificationInfo_.pool);

    if (!limitOrderIds.contains(orderId)) revert LimitOrderNotFound(orderId);

    limitOrders[orderId] = modificationInfo_;

    emit LimitOrderModified(msg.sender, modificationInfo_.pool, orderId);
  }

  /// @notice Deletes a limit order for a pool.
  /// @param pool_ The address of the pool to delete a limit order for.
  function deleteLimitOrder(address pool_) external {
    _removeLimitOrder(_getLimitOrderId(msg.sender, pool_));
  }

  ////////////////////////////////
  //       Keeper Functions     //
  ////////////////////////////////

  /// @notice Execute multiple limit orders in a single transaction.
  /// @dev This function assumes that users have already approved the pool token transfers to this contract.
  /// @param orders_ Array of limit order executions.
  function executeLimitOrders(LimitOrderExecution[] calldata orders_) external onlyAuthorizedKeeper {
    for (uint256 i; i < orders_.length; ++i) {
      this._executeLimitOrder(orders_[i]);
    }
  }

  /// @notice Execute multiple limit orders in a single transaction, continuing even if some orders fail.
  /// @dev This function will not revert if individual order executions fail.
  /// @param orders_ Array of limit order executions.
  function executeLimitOrdersSafe(LimitOrderExecution[] calldata orders_) external onlyAuthorizedKeeper {
    for (uint256 i; i < orders_.length; ++i) {
      // solhint-disable-next-line no-empty-blocks
      try this._executeLimitOrder(orders_[i]) {} catch (bytes memory reason) {
        emit LimitOrderExecutionFailed(orders_[i].orderId, reason);
      }
    }
  }

  /// @notice Execute multiple settlement orders in a single transaction.
  /// @param orders_ Array of order IDs and their corresponding swap data.
  function executeSettlementOrders(SettlementOrderExecution[] calldata orders_) external onlyAuthorizedKeeper {
    for (uint256 i; i < orders_.length; ++i) {
      this._executeSettlementOrder(orders_[i].user, orders_[i].swapData);
    }
  }

  /// @notice Execute multiple settlement orders in a single transaction, continuing even if some orders fail.
  /// @dev This function will not revert if individual order executions fail.
  /// @param orders_ Array of settlement order executions.
  function executeSettlementOrdersSafe(SettlementOrderExecution[] calldata orders_) external onlyAuthorizedKeeper {
    for (uint256 i; i < orders_.length; ++i) {
      // solhint-disable-next-line no-empty-blocks
      try this._executeSettlementOrder(orders_[i].user, orders_[i].swapData) {} catch (bytes memory reason) {
        emit SettlementOrderExecutionFailed(orders_[i].user, reason);
      }
    }
  }

  /// @notice This function will delete all limit orders for the specified order IDs.
  /// @dev Will revert if any of the order IDs are not found or conditions for deletion are not met.
  /// @param orderIds_ The array of order IDs to delete.
  function deleteLimitOrders(bytes32[] calldata orderIds_) external onlyAuthorizedKeeper {
    for (uint256 i; i < orderIds_.length; ++i) {
      LimitOrderInfo memory deletedOrder = _removeLimitOrder(orderIds_[i]);

      // Check if the limit order can be deleted based on user's balance and allowance
      if (!_canDeleteLimitOrder(deletedOrder)) {
        revert LimitOrderNotDeletable(deletedOrder.user, deletedOrder.pool);
      }
    }
  }

  /// @notice Returns all the limit order IDs.
  /// @return limitOrderIds_ The array of all the limit order IDs.
  function getAllLimitOrderIds() external view returns (bytes32[] memory limitOrderIds_) {
    return limitOrderIds.values();
  }

  /// @notice Returns all the single asset swap settlement order IDs.
  /// @return usersToSettle_ The array of all the single asset swap settlement order IDs.
  function getAllUsersToSettle() external view returns (address[] memory usersToSettle_) {
    return usersToSettle.values();
  }

  ////////////////////////////////
  // Internal/Private Functions //
  ////////////////////////////////

  function _executeLimitOrder(LimitOrderExecution calldata orderExecutionData_) external {
    if (msg.sender != address(this)) revert ExternalCallerNotAllowed();

    if (!limitOrderIds.contains(orderExecutionData_.orderId)) revert LimitOrderNotFound(orderExecutionData_.orderId);

    LimitOrderInfo memory limitOrder = limitOrders[orderExecutionData_.orderId];

    if (orderExecutionData_.amount < limitOrder.amount) {
      limitOrders[orderExecutionData_.orderId].amount -= orderExecutionData_.amount;

      emit LimitOrderModified(limitOrder.user, limitOrder.pool, orderExecutionData_.orderId);

      _processLimitOrderExecution(limitOrder, orderExecutionData_.complexAssetsData, orderExecutionData_.amount);

      emit LimitOrderExecutedPartially(
        limitOrder.user,
        limitOrder.pool,
        orderExecutionData_.orderId,
        orderExecutionData_.amount
      );
    } else {
      delete limitOrders[orderExecutionData_.orderId];
      limitOrderIds.remove(orderExecutionData_.orderId);

      emit LimitOrderDeleted(limitOrder.user, limitOrder.pool, orderExecutionData_.orderId);

      _processLimitOrderExecution(limitOrder, orderExecutionData_.complexAssetsData, limitOrder.amount);

      emit LimitOrderExecuted(limitOrder.user, limitOrder.pool, orderExecutionData_.orderId);
    }
  }

  function _processLimitOrderExecution(
    LimitOrderInfo memory limitOrder_,
    IPoolLogic.ComplexAsset[] calldata complexAssetsData_,
    uint256 amountToRedeem_
  ) internal {
    uint256 currentPriceD18 = poolFactory.getAssetPrice(limitOrder_.pricingAsset);

    if (currentPriceD18 > limitOrder_.stopLossPriceD18 && currentPriceD18 < limitOrder_.takeProfitPriceD18)
      revert LimitOrderNotFillable(currentPriceD18, limitOrder_.stopLossPriceD18, limitOrder_.takeProfitPriceD18);

    _validateComplexAssetsData(complexAssetsData_);

    // Pool address assumed to be valid, as limit order can be created only for valid pools.
    IERC20(limitOrder_.pool).safeTransferFrom(limitOrder_.user, address(this), amountToRedeem_);

    IERC20(limitOrder_.pool).safeIncreaseAllowance(address(easySwapper), amountToRedeem_);

    // This will redeem the pool token balance and the withdrawal vault belonging to the user
    // will receive multiple assets which are the underlying assets of the pool.
    easySwapper.initLimitOrderWithdrawalFor(limitOrder_.user, limitOrder_.pool, amountToRedeem_, complexAssetsData_);

    bool justAdded = usersToSettle.add(limitOrder_.user);

    if (justAdded) emit SettlementOrderCreated(limitOrder_.user);
  }

  function _executeSettlementOrder(address user_, IWithdrawalVault.MultiInSingleOutData calldata swapData_) external {
    if (msg.sender != address(this)) revert ExternalCallerNotAllowed();

    _removeSettlementOrder(user_);

    IWithdrawalVault.TrackedAsset[] memory assetsInVault = easySwapper.getTrackedAssetsFromLimitOrders(user_);

    // Stops order execution after removing order from storage. That means order has been settled by someone manually via EasySwapperV2 and doesn't need to be stored.
    if (assetsInVault.length == 0) return;

    // Check that the destination token is the same as settlement token.
    if (address(swapData_.destData.destToken) != limitOrderSettlementToken)
      revert InvalidAsset(address(swapData_.destData.destToken));

    IPoolFactory cachedPoolFactory = poolFactory;
    uint256 vaultTotalValueD18;

    // Get total value of tokens in user's vault.
    for (uint256 i; i < assetsInVault.length; ++i) {
      vaultTotalValueD18 +=
        (cachedPoolFactory.getAssetPrice(assetsInVault[i].token) * assetsInVault[i].balance) /
        (10 ** IERC20Metadata(assetsInVault[i].token).decimals());
    }

    // Apply allowed slippage tolerance to that value.
    uint256 minValueToReceiveD18 = (vaultTotalValueD18 * (SLIPPAGE_DENOMINATOR - defaultSlippageTolerance)) /
      SLIPPAGE_DENOMINATOR;

    // Calculate the minimum amount of settlement token to receive.
    uint256 minSettlementTokenToReceive = (minValueToReceiveD18 *
      (10 ** IERC20Metadata(limitOrderSettlementToken).decimals())) /
      cachedPoolFactory.getAssetPrice(limitOrderSettlementToken);

    uint256 settlementTokenAmountReceived = easySwapper.completeLimitOrderWithdrawalFor(
      user_,
      swapData_,
      minSettlementTokenToReceive
    );

    emit SettlementOrderExecuted(user_, settlementTokenAmountReceived);
  }

  function _removeLimitOrder(bytes32 orderId_) internal returns (LimitOrderInfo memory deletedOrder_) {
    if (!limitOrderIds.contains(orderId_)) revert LimitOrderNotFound(orderId_);

    deletedOrder_ = limitOrders[orderId_];

    delete limitOrders[orderId_];
    limitOrderIds.remove(orderId_);

    emit LimitOrderDeleted(deletedOrder_.user, deletedOrder_.pool, orderId_);
  }

  function _removeSettlementOrder(address user_) internal {
    if (!usersToSettle.contains(user_)) revert SettlementOrderNotFound(user_);

    usersToSettle.remove(user_);

    emit SettlementOrderDeleted(user_);
  }

  function _canDeleteLimitOrder(LimitOrderInfo memory limitOrder_) internal view returns (bool) {
    // Check if user's pool token balance is 0, maybe they withdrew manually.
    uint256 userBalance = IERC20(limitOrder_.pool).balanceOf(limitOrder_.user);
    if (userBalance == 0) return true;

    // Check if user has revoked approval for their pool tokens (rare, but possible).
    uint256 allowance = IERC20(limitOrder_.pool).allowance(limitOrder_.user, address(this));
    if (allowance == 0) return true;

    return false;
  }

  function _setDefaultSlippageTolerance(uint16 defaultSlippageTolerance_) internal {
    if (defaultSlippageTolerance_ == 0 || defaultSlippageTolerance_ > SLIPPAGE_DENOMINATOR)
      revert InvalidValue("slippage");

    defaultSlippageTolerance = defaultSlippageTolerance_;

    emit SlippageToleranceSet(defaultSlippageTolerance_);
  }

  function _setPoolFactory(IPoolFactory poolFactory_) internal {
    if (address(poolFactory_) == address(0)) revert ZeroAddress("poolFactory");

    poolFactory = poolFactory_;
  }

  function _setEasySwapper(IEasySwapperV2 easySwapper_) internal {
    if (address(easySwapper_) == address(0)) revert ZeroAddress("easySwapper");

    easySwapper = easySwapper_;
  }

  function _setLimitOrderSettlementToken(address limitOrderSettlementToken_, IPoolFactory poolFactory_) internal {
    if (!poolFactory_.isValidAsset(limitOrderSettlementToken_)) revert InvalidAsset(limitOrderSettlementToken_);

    limitOrderSettlementToken = limitOrderSettlementToken_;

    emit SettlementTokenSet(limitOrderSettlementToken_);
  }

  function _validateLimitOrderInfo(LimitOrderInfo memory limitOrderInfo_) internal view {
    // Don't allow the user to create a limit order for another user.
    if (limitOrderInfo_.user != msg.sender) revert InvalidValue("user");

    IPoolFactory cachedPoolFactory = poolFactory;

    // Validate if pool address set is actually a pool.
    if (!cachedPoolFactory.isPool(limitOrderInfo_.pool)) revert InvalidPool(limitOrderInfo_.pool);

    uint256 userPoolTokenBalance = IPoolLogic(limitOrderInfo_.pool).balanceOf(limitOrderInfo_.user);

    // Validate if the user has enough pool tokens to create a limit order for.
    if (limitOrderInfo_.amount == 0 || userPoolTokenBalance < limitOrderInfo_.amount) revert InvalidValue("amount");

    // Check that the pricing asset is valid (has a price aggregator set).
    if (!cachedPoolFactory.isValidAsset(limitOrderInfo_.pricingAsset))
      revert InvalidAsset(limitOrderInfo_.pricingAsset);

    uint256 currentPriceD18 = cachedPoolFactory.getAssetPrice(limitOrderInfo_.pricingAsset);

    // Check that the prices are valid.
    if (limitOrderInfo_.stopLossPriceD18 >= currentPriceD18 || limitOrderInfo_.takeProfitPriceD18 <= currentPriceD18)
      revert InvalidPrices(limitOrderInfo_.stopLossPriceD18, limitOrderInfo_.takeProfitPriceD18, currentPriceD18);
  }

  /// @dev Make sure that specified slippage tolerance is not greater than the allowed.
  ///      On the other hand, if we keep order execution to authorized keepers only, this validation can be removed.
  ///      This is important as revert can prevent from executing the order.
  function _validateComplexAssetsData(IPoolLogic.ComplexAsset[] memory complexAssetsData_) internal view {
    for (uint256 i; i < complexAssetsData_.length; ++i) {
      if (complexAssetsData_[i].withdrawData.length == 0) {
        if (
          complexAssetsData_[i].slippageTolerance == 0 ||
          complexAssetsData_[i].slippageTolerance > defaultSlippageTolerance
        ) revert InvalidValue("slippage");
        continue;
      }

      ISwapDataConsumingGuard.ComplexAssetSwapData memory withdrawData = abi.decode(
        complexAssetsData_[i].withdrawData,
        (ISwapDataConsumingGuard.ComplexAssetSwapData)
      );
      if (
        withdrawData.slippageTolerance != complexAssetsData_[i].slippageTolerance ||
        withdrawData.slippageTolerance > defaultSlippageTolerance
      ) revert InvalidValue("slippage");
    }
  }

  /// @dev Function to get a new limit order ID.
  /// @dev Note that the order id may not be unique across different time periods.
  ///      However, there will never be two or more limit orders with the same id.
  /// @dev The returned order id can be used for confirming the existence of a limit order by checking the limitOrderIds set.
  function _getLimitOrderId(address user_, address pool_) internal pure returns (bytes32 orderId_) {
    return keccak256(abi.encodePacked(user_, pool_));
  }

  ////////////////////////////////
  //       Owner Functions      //
  ////////////////////////////////

  /// @notice Function to add an authorized keeper.
  /// @param keeper_ The address of the keeper to add.
  function addAuthorizedKeeper(address keeper_) external onlyOwner {
    isAuthorizedKeeper[keeper_] = true;

    emit AuthorizedKeeperAdded(keeper_);
  }

  /// @notice Function to remove an authorized keeper.
  /// @param keeper_ The address of the keeper to remove.
  function removeAuthorizedKeeper(address keeper_) external onlyOwner {
    isAuthorizedKeeper[keeper_] = false;

    emit AuthorizedKeeperRemoved(keeper_);
  }

  /// @notice Function to set the default slippage tolerance for all swaps in all order executions.
  /// @param defaultSlippageTolerance_ The default slippage tolerance to set.
  function setDefaultSlippageTolerance(uint16 defaultSlippageTolerance_) external onlyOwner {
    _setDefaultSlippageTolerance(defaultSlippageTolerance_);
  }

  /// @notice Function to set the pool factory contract address.
  /// @param poolFactory_ The pool factory contract address to set.
  function setPoolFactory(IPoolFactory poolFactory_) external onlyOwner {
    _setPoolFactory(poolFactory_);
  }

  /// @notice Function to set the easy swapper contract address.
  /// @param easySwapper_ The easy swapper contract address to set.
  function setEasySwapper(IEasySwapperV2 easySwapper_) external onlyOwner {
    _setEasySwapper(easySwapper_);
  }

  /// @notice Function to set the token to receive when a settlement order is executed.
  /// @param limitOrderSettlementToken_ The token to receive when a settlement order is executed.
  function setLimitOrderSettlementToken(address limitOrderSettlementToken_) external onlyOwner {
    _setLimitOrderSettlementToken(limitOrderSettlementToken_, poolFactory);
  }
}
