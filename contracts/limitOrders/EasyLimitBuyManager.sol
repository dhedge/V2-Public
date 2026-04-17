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

import {SafeERC20} from "@openzeppelin/v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20 as IERC20OZ} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";

import {AuthorizedKeepers} from "../utils/keepers/AuthorizedKeepers.sol";

import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ISignatureTransfer} from "../interfaces/permit2/ISignatureTransfer.sol";
import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IPoolLogic} from "../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../interfaces/IPoolManagerLogic.sol";
import {IEasySwapperV2} from "../swappers/easySwapperV2/interfaces/IEasySwapperV2.sol";
import {ISwapper} from "../interfaces/flatMoney/swapper/ISwapper.sol";
import {EasyLimitBuyTypeHashLib} from "./EasyLimitBuyTypeHashLib.sol";

/// @title EasyLimitBuyManager
/// @notice Manages limit buy orders for dHEDGE vaults using Permit2 signatures
/// @dev Users sign EIP-712 messages off-chain, keepers execute when price conditions are met
contract EasyLimitBuyManager is AuthorizedKeepers, ICommonErrors {
  using SafeERC20 for IERC20OZ;

  // ============ Constants ============

  uint16 public constant MAX_SLIPPAGE_BPS = 500; // 5% max slippage
  uint16 public constant SLIPPAGE_DENOMINATOR = 10_000;
  uint256 public constant DEFAULT_COOLDOWN = 1 days;

  // ============ State ============

  /// @notice Permit2 contract address
  ISignatureTransfer public immutable permit2;

  /// @notice dHEDGE pool factory
  IPoolFactory public immutable poolFactory;

  /// @notice EasySwapperV2 for cooldown/swapper/depositQuote
  IEasySwapperV2 public immutable easySwapperV2;

  // ============ Structs ============

  /// @notice Internal struct to reduce stack depth in _fillLimitBuy
  struct FillExecution {
    bytes32 orderHash;
    address depositToken;
    uint256 depositAmount;
    uint256 vaultTokensReceived;
    uint256 minVaultTokens;
  }

  /// @notice Swap data for zap operations (token/amount derived from permit)
  /// @param aggregatorData Router key and calldata for the swap
  /// @param destData Destination token and minimum output amount
  struct ZapData {
    ISwapper.AggregatorData aggregatorData;
    ISwapper.DestData destData;
  }

  /// @notice Parameters for a single limit buy execution in batch
  struct LimitBuyExecution {
    EasyLimitBuyTypeHashLib.LimitBuyOrder order;
    ISignatureTransfer.PermitTransferFrom permit;
    bytes signature;
    ZapData zapData;
  }

  // ============ Events ============

  event LimitBuyFilled(
    bytes32 indexed orderHash,
    address indexed user,
    address indexed targetVault,
    address inputToken,
    uint256 inputAmount,
    uint256 vaultTokensReceived
  );

  event LimitBuyFillFailed(bytes32 indexed orderHash, address indexed owner, bytes reason);

  // ============ Errors ============

  error PriceConditionNotMet(uint256 currentPrice, uint256 minPrice, uint256 maxPrice);
  error InvalidPriceRange(uint256 minPrice, uint256 maxPrice);
  error InvalidDepositAssetConfig(bool useZap, address inputToken, address zapDestToken, bool isDepositAsset);
  error InvalidSlippage(uint16 slippageBps);
  error InsufficientVaultTokensReceived(uint256 expected, uint256 received);

  /// @param _admin Contract admin/owner
  /// @param _permit2 Permit2 contract address
  /// @param _poolFactory dHEDGE pool factory
  /// @param _easySwapperV2 EasySwapperV2 contract
  constructor(
    address _admin,
    ISignatureTransfer _permit2,
    IPoolFactory _poolFactory,
    IEasySwapperV2 _easySwapperV2
  ) AuthorizedKeepers(_admin) {
    if (address(_permit2) == address(0)) revert ZeroAddress("permit2");
    if (address(_poolFactory) == address(0)) revert ZeroAddress("poolFactory");
    if (address(_easySwapperV2) == address(0)) revert ZeroAddress("easySwapperV2");

    permit2 = _permit2;
    poolFactory = _poolFactory;
    easySwapperV2 = _easySwapperV2;
  }

  // ============ Keeper Functions ============

  /// @notice Execute multiple limit buy orders in a single transaction
  /// @dev Reverts if any order fails
  /// @param _executions Array of limit buy executions
  function fillLimitBuyBatch(LimitBuyExecution[] calldata _executions) external onlyAuthorizedKeeper {
    for (uint256 i; i < _executions.length; ++i) {
      _fillLimitBuy(_executions[i].order, _executions[i].permit, _executions[i].signature, _executions[i].zapData);
    }
  }

  /// @notice Execute multiple limit buy orders, continuing even if some fail
  /// @dev Emits LimitBuyFillFailed for failed orders instead of reverting
  /// @param _executions Array of limit buy executions
  function fillLimitBuySafeBatch(LimitBuyExecution[] calldata _executions) external onlyAuthorizedKeeper {
    for (uint256 i; i < _executions.length; ++i) {
      bytes32 orderHash = EasyLimitBuyTypeHashLib.hashLimitBuyOrder(_executions[i].order);
      try
        this._fillLimitBuyExternal(
          _executions[i].order,
          _executions[i].permit,
          _executions[i].signature,
          _executions[i].zapData
        )
      // solhint-disable-next-line no-empty-blocks
      {
        // Success - event emitted in _fillLimitBuy
      } catch (bytes memory reason) {
        emit LimitBuyFillFailed(orderHash, _executions[i].order.owner, reason);
      }
    }
  }

  /// @notice Internal function exposed for try/catch in fillLimitBuySafeBatch
  /// @dev Only callable by this contract
  function _fillLimitBuyExternal(
    EasyLimitBuyTypeHashLib.LimitBuyOrder calldata _order,
    ISignatureTransfer.PermitTransferFrom calldata _permit,
    bytes calldata _signature,
    ZapData calldata _zapData
  ) external {
    if (msg.sender != address(this)) revert UnauthorizedCaller(msg.sender);
    _fillLimitBuy(_order, _permit, _signature, _zapData);
  }

  // ============ Internal Functions ============

  function _fillLimitBuy(
    EasyLimitBuyTypeHashLib.LimitBuyOrder calldata _order,
    ISignatureTransfer.PermitTransferFrom calldata _permit,
    bytes calldata _signature,
    ZapData calldata _zapData
  ) internal {
    // Validate target vault
    if (!poolFactory.isPool(_order.targetVault)) revert InvalidPool(_order.targetVault);

    // Validate slippage
    if (_order.slippageToleranceBps == 0 || _order.slippageToleranceBps > MAX_SLIPPAGE_BPS) {
      revert InvalidSlippage(_order.slippageToleranceBps);
    }

    // Validate price condition
    _validatePriceCondition(_order);

    // Determine if zap is needed
    bool useZap = _zapData.aggregatorData.swapData.length > 0;

    // Validate deposit asset configuration
    _validateDepositAssetConfig(
      _order.targetVault,
      _permit.permitted.token,
      address(_zapData.destData.destToken),
      useZap
    );

    FillExecution memory exec;
    exec.orderHash = EasyLimitBuyTypeHashLib.hashLimitBuyOrder(_order);

    // Calculate expected vault tokens from ORIGINAL input (before any swap)
    // This single slippage check covers both swap and deposit
    uint256 expectedVaultTokens = easySwapperV2.depositQuote(
      _order.targetVault,
      _permit.permitted.token,
      _permit.permitted.amount
    );
    exec.minVaultTokens =
      (expectedVaultTokens * (SLIPPAGE_DENOMINATOR - _order.slippageToleranceBps)) /
      SLIPPAGE_DENOMINATOR;

    // Transfer tokens from user via Permit2
    _transferFromUser(_permit, _order.owner, exec.orderHash, _signature);

    // Execute swap if needed, or use input directly
    if (useZap) {
      (exec.depositToken, exec.depositAmount) = _executeSwap(
        _permit.permitted.token,
        _permit.permitted.amount,
        _zapData
      );
    } else {
      exec.depositToken = _permit.permitted.token;
      exec.depositAmount = _permit.permitted.amount;
    }

    // Execute deposit
    exec.vaultTokensReceived = _executeDeposit(_order.targetVault, exec.depositToken, exec.depositAmount, _order.owner);

    // Verify slippage tolerance (covers both swap and deposit)
    if (exec.vaultTokensReceived < exec.minVaultTokens) {
      revert InsufficientVaultTokensReceived(exec.minVaultTokens, exec.vaultTokensReceived);
    }

    // Emit event
    emit LimitBuyFilled({
      orderHash: exec.orderHash,
      user: _order.owner,
      targetVault: _order.targetVault,
      inputToken: _permit.permitted.token,
      inputAmount: _permit.permitted.amount,
      vaultTokensReceived: exec.vaultTokensReceived
    });
  }

  /// @notice Validate price condition is met
  function _validatePriceCondition(EasyLimitBuyTypeHashLib.LimitBuyOrder calldata _order) internal view {
    // Validate price range is valid (min <= max)
    if (_order.minTriggerPriceD18 > _order.maxTriggerPriceD18) {
      revert InvalidPriceRange(_order.minTriggerPriceD18, _order.maxTriggerPriceD18);
    }

    uint256 currentPrice = poolFactory.getAssetPrice(_order.pricingAsset);

    // Price must be within [minTriggerPrice, maxTriggerPrice] range
    if (currentPrice < _order.minTriggerPriceD18 || currentPrice > _order.maxTriggerPriceD18) {
      revert PriceConditionNotMet(currentPrice, _order.minTriggerPriceD18, _order.maxTriggerPriceD18);
    }
  }

  /// @notice Validate deposit asset configuration
  /// @dev If no zap: input token MUST be deposit asset
  /// @dev If zap: input token must NOT be deposit asset, dest token MUST be deposit asset
  function _validateDepositAssetConfig(
    address _targetVault,
    address _inputToken,
    address _zapDestToken,
    bool _useZap
  ) internal view {
    address poolManagerLogic = IPoolLogic(_targetVault).poolManagerLogic();
    bool inputIsDepositAsset = IPoolManagerLogic(poolManagerLogic).isDepositAsset(_inputToken);

    if (_useZap) {
      // Zap: input should NOT be deposit asset, dest SHOULD be
      bool destIsDepositAsset = IPoolManagerLogic(poolManagerLogic).isDepositAsset(_zapDestToken);
      if (inputIsDepositAsset || !destIsDepositAsset) {
        revert InvalidDepositAssetConfig(_useZap, _inputToken, _zapDestToken, inputIsDepositAsset);
      }
    } else {
      // Direct: input MUST be deposit asset
      if (!inputIsDepositAsset) {
        revert InvalidDepositAssetConfig(_useZap, _inputToken, _zapDestToken, inputIsDepositAsset);
      }
    }
  }

  /// @notice Transfer tokens from user via Permit2
  function _transferFromUser(
    ISignatureTransfer.PermitTransferFrom calldata _permit,
    address _owner,
    bytes32 _witness,
    bytes calldata _signature
  ) internal {
    permit2.permitWitnessTransferFrom(
      _permit,
      ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: _permit.permitted.amount}),
      _owner,
      _witness,
      EasyLimitBuyTypeHashLib.WITNESS_TYPE_STRING,
      _signature
    );
  }

  /// @notice Execute swap via swapper
  function _executeSwap(
    address _srcToken,
    uint256 _srcAmount,
    ZapData calldata _zapData
  ) internal returns (address destToken_, uint256 destAmount_) {
    destToken_ = address(_zapData.destData.destToken);
    uint256 destBalanceBefore = IERC20(destToken_).balanceOf(address(this));

    ISwapper swapper_ = easySwapperV2.swapper();

    // Approve swapper
    IERC20OZ(_srcToken).safeIncreaseAllowance(address(swapper_), _srcAmount);

    // Build swap struct using permit-derived token/amount
    ISwapper.InOutData memory swapProps;
    ISwapper.SrcData[] memory srcData = new ISwapper.SrcData[](1);
    ISwapper.SrcTokenSwapDetails[] memory srcTokenSwapDetails = new ISwapper.SrcTokenSwapDetails[](1);

    srcTokenSwapDetails[0].token = IERC20(_srcToken);
    srcTokenSwapDetails[0].amount = _srcAmount;
    srcTokenSwapDetails[0].aggregatorData = _zapData.aggregatorData;

    srcData[0].srcTokenSwapDetails = srcTokenSwapDetails;
    srcData[0].transferMethodData.method = ISwapper.TransferMethod.ALLOWANCE;

    swapProps.srcData = srcData;
    swapProps.destData = _zapData.destData;

    swapper_.swap(swapProps);

    destAmount_ = IERC20(destToken_).balanceOf(address(this)) - destBalanceBefore;
  }

  /// @notice Execute deposit to vault
  function _executeDeposit(
    address _targetVault,
    address _depositToken,
    uint256 _depositAmount,
    address _recipient
  ) internal returns (uint256 vaultTokensReceived_) {
    // Approve vault to spend deposit token
    IERC20OZ(_depositToken).safeIncreaseAllowance(_targetVault, _depositAmount);

    // Determine cooldown: use custom if vault is whitelisted, otherwise default
    uint256 cooldown = easySwapperV2.customCooldownDepositsWhitelist(_targetVault)
      ? easySwapperV2.customCooldown()
      : DEFAULT_COOLDOWN;

    // Execute deposit - vault tokens go to recipient
    vaultTokensReceived_ = IPoolLogic(_targetVault).depositForWithCustomCooldown(
      _recipient,
      _depositToken,
      _depositAmount,
      cooldown,
      address(0)
    );
  }
}
