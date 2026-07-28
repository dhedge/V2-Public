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
// Copyright (c) 2025 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IPoolManagerLogic} from "../interfaces/IPoolManagerLogic.sol";
import {IHasDaoInfo} from "../interfaces/IHasDaoInfo.sol";
import {IHasGuardInfo} from "../interfaces/IHasGuardInfo.sol";
import {IHasPausable} from "../interfaces/IHasPausable.sol";
import {IHasSupportedAsset} from "../interfaces/IHasSupportedAsset.sol";
import {IGovernance} from "../interfaces/IGovernance.sol";
import {IGuard} from "../interfaces/guards/IGuard.sol";
import {IHasOwnable} from "../interfaces/IHasOwnable.sol";
import {IManaged} from "../interfaces/IManaged.sol";
import {IPoolFactory} from "../interfaces/IPoolFactory.sol";
import {IValueManipulationCheck} from "../interfaces/IValueManipulationCheck.sol";
import {ITxTrackingGuard} from "../interfaces/guards/ITxTrackingGuard.sol";
import {IDytmOfficeContractGuard} from "../interfaces/dytm/IDytmOfficeContractGuard.sol";
import {IDytmOffice} from "../interfaces/dytm/IDytmOffice.sol";
import {IAaveLendingPoolAssetGuard} from "../interfaces/guards/IAaveLendingPoolAssetGuard.sol";
import {AddressHelper} from "./AddressHelper.sol";

library PoolLogicLib {
  using SafeMath for uint256;
  using AddressHelper for address;

  struct LiquidityMintTo {
    uint256 recipient;
    uint256 manager;
    uint256 dao;
    uint256 referrer; // portion of manager's entry fee share going to referrer
  }

  struct PoolTokensAllocation {
    uint256 toBurn;
    uint256 toTransferManager;
    uint256 toTransferDao;
    uint256 toGetPortionFrom;
  }

  event TransactionExecuted(address pool, address manager, uint16 transactionType, uint256 time);

  /// @notice Compute how deposited value is split into liquidity tokens for recipient, manager, DAO, and optionally referrer
  /// @dev When a valid referrer address is provided and referral is enabled for the pool,
  ///      a portion of the manager's entry fee share is redirected to the referrer.
  ///      DAO share is never affected. Pass address(0) for no referral.
  function computeLiquidityMintTo(
    uint256 _totalSupply,
    uint256 _depositValue,
    uint256 _totalValue,
    address _poolManagerLogic,
    address _poolFactory,
    address _referrer
  ) external view returns (LiquidityMintTo memory liquidityMintTo) {
    liquidityMintTo = _buildLiquidityMintTo(
      _totalSupply,
      _depositValue,
      _totalValue,
      _poolManagerLogic,
      _poolFactory,
      _referrer
    );

    // Check supply cap only during deposit mintings to avoid withdrawals being halted during PoolLogic::_mintManagerFee()
    _validateMinting(
      _totalSupply,
      liquidityMintTo.recipient.add(liquidityMintTo.manager).add(liquidityMintTo.dao).add(liquidityMintTo.referrer),
      _poolManagerLogic
    );
  }

  function computePoolTokensAllocation(
    uint256 _redeemAmount,
    address _poolManagerLogic,
    address _poolFactory
  ) external view returns (PoolTokensAllocation memory tokens) {
    tokens.toBurn = _redeemAmount;
    tokens.toGetPortionFrom = _redeemAmount;

    (uint256 exitFeeNumerator, uint256 poolFeeShareNumerator, uint256 feeDenominator) = IPoolManagerLogic(
      _poolManagerLogic
    ).getExitFeeInfo();

    // Exit fee is 0, hence burn full amount and process withdrawal according to the portion of this amount.
    if (exitFeeNumerator == 0) {
      return tokens;
    }

    uint256 exitFee = tokens.toBurn.mul(exitFeeNumerator).div(feeDenominator);

    tokens.toGetPortionFrom = tokens.toGetPortionFrom.sub(exitFee);

    uint256 exitFeeToTransfer = exitFee.mul(feeDenominator.sub(poolFeeShareNumerator)).div(feeDenominator);

    // Nothing to transfer to manager or DAO, 100% of exit fee is going to the pool. all tokens are burned, user's portion is reduced on size of the fee.
    if (exitFeeToTransfer == 0) {
      return tokens;
    }

    // Only tokens not intended for transfer are burned, user's portion still reduced on size of the fee.
    tokens.toBurn = tokens.toBurn.sub(exitFeeToTransfer);

    (uint256 daoFeeNumerator, uint256 daoFeeDenominator) = IHasDaoInfo(_poolFactory).getDaoFee();

    tokens.toTransferDao = exitFeeToTransfer.mul(daoFeeNumerator).div(daoFeeDenominator);
    tokens.toTransferManager = exitFeeToTransfer.sub(tokens.toTransferDao);

    require(tokens.toBurn > tokens.toTransferManager && tokens.toTransferManager > tokens.toTransferDao, "dh13");

    return tokens;
  }

  function _buildLiquidityMintTo(
    uint256 _totalSupply,
    uint256 _depositValue,
    uint256 _totalValue,
    address _poolManagerLogic,
    address _poolFactory,
    address _referrer
  ) internal view returns (LiquidityMintTo memory liquidityMintTo) {
    liquidityMintTo.recipient = _totalSupply > 0 ? _depositValue.mul(_totalSupply).div(_totalValue) : _depositValue;

    (uint256 entryFeeNumerator, uint256 poolFeeShareNumerator, uint256 feeDenominator) = IPoolManagerLogic(
      _poolManagerLogic
    ).getEntryFeeInfo();

    if (entryFeeNumerator == 0) {
      return liquidityMintTo;
    }

    uint256 entryFee = liquidityMintTo.recipient.mul(entryFeeNumerator).div(feeDenominator);

    liquidityMintTo.recipient = liquidityMintTo.recipient.sub(entryFee);

    uint256 entryFeeToMint = entryFee.mul(feeDenominator.sub(poolFeeShareNumerator)).div(feeDenominator);

    if (entryFeeToMint == 0) {
      return liquidityMintTo;
    }

    (uint256 daoFeeNumerator, uint256 daoFeeDenominator) = IHasDaoInfo(_poolFactory).getDaoFee();

    liquidityMintTo.dao = entryFeeToMint.mul(daoFeeNumerator).div(daoFeeDenominator);
    liquidityMintTo.manager = entryFeeToMint.sub(liquidityMintTo.dao);

    // Referral split: taken from manager's portion only, DAO share is never affected
    if (_referrer != address(0) && liquidityMintTo.manager > 0) {
      uint256 referrerShareNumerator = IPoolManagerLogic(_poolManagerLogic).getReferralShare();

      if (referrerShareNumerator > 0) {
        liquidityMintTo.referrer = liquidityMintTo.manager.mul(referrerShareNumerator).div(feeDenominator);
        liquidityMintTo.manager = liquidityMintTo.manager.sub(liquidityMintTo.referrer);
      }
    }

    require(
      liquidityMintTo.recipient > liquidityMintTo.manager.add(liquidityMintTo.referrer) &&
        liquidityMintTo.manager.add(liquidityMintTo.referrer) > liquidityMintTo.dao,
      "dh13"
    );

    return liquidityMintTo;
  }

  function _validateMinting(uint256 _totalSupply, uint256 _mintAmount, address _poolManagerLogic) internal view {
    uint256 supplyCap = IPoolManagerLogic(_poolManagerLogic).maxSupplyCap();
    if (supplyCap > 0) {
      require(_totalSupply.add(_mintAmount) <= supplyCap, "dh32");
    }
  }

  /// @notice Calculate lockup cooldown applied to the investor after pool deposit
  /// @param _currentBalance Investor's current pool tokens balance
  /// @param _liquidityMinted Liquidity to be minted to investor after pool deposit
  /// @param _newCooldown New cooldown lockup time
  /// @param _lastCooldown Last cooldown lockup time applied to investor
  /// @param _lastDepositTime Timestamp when last pool deposit happened
  /// @param _blockTimestamp Timestamp of a block
  /// @return cooldown New lockup cooldown to be applied to investor address
  function calculateCooldown(
    uint256 _currentBalance,
    uint256 _liquidityMinted,
    uint256 _newCooldown,
    uint256 _lastCooldown,
    uint256 _lastDepositTime,
    uint256 _blockTimestamp
  ) external pure returns (uint256 cooldown) {
    // Get timestamp when current cooldown ends
    uint256 cooldownEndsAt = _lastDepositTime.add(_lastCooldown);
    // Current exit remaining cooldown
    uint256 remainingCooldown = cooldownEndsAt < _blockTimestamp ? 0 : cooldownEndsAt.sub(_blockTimestamp);
    // If it's first deposit with zero liquidity, no cooldown should be applied
    if (_currentBalance == 0 && _liquidityMinted == 0) {
      cooldown = 0;
      // If it's first deposit, new cooldown should be applied
    } else if (_currentBalance == 0) {
      cooldown = _newCooldown;
      // If zero liquidity or new cooldown reduces remaining cooldown, apply remaining
    } else if (_liquidityMinted == 0 || _newCooldown < remainingCooldown) {
      cooldown = remainingCooldown;
      // For the rest cases calculate cooldown based on current balance and liquidity minted
    } else {
      // If the user already owns liquidity, the additional lockup should be in proportion to their existing liquidity.
      // Calculated as _newCooldown * _liquidityMinted / _currentBalance
      // Aggregate additional and remaining cooldowns
      uint256 aggregatedCooldown = _newCooldown.mul(_liquidityMinted).div(_currentBalance).add(remainingCooldown);
      // Resulting value is capped at new cooldown time (shouldn't be bigger) and falls back to one second in case of zero
      cooldown = aggregatedCooldown > _newCooldown
        ? _newCooldown
        : aggregatedCooldown != 0
          ? aggregatedCooldown
          : 1;
    }
  }

  /// @notice Execute a guarded transaction on behalf of the pool
  /// @dev Resolves the appropriate guard, validates authorization, executes the transaction,
  ///      and handles post-transaction tracking. Called via DELEGATECALL from PoolLogic.
  /// @param _to The destination address for pool to talk to
  /// @param _data The data that going to send in the transaction
  /// @param _isDelegationCallback Whether this transaction is being executed via a delegation callback
  /// @param _factory The pool factory address
  /// @param _poolManagerLogic The pool manager logic address
  /// @return success A boolean for success or fail transaction
  function execTransaction(
    address _to,
    bytes memory _data,
    bool _isDelegationCallback,
    address _factory,
    address _poolManagerLogic
  ) external returns (bool success) {
    require(!IHasPausable(_factory).tradingPausedPools(address(this)), "dh20");

    {
      address checker = IPoolFactory(_factory).valueManipulationCheck();
      if (checker != address(0)) {
        IValueManipulationCheck(checker).checkOperationType(
          address(this),
          IValueManipulationCheck.OperationType.ExecTransaction
        );
      }
    }

    require(_to != address(0), "dh18");

    address guard;
    uint16 txType;
    bool isPublic;

    {
      address contractGuard = IHasGuardInfo(_factory).getContractGuard(_to);

      if (contractGuard != address(0)) {
        guard = contractGuard;
        (txType, isPublic) = IGuard(contractGuard).txGuard(_poolManagerLogic, _to, _data);
      }
    }

    // invalid contract guard call, try asset guard
    if (txType == 0) {
      // no contract guard configured, get asset guard
      address assetGuard = IHasGuardInfo(_factory).getAssetGuard(_to);

      if (assetGuard == address(0)) {
        // If there is no contractGuard and no assetGuard then use the ERC20Guard for the transaction,
        // which will only allow a valid approve transaction
        address governanceAddress = IPoolFactory(_factory).governanceAddress();
        assetGuard = IGovernance(governanceAddress).assetGuards(0); // get ERC20Guard (assetType 0)
      } else {
        // if asset is configured, ensure that it's enabled in the pool
        require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_to), "dh22");
      }
      guard = assetGuard;
      (txType, isPublic) = IGuard(assetGuard).txGuard(_poolManagerLogic, _to, _data);
    }

    require(txType > 0, "dh23");

    {
      address manager = IManaged(_poolManagerLogic).manager();

      require(
        isPublic ||
          _isDelegationCallback ||
          msg.sender == manager ||
          msg.sender == IManaged(_poolManagerLogic).trader() ||
          msg.sender == IHasOwnable(_factory).owner(),
        "dh24"
      );

      success = _to.tryAssemblyCall(_data);

      // call afterTxGuard to track transactions
      // to make it compatible with previous version, we use low-level call before calling afterTxGuard() function
      // the low level call will return `false` if its execution reverts
      // solhint-disable-next-line avoid-low-level-calls
      (bool hasFunction, bytes memory returnData) = guard.call(abi.encodeWithSignature("isTxTrackingGuard()"));
      if (hasFunction && abi.decode(returnData, (bool))) {
        ITxTrackingGuard(guard).afterTxGuard(_poolManagerLogic, _to, _data);
      }

      emit TransactionExecuted(address(this), manager, txType, block.timestamp);
      IPoolFactory(_factory).emitPoolEvent();
    }
  }

  /// @notice Validate delegation callback caller is a legitimate DYTM office
  /// @dev Ensures the caller has a registered contract guard matching the DYTM office,
  ///      and that the original caller context (the account that initiated the delegation call) is this pool.
  ///      This prevents unauthorized contracts from triggering delegation callbacks on behalf of the pool.
  /// @param _factory The pool factory address for guard lookup
  /// @param _caller The msg.sender of the delegation callback (expected to be DYTM office)
  /// @param _self The address of the pool (this) to verify caller context
  function validateDelegationCallback(address _factory, address _caller, address _self) external view {
    address dytmOfficeContractGuard = IHasGuardInfo(_factory).getContractGuard(_caller);
    require(
      dytmOfficeContractGuard != address(0) &&
        _caller == IDytmOfficeContractGuard(dytmOfficeContractGuard).dytmOffice(),
      "dh35"
    );
    address originalCaller = IDytmOffice(_caller).callerContext();
    require(originalCaller == _self, "dh34");
  }

  /// @notice Validate flash loan callback caller is a legitimate Aave lending pool
  /// @dev Ensures the initiator is this pool and the caller has a registered asset guard
  ///      matching the Aave lending pool. Returns the guard for subsequent flashloanProcessing call.
  /// @param _factory The pool factory address for guard lookup
  /// @param _initiator The address that initiated the flash loan (must be this pool)
  /// @param _caller The msg.sender of the flash loan callback (expected to be Aave lending pool)
  /// @param _self The address of the pool (this)
  /// @return aaveLendingPoolAssetGuard The validated asset guard address
  function validateFlashLoanCallback(
    address _factory,
    address _initiator,
    address _caller,
    address _self
  ) external view returns (address aaveLendingPoolAssetGuard) {
    require(_initiator == _self, "dh29");
    aaveLendingPoolAssetGuard = IHasGuardInfo(_factory).getAssetGuard(_caller);
    require(
      aaveLendingPoolAssetGuard != address(0) &&
        _caller == IAaveLendingPoolAssetGuard(aaveLendingPoolAssetGuard).aaveLendingPool(),
      "dh30"
    );
  }
}
