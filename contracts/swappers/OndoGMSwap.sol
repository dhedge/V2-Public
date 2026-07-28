// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/v5/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/v5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/v5/contracts/token/ERC20/IERC20.sol";

import {AuthorizedCallersBase} from "../utils/callers/AuthorizedCallersBase.sol";
import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IGMTokenManager} from "../interfaces/ondo/IGMTokenManager.sol";
import {IOndoGMSwap} from "../interfaces/ondo/IOndoGMSwap.sol";

/// @title OndoGMSwap
/// @notice Central contract for dHedge vaults to perform atomic mint/redeem swaps via Ondo's GMTokenManager.
/// @dev This contract is whitelisted by Ondo and intermediates token transfers between vaults and GMTokenManager.
/// @dev Caller must be a dHEDGE pool (automatically authorised via `poolFactory.isPool`) or a non-pool address
///      explicitly added by the owner via `setAuthorizedCaller`. `DytmWithdrawProcessor` is the only such
///      address today — it both mints GM (to repay a bear-Ondo debt) and redeems GM (to settle a
///      long-Ondo position). Defense-in-depth on the BUY-side mint surface lives elsewhere:
///      `swapExactInWithAttestation` hard-codes the output recipient to `msg.sender`, the
///      processor's `_checkAction` blocks direct token transfers + zeroes every approval at end
///      of unwind, and Ondo's attestation pipeline rate-limits how many BUYs a given `userId`
///      can sign per period.
contract OndoGMSwap is IOndoGMSwap, AuthorizedCallersBase, OwnableUpgradeable, ICommonErrors {
  using SafeERC20 for IERC20;

  // Scaling factor for implied cost: 18 (quantity) + 18 (price) - 6 (USDC decimals) = 30
  uint256 private constant IMPLIED_COST_SCALING = 1e30;
  // Tolerance for excess USDC: 1 USDC (6 decimals)
  uint256 private constant USDC_TOLERANCE = 1e6;

  error InvalidQuoteSide(uint8 side);
  error InsufficientOutput(uint256 actual, uint256 minimum);
  error ExcessiveAmountIn(uint256 amountIn, uint256 impliedCost);
  error AssetMismatch();
  error AmountMismatch();
  error InvalidAdditionalData();
  error InvalidSettlementToken();

  IPoolFactory public poolFactory;
  IGMTokenManager public gmTokenManager;
  address public usdc;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _owner,
    address _poolFactory,
    address _gmTokenManager,
    address _usdc
  ) external initializer {
    if (_poolFactory == address(0)) revert ZeroAddress("_poolFactory");
    if (_gmTokenManager == address(0)) revert ZeroAddress("_gmTokenManager");
    if (_usdc == address(0)) revert ZeroAddress("_usdc");

    __Ownable_init(_owner);

    poolFactory = IPoolFactory(_poolFactory);
    gmTokenManager = IGMTokenManager(_gmTokenManager);
    usdc = _usdc;

    // Max approve USDC to GMTokenManager since it's the only deposit/redeem token
    IERC20(_usdc).approve(_gmTokenManager, type(uint256).max);
  }

  /// @notice Perform an atomic mint or redeem swap via Ondo's GMTokenManager.
  /// @param tokenIn The input token (USDC for buy, Ondo asset for sell).
  /// @param amountIn The amount of tokenIn to swap.
  /// @param tokenOut The output token (Ondo asset for buy, USDC for sell).
  /// @param amountOutMinimum The minimum amount of tokenOut to receive.
  /// @param attestationSignature The attestation signature from Ondo.
  /// @param quote The Ondo attestation quote.
  function swapExactInWithAttestation(
    address tokenIn,
    uint256 amountIn,
    address tokenOut,
    uint256 amountOutMinimum,
    bytes calldata attestationSignature,
    IGMTokenManager.Quote calldata quote
  ) external onlyAuthorizedCaller {
    // Validate quote fields
    if (quote.additionalData != bytes32(0)) revert InvalidAdditionalData();

    // Pull tokenIn from the caller
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

    // Record tokenOut balance before swap
    uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

    // Validate quote and execute mint or redeem
    if (quote.side == uint8(IGMTokenManager.QuoteSide.BUY)) {
      if (tokenIn != address(usdc)) revert InvalidSettlementToken();
      if (quote.asset != tokenOut) revert AssetMismatch();
      // Prevent excess USDC from being converted to USDon and stuck in this contract.
      // Implied cost is quote.quantity * quote.price scaled to USDC decimals (18+18-6=30).
      uint256 impliedCost = (quote.quantity * quote.price) / IMPLIED_COST_SCALING;
      if (amountIn > impliedCost + USDC_TOLERANCE) revert ExcessiveAmountIn(amountIn, impliedCost);
      gmTokenManager.mintWithAttestation(quote, attestationSignature, tokenIn, amountIn);
    } else if (quote.side == uint8(IGMTokenManager.QuoteSide.SELL)) {
      if (tokenOut != address(usdc)) revert InvalidSettlementToken();
      if (quote.asset != tokenIn) revert AssetMismatch();
      if (amountIn != quote.quantity) revert AmountMismatch();
      IERC20(tokenIn).safeIncreaseAllowance(address(gmTokenManager), amountIn);
      gmTokenManager.redeemWithAttestation(quote, attestationSignature, tokenOut, amountOutMinimum);
    } else {
      revert InvalidQuoteSide(quote.side);
    }

    // Measure actual output
    uint256 actualOutput = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
    if (actualOutput < amountOutMinimum) revert InsufficientOutput(actualOutput, amountOutMinimum);

    // Transfer output to the caller
    IERC20(tokenOut).safeTransfer(msg.sender, actualOutput);
  }

  /// @notice Rescue tokens stuck in this contract.
  /// @param token The token to rescue.
  /// @param amount The amount to rescue.
  /// @param recipient The address to send rescued tokens to.
  function rescueToken(address token, uint256 amount, address recipient) external onlyOwner {
    if (recipient == address(0)) revert ZeroAddress("recipient");
    IERC20(token).safeTransfer(recipient, amount);
  }

  /// @notice Authorise (or revoke) a non-pool caller of `swapExactInWithAttestation`.
  function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
    _setAuthorizedCaller(caller, authorized);
  }

  /// @notice Whether `caller` is authorised to invoke `swapExactInWithAttestation`.
  ///         Any dHEDGE pool is automatically authorised; other callers must be added by the owner.
  function isAuthorizedCaller(address caller) public view override returns (bool) {
    return poolFactory.isPool(caller) || super.isAuthorizedCaller(caller);
  }
}
