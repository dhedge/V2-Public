// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./IFactory.sol";
import "../../utils/TxDataUtils.sol";
import "../../interfaces/IERC20Extended.sol";
import "../../interfaces/IAssetHandler.sol";
import "../../interfaces/IHasGuardInfo.sol";
import "../../interfaces/IPoolLogic.sol";
import "../../interfaces/ITransactionTypes.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../utils/AddressHelper.sol";

/// @notice This contract allows for swapping between assets and pools with configurable swap fees and assets
contract PoolTokenSwapper is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, TxDataUtils {
  using MathUpgradeable for uint256;
  using SafeMathUpgradeable for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressHelper for address;

  struct AssetConfig {
    address asset;
    bool assetEnabled;
  }

  struct PoolConfig {
    address pool;
    uint256 poolSwapFee;
    bool poolEnabled;
  }

  struct SwapWhitelistConfig {
    address sender;
    bool status;
  }

  struct PoolData {
    uint256 poolSwapFee;
    bool poolEnabled;
  }

  address public poolFactory; // for dHedge guard protection
  address public poolLogic; // Uses the same name as PoolManagerLogic for guard compatibility
  address public manager; // Uses the same name as PoolManagerLogic for guard compatibility

  mapping(address => bool) public assetConfiguration;
  mapping(address => PoolData) public poolConfiguration;
  mapping(address => bool) public swapWhitelist;

  // solhint-disable-next-line var-name-mixedcase
  uint256 internal constant FEE_DENOMINATOR = 10_000;

  // Events
  event TokenSwapperTransactionExecuted(address indexed swapper, address indexed manager, uint16 transactionType);

  event Swap(
    address indexed user,
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );

  /// @dev Initializes the contract with the given parameters
  /// @param _factory The address of the pool factory contract
  /// @param _manager The address of the manager allowed to execute transactions
  /// @param _assetConfigs An array of AssetConfig structs containing the addresses of the assets
  /// @param _poolConfigs An array of PoolConfig structs containing the addresses of the pools and their swap fees
  /// @param _swapWhitelist An array of SwapWhitelistConfig structs containing the addresses and their swap whitelist status
  function initialize(
    address _factory,
    address _manager,
    AssetConfig[] calldata _assetConfigs,
    PoolConfig[] calldata _poolConfigs,
    SwapWhitelistConfig[] calldata _swapWhitelist
  ) external initializer {
    __Ownable_init();
    __Pausable_init();
    __ReentrancyGuard_init();
    poolLogic = address(this);
    poolFactory = _factory;
    _setManager(_manager);
    _setAssets(_assetConfigs);
    _setPools(_poolConfigs);
    _setSwapWhitelist(_swapWhitelist);
  }

  modifier onlySwapWhitelist() {
    require(swapWhitelist[msg.sender], "PTS: sender is not whitelisted");
    _;
  }

  /// @notice Only the manager specified in the contract can execute transactions
  modifier onlyManager() {
    require(msg.sender == manager, "PTS: only manager");
    _;
  }

  /// @dev Checks that the pool and asset are enabled
  /// @param _pool The address of the pool
  /// @param _asset The address of the asset
  modifier onlyEnabled(address _pool, address _asset) {
    require(poolConfiguration[_pool].poolEnabled && assetConfiguration[_asset], "PTS: pool/asset is not enabled");
    _;
  }

  /// @dev Checks that the pools are enabled
  /// @param _poolIn The address of the pool to swap from
  /// @param _poolOut The address of the pool to swap to
  modifier onlyEnabledPools(address _poolIn, address _poolOut) {
    require(
      poolConfiguration[_poolIn].poolEnabled && poolConfiguration[_poolOut].poolEnabled,
      "PTS: pool is not enabled"
    );
    _;
  }

  // ----- Swap related functions ----- //

  /// @notice Swaps between two assets or pools
  /// @dev Determines the type of swap (asset to pool, pool to asset, or pool to pool) and calls the corresponding swap function
  /// @param tokenIn Token to be swapped from
  /// @param tokenOut Token to be swapped to
  /// @param amountIn Amount of tokenIn to swap
  /// @param minAmountOut Minimum expected amount out from swap
  /// @return amountOut The amount of tokenOut received from the swap
  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut
  ) external nonReentrant whenNotPaused onlySwapWhitelist returns (uint256 amountOut) {
    (bool assetIn, bool poolIn, bool assetOut, bool poolOut) = _getSwapType(tokenIn, tokenOut);

    if (assetIn && poolOut) {
      // asset -> pool swap
      amountOut = swapAssetToPool(tokenIn, tokenOut, amountIn, minAmountOut);
    } else if (poolIn && assetOut) {
      // pool -> asset swap
      amountOut = swapPoolToAsset(tokenIn, tokenOut, amountIn, minAmountOut);
    } else if (poolIn && poolOut) {
      // pool -> pool swap
      amountOut = swapPoolToPool(tokenIn, tokenOut, amountIn, minAmountOut);
    } else {
      revert("invalid swap");
    }
  }

  /// @notice Swaps an asset for pool tokens
  /// @dev Calculates the amount of pool tokens to receive for the given amount of asset, transfers the asset from the user to this contract, and transfers the pool tokens to the user
  /// @param assetIn The address of the asset to swap from
  /// @param poolOut The address of the pool to swap to
  /// @param amountIn The amount of asset to swap
  /// @param minAmountOut The minimum amount of pool tokens to receive from the swap
  /// @return amountOut The amount of pool tokens received from the swap
  function swapAssetToPool(
    address assetIn,
    address poolOut,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal returns (uint256 amountOut) {
    amountOut = getAssetToPoolQuote(assetIn, poolOut, amountIn);

    require(amountOut >= minAmountOut, "PTS: price changed, try again");

    IERC20Upgradeable(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20Upgradeable(poolOut).safeTransfer(msg.sender, amountOut);

    emit Swap(msg.sender, assetIn, poolOut, amountIn, amountOut);
  }

  /// @notice Swaps pool tokens for an asset
  /// @dev Calculates the amount of asset to receive for the given amount of pool tokens, transfers the pool tokens from the user to this contract, and transfers the asset to the user
  /// @param poolIn The address of the pool to swap from
  /// @param assetOut The address of the asset to swap to
  /// @param amountIn The amount of pool tokens to swap
  /// @param minAmountOut The minimum amount of asset to receive from the swap
  /// @return amountOut The amount of asset received from the swap
  function swapPoolToAsset(
    address poolIn,
    address assetOut,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal returns (uint256 amountOut) {
    amountOut = getPoolToAssetQuote(poolIn, assetOut, amountIn);

    require(amountOut >= minAmountOut, "PTS: price changed, try again");

    IERC20Upgradeable(poolIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20Upgradeable(assetOut).safeTransfer(msg.sender, amountOut);

    emit Swap(msg.sender, poolIn, assetOut, amountIn, amountOut);
  }

  /// @notice Swaps pool tokens for pool tokens
  /// @dev Calculates the amount of pool tokens to receive for the given amount of pool tokens, transfers the pool tokens from the user to this contract, and transfers the pool tokens to the user
  /// @param poolIn The address of the pool to swap from
  /// @param poolOut The address of the pool to swap to
  /// @param amountIn The amount of pool tokens to swap
  /// @param minAmountOut The minimum amount of pool tokens to receive from the swap
  /// @return amountOut The amount of pool tokens received from the swap
  function swapPoolToPool(
    address poolIn,
    address poolOut,
    uint256 amountIn,
    uint256 minAmountOut
  ) internal returns (uint256 amountOut) {
    amountOut = getPoolToPoolQuote(poolIn, poolOut, amountIn);

    require(amountOut >= minAmountOut, "PTS: price changed, try again");

    IERC20Upgradeable(poolIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20Upgradeable(poolOut).safeTransfer(msg.sender, amountOut);

    emit Swap(msg.sender, poolIn, poolOut, amountIn, amountOut);
  }

  // ----- Manager functions ----- //

  /// @notice Function to let the pool manager execute whitelisted third party protocol functions eg swaps
  /// @dev Can only be executed by the manager account
  /// @dev Can only interact with a dHEDGE supported asset or contract, or dHEDGE pool
  /// @param to The destination address for pool to interact with
  /// @param data The data that going to be sent in the transaction
  /// @return success A boolean for success or failure of the transaction
  function execTransaction(
    address to,
    bytes calldata data
  ) external nonReentrant whenNotPaused onlyManager returns (bool success) {
    require(to != address(0), "PTS: non-zero address required");

    address contractGuard = IHasGuardInfo(poolFactory).getContractGuard(to);
    address guard;
    uint16 txType;

    if (contractGuard != address(0)) {
      guard = contractGuard;
      (txType, ) = IGuard(guard).txGuard(address(this), to, data);
    } else {
      if (assetConfiguration[to] || poolConfiguration[to].poolEnabled) {
        guard = IHasGuardInfo(poolFactory).getAssetGuard(to);
        (txType, ) = IGuard(guard).txGuard(address(this), to, data);
      }
    }

    // Pass tx if withdrawing from the pool directly
    // Note: this isn't supported by standard dHEDGE pools because of multiple assets the pool receives
    if (txType == 0 && IFactory(poolFactory).isPool(to)) {
      bytes4 method = getMethod(data);

      if (method == IPoolLogic.withdraw.selector) {
        txType = uint16(ITransactionTypes.TransactionType.EasySwapperWithdraw);
      }
    }

    require(txType > 0, "PTS: invalid transaction");

    success = to.tryAssemblyCall(data);
    require(success, "PTS: transaction failed");

    emit TokenSwapperTransactionExecuted(address(this), manager, txType);
  }

  // ----- Owner functions ----- //

  /// @notice Sets the addresses and enabled statuses of the assets
  /// @dev Can only be called by the owner
  /// @param _assetConfigs An array of AssetConfig structs containing the addresses of the assets
  function setAssets(AssetConfig[] calldata _assetConfigs) external onlyOwner {
    _setAssets(_assetConfigs);
  }

  /// @notice Sets the addresses and enabled statuses of the pools and their swap fees
  /// @dev Can only be called by the owner
  /// @param _poolConfigs An array of PoolConfig structs containing the addresses of the pools and their swap fees
  function setPools(PoolConfig[] calldata _poolConfigs) external onlyOwner {
    _setPools(_poolConfigs);
  }

  /// @notice Sets the manager account to manage the assets inside the vault
  /// @dev Can only be called by the owner
  /// @param _manager The manager account
  function setManager(address _manager) external onlyOwner {
    _setManager(_manager);
  }

  /// @notice Sets the addresses which can swap with this contract
  /// @dev Can only be called by the owner
  /// @param _swapWhitelist An array of SwapWhitelistConfig structs containing the addresses and their swap whitelist status
  function setSwapWhitelist(SwapWhitelistConfig[] calldata _swapWhitelist) external onlyOwner {
    _setSwapWhitelist(_swapWhitelist);
  }

  /// @notice Allows the contract owner to withdraw any ERC20 token in the contract
  /// @dev Can only be called by the owner
  /// @param _token The address of the ERC20 token
  /// @param _amount The amount of the ERC20 token to withdraw
  function salvage(IERC20Upgradeable _token, uint256 _amount) external onlyOwner {
    _token.safeTransfer(msg.sender, _amount);
  }

  /// @notice Pauses the contract
  /// @dev Can only be called by the owner
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice Unpauses the contract
  /// @dev Can only be called by the owner
  function unpause() external onlyOwner {
    _unpause();
  }

  // ----- Public view functions ----- //

  /// @notice The dHEDGE pool factory
  /// @dev Uses the same name `factory` as PoolManagerLogic for guard compatibility
  /// @return The address of the pool factory
  function factory() external view returns (address) {
    return poolFactory;
  }

  /// @notice Returns true for any asset supported by dHedge
  /// @param asset The address of the asset
  /// @return supported if the asset is supported by dHedge
  function isSupportedAsset(address asset) external view returns (bool supported) {
    address _assetHandler = IFactory(poolFactory).getAssetHandler();
    supported = IAssetHandler(_assetHandler).priceAggregators(asset) != address(0);
  }

  // ----- Quote related functions ----- //

  /// @notice Gets an amount out quote for any type of swap (pool or asset)
  /// @notice The quote includes swap fees
  /// @dev If input assets are invalid, it reverts
  /// @param tokenIn swap from token address (pool or asset)
  /// @param tokenOut swap to token address (pool or asset)
  /// @param amountIn swap from token amount
  /// @return amountOut swap to quote amount
  function getSwapQuote(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut) {
    (bool assetIn, bool poolIn, bool assetOut, bool poolOut) = _getSwapType(tokenIn, tokenOut);

    if (assetIn && poolOut) {
      // asset -> pool swap
      amountOut = getAssetToPoolQuote(tokenIn, tokenOut, amountIn);
    } else if (poolIn && assetOut) {
      // pool -> asset swap
      amountOut = getPoolToAssetQuote(tokenIn, tokenOut, amountIn);
    } else if (poolIn && poolOut) {
      // pool -> pool swap
      amountOut = getPoolToPoolQuote(tokenIn, tokenOut, amountIn);
    } else {
      revert("invalid quote assets");
    }
  }

  /// @notice Gets an amount out quote for an asset to pool swap
  /// @notice The quote includes swap fees
  /// @param assetIn swap from asset address
  /// @param poolOut swap to pool address
  /// @param amountIn swap from asset amount
  /// @return amountOut swap to quote amount
  function getAssetToPoolQuote(
    address assetIn,
    address poolOut,
    uint256 amountIn
  ) internal view onlyEnabled(poolOut, assetIn) returns (uint256 amountOut) {
    uint8 decimalsIn = IERC20Extended(assetIn).decimals();
    uint256 poolTokenPrice18 = IPoolLogic(poolOut).tokenPrice();
    uint256 assetPrice18 = IFactory(poolFactory).getAssetPrice(assetIn);
    uint256 assetValue18 = amountIn.mul(assetPrice18).div(10 ** decimalsIn);
    amountOut = assetValue18.mul(10 ** 18).div(poolTokenPrice18);

    uint256 swapFee = _getSwapFee(amountOut, poolOut);

    // subtract swap fee
    amountOut = amountOut.sub(swapFee);
    require(amountOut > 0, "PTS: error on amount out");
  }

  /// @notice Gets an amount out quote for a pool to asset swap
  /// @notice The quote includes swap fees
  /// @param poolIn swap from pool address
  /// @param assetOut swap to asset address
  /// @param amountIn swap from pool amount
  /// @return amountOut swap to quote amount
  function getPoolToAssetQuote(
    address poolIn,
    address assetOut,
    uint256 amountIn
  ) internal view onlyEnabled(poolIn, assetOut) returns (uint256 amountOut) {
    uint8 toDecimals = IERC20Extended(assetOut).decimals();
    uint256 poolTokenPrice18 = IPoolLogic(poolIn).tokenPrice();
    uint256 assetPrice18 = IFactory(poolFactory).getAssetPrice(assetOut);
    uint256 poolValue18 = amountIn.mul(poolTokenPrice18).div(10 ** 18);
    amountOut = poolValue18.mul(10 ** toDecimals).div(assetPrice18);

    uint256 swapFee = _getSwapFee(amountOut, poolIn);

    // subtract swap fee
    amountOut = amountOut.sub(swapFee);
    require(amountOut > 0, "PTS: error on amount out");
  }

  /// @notice Gets an amount out quote for a pool to pool swap
  /// @notice The quote includes swap fees
  /// @param poolIn swap from pool address
  /// @param poolOut swap to pool address
  /// @param amountIn swap from pool amount
  /// @return amountOut swap to quote amount
  function getPoolToPoolQuote(
    address poolIn,
    address poolOut,
    uint256 amountIn
  ) internal view onlyEnabledPools(poolIn, poolOut) returns (uint256 amountOut) {
    uint256 poolInTokenPrice18 = IPoolLogic(poolIn).tokenPrice();
    uint256 poolToTokenPrice18 = IPoolLogic(poolOut).tokenPrice();
    uint256 poolInValue18 = amountIn.mul(poolInTokenPrice18).div(10 ** 18);
    amountOut = poolInValue18.mul(10 ** 18).div(poolToTokenPrice18);

    uint256 swapFeeIn = _getSwapFee(amountOut, poolIn);
    uint256 swapFeeOut = _getSwapFee(amountOut, poolOut);

    // subtract swap fee
    // selects the max of from/to pool swap fee
    amountOut = amountOut.sub(swapFeeIn.max(swapFeeOut));
    require(amountOut > 0, "PTS: error on amount out");
  }

  // ----- Private functions ----- //

  function _setAssets(AssetConfig[] calldata _assetsConfigs) private {
    for (uint256 i = 0; i < _assetsConfigs.length; i++) {
      require(IFactory(poolFactory).isValidAsset(_assetsConfigs[i].asset), "PTS: asset is not valid");
      require(!IFactory(poolFactory).isPool(_assetsConfigs[i].asset), "PTS: cannot set pool as asset");
      assetConfiguration[_assetsConfigs[i].asset] = _assetsConfigs[i].assetEnabled;
    }
  }

  function _setPools(PoolConfig[] calldata _poolConfigs) private {
    for (uint256 i = 0; i < _poolConfigs.length; i++) {
      require(IFactory(poolFactory).isPool(_poolConfigs[i].pool), "PTS: is not a pool");
      poolConfiguration[_poolConfigs[i].pool].poolEnabled = _poolConfigs[i].poolEnabled;
      poolConfiguration[_poolConfigs[i].pool].poolSwapFee = _poolConfigs[i].poolSwapFee;
    }
  }

  function _setManager(address _manager) private {
    require(_manager != address(0), "PTS: invalid manager address");
    manager = _manager;
  }

  function _setSwapWhitelist(SwapWhitelistConfig[] calldata _swapWhitelist) private {
    for (uint256 i = 0; i < _swapWhitelist.length; i++) {
      swapWhitelist[_swapWhitelist[i].sender] = _swapWhitelist[i].status;
    }
  }

  function _getSwapFee(uint256 _amountOut, address _pool) private view returns (uint256 swapFeeAmount) {
    swapFeeAmount = _amountOut.mul(poolConfiguration[_pool].poolSwapFee).div(FEE_DENOMINATOR);
    require(swapFeeAmount > 0, "PTS: invalid swap fee");
  }

  function _getSwapType(
    address _tokenIn,
    address _tokenOut
  ) private view returns (bool assetIn, bool poolIn, bool assetOut, bool poolOut) {
    if (poolConfiguration[_tokenIn].poolEnabled) poolIn = true;
    if (poolConfiguration[_tokenOut].poolEnabled) poolOut = true;
    if (assetConfiguration[_tokenIn]) assetIn = true;
    if (assetConfiguration[_tokenOut]) assetOut = true;
  }
}
