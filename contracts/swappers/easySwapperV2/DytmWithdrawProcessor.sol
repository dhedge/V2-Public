// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {SafeERC20} from "../../utils/SafeERC20.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {AddressHelper} from "../../utils/AddressHelper.sol";
import {PoolLogicLib} from "../../utils/PoolLogicLib.sol";
import {TxDataUtils} from "../../utils/TxDataUtils.sol";

import {IDytmDelegatee} from "../../interfaces/dytm/IDytmDelegatee.sol";
import {IDytmOffice} from "../../interfaces/dytm/IDytmOffice.sol";
import {IDytmWithdrawProcessor} from "../../interfaces/dytm/IDytmWithdrawProcessor.sol";
import {DytmParamStructs} from "../../utils/dytm/DytmParamStructs.sol";

import {IEasySwapperV2} from "./interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "./interfaces/IWithdrawalVault.sol";
import {DytmWithdrawLib} from "./libraries/dytm/DytmWithdrawLib.sol";

/// @title DytmWithdrawProcessor
/// @notice Runs the user's DYTM unwind plan. A `WithdrawalVault` transfers the freshly-split DYTM
///         accounts here, the processor delegates back into DYTM, enforces the drained-account
///         post-condition, and returns the `outputAsset` gain to the vault.
/// @dev    Auth: `caller.depositor()` is cross-checked against `easySwapperV2`'s vault registry.
/// @dev    DEPLOYMENT NOTE: Re-deploying requires re-deploying `DytmOfficeAssetGuard` (stores
///         processor as immutable) and updating `OndoGMSwap.setAuthorizedCaller`.
contract DytmWithdrawProcessor is IDytmDelegatee, IDytmWithdrawProcessor, Ownable, TxDataUtils {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using AddressHelper for address;

  /// @notice EasySwapperV2 used to authorise WithdrawalVault callers of `process`.
  IEasySwapperV2 public immutable easySwapperV2;
  /// @notice dHEDGE factory used to validate the DYTM Office identity inside `onDelegationCallback`.
  address public immutable dHedgePoolFactory;
  /// @notice Canonical settlement token for every DYTM unwind on this chain. `DytmWithdrawLib`
  ///         enforces `plan.outputAsset == usdc` so every unwind exits in a DEX-liquid stable
  ///         asset and the 2% slippage cap stays denominated in USD terms.
  address public immutable override usdc;

  constructor(address _easySwapperV2, address _dHedgePoolFactory, address _usdc) {
    require(_easySwapperV2 != address(0), "invalid easySwapperV2");
    require(_dHedgePoolFactory != address(0), "invalid poolFactory");
    require(_usdc != address(0), "invalid usdc");
    easySwapperV2 = IEasySwapperV2(_easySwapperV2);
    dHedgePoolFactory = _dHedgePoolFactory;
    usdc = _usdc;
  }

  /// @inheritdoc IDytmWithdrawProcessor
  function process(UnwindPlanRequest calldata params) external override returns (uint256 received) {
    require(_isAuthorizedVault(msg.sender), "unauthorized vault");

    uint256 balanceBefore = IERC20(params.outputAsset).balanceOf(address(this));

    IDytmOffice(params.dytmOffice).delegationCall(
      DytmParamStructs.DelegationCallParams({
        delegatee: IDytmDelegatee(address(this)),
        callbackData: abi.encode(params.actions)
      })
    );

    // Post-check: every transferred split account must end the unwind either fully drained, or
    // holding only a sub-$1 GM dust remnant Ondo can't attest a swap for. Drained accounts are
    // inert and stay here; a remnant is handed back to the pool so its value isn't orphaned in
    // this shared processor (the pool's manager can later merge it into the pool's own account).
    // `DytmWithdrawLib` bounds the remnant's value so a plan can't lazily orphan real value.
    for (uint256 i; i < params.splitPositions.length; ++i) {
      uint256 tokenId = params.splitPositions[i].tokenId;
      uint88 marketId = params.splitPositions[i].marketId;
      bool drained = IDytmOffice(params.dytmOffice).getDebtId(tokenId, marketId) == 0 &&
        IDytmOffice(params.dytmOffice).getAllCollateralIds(tokenId, marketId).length == 0;
      if (!drained) {
        IDytmOffice(params.dytmOffice).transfer(params.pool, tokenId, 1);
      }
    }

    // Forward the `outputAsset` gain produced by the unwind back to the caller; the caller
    // (`WithdrawalVault`) is the authority on the slippage floor.
    received = IERC20(params.outputAsset).balanceOf(address(this)).sub(balanceBefore);
    IERC20(params.outputAsset).safeTransfer(msg.sender, received);
  }

  /// @notice An allowance the plan granted that needs to be zeroed at end of `onDelegationCallback`.
  struct PendingApproval {
    address token;
    address spender;
  }

  /// @notice DYTM Office callback. Runs the user's action sequence and zeros every allowance the
  ///         plan granted so the shared processor never carries persistent state between unwinds.
  function onDelegationCallback(bytes calldata _callbackData) external override returns (bytes memory) {
    PoolLogicLib.validateDelegationCallback(dHedgePoolFactory, msg.sender, address(this));
    DytmWithdrawLib.Action[] memory actions = abi.decode(_callbackData, (DytmWithdrawLib.Action[]));

    PendingApproval[] memory pending = new PendingApproval[](actions.length);
    uint256 pendingCount;

    for (uint256 i; i < actions.length; ++i) {
      address spender = _checkAction(actions[i]);
      if (spender != address(0)) {
        pending[pendingCount++] = PendingApproval({token: actions[i].to, spender: spender});
      }
      actions[i].to.tryAssemblyCall(actions[i].data);
    }

    // Zero every allowance the plan granted so nothing persists between unwinds.
    for (uint256 i; i < pendingCount; ++i) {
      IERC20(pending[i].token).safeApprove(pending[i].spender, 0);
    }
    return "";
  }

  /// @dev Action filter:
  ///        - Self-call: blocked.
  ///        - `transfer` / `transferFrom`: blocked.
  ///        - `approve` / `increaseAllowance`: spender returned so the caller can zero the
  ///          allowance post-unwind.
  function _checkAction(DytmWithdrawLib.Action memory action) private view returns (address spender) {
    require(action.to != address(this), "self-call blocked");
    if (action.data.length < 4) return address(0);
    bytes4 selector = getMethod(action.data);

    if (selector == IERC20.approve.selector || selector == 0x39509351 /* increaseAllowance */) {
      (spender, ) = abi.decode(getParams(action.data), (address, uint256));
    } else if (selector == IERC20.transfer.selector || selector == IERC20.transferFrom.selector) {
      revert("transfer/transferFrom blocked");
    }
  }

  /// @notice Recover dust accumulated from imperfect unwinds (rounding remainders, untracked
  ///         intermediate tokens). Drained DYTM account NFTs that pile up here are inert (no
  ///         collateral, no debt) so they don't need a dedicated rescue path.
  function rescueToken(address token, uint256 amount, address recipient) external onlyOwner {
    require(recipient != address(0), "invalid recipient");
    IERC20(token).safeTransfer(recipient, amount);
  }

  /// @dev Caller is allowed if it is a WithdrawalVault registered against its claimed depositor
  ///      in `easySwapperV2`. A malicious contract can return any `depositor()`, but the
  ///      registered-vault lookup only matches if `easySwapperV2` itself deployed `caller`.
  function _isAuthorizedVault(address caller) private view returns (bool) {
    try IWithdrawalVault(caller).depositor() returns (address vaultDepositor) {
      return
        easySwapperV2.withdrawalContracts(vaultDepositor) == caller ||
        easySwapperV2.limitOrderContracts(vaultDepositor) == caller;
    } catch {
      return false;
    }
  }
}
