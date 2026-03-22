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

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IGPv2Settlement} from "../../../interfaces/cowSwap/IGPv2Settlement.sol";
import {IPoolFactory} from "../../../interfaces/IPoolFactory.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IDataValidator} from "../../../interfaces/IDataValidator.sol";
import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

/// @notice Transaction guard for CoWSwap (GPv2) Settlement contract interactions
/// @dev This guard validates PreSign operations for CoWSwap orders placed by dHEDGE pools.
///
///      CoWSwap PreSign Flow:
///      1. Manager creates order off-chain and submits to CoWSwap orderbook
///      2. Manager calls TypedStructuredDataValidator.submit() with full order data
///         - Validator validates order (receiver, tokens, rate check, etc.)
///         - Validator computes EIP-712 digest and stores in validatedHashes[pool][digest]
///      3. Manager calls pool.execTransaction() → GPv2Settlement.setPreSignature(orderUid, true)
///         - This guard extracts orderDigest from orderUid (first 32 bytes)
///         - This guard verifies owner in orderUid matches the pool
///         - This guard checks validatedHashes[pool][orderDigest] exists
///         - If all checks pass, the transaction is allowed
///      4. CoWSwap solver executes the order when conditions are met
///
///      Security:
///      - Only pre-validated orders can be pre-signed (prevents malicious orders)
///      - Owner in orderUid must match the pool address (prevents signing for other addresses)
///      - Order contents were already validated in step 2 (receiver, tokens, rate, expiry)
contract GPv2SettlementContractGuard is IGuard, TxDataUtils, ITransactionTypes {
  /// @dev Length of CoWSwap orderUid in bytes = orderDigest (32) + owner (20) + validTo (4) = 56 bytes
  uint256 private constant ORDER_UID_LENGTH = 56;

  /// @notice The dHEDGE PoolFactory contract
  IPoolFactory public immutable poolFactory;

  /// @param _poolFactory The dHEDGE PoolFactory contract address
  constructor(address _poolFactory) {
    require(_poolFactory != address(0), "GPv2Guard: invalid poolFactory");

    poolFactory = IPoolFactory(_poolFactory);
  }

  /// @notice Transaction guard for GPv2Settlement contract
  /// @param _poolManagerLogic The pool manager logic address
  /// @param _data Transaction call data attempt by manager
  /// @return txType Transaction type
  /// @return isPublic Whether the transaction is public (always false)
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes calldata _data
  ) external view override returns (uint16 txType, bool isPublic) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    bytes4 method = getMethod(_data);

    if (method == IGPv2Settlement.setPreSignature.selector) {
      (bytes memory orderUid, bool signed) = abi.decode(getParams(_data), (bytes, bool));

      // Only validate when signing (not when revoking)
      // The CoWSwap UI does NOT use setPreSignature(orderUid, false) for cancellation, they use invalidateOrder
      // invalidateOrder is a permanent, irreversible cancellation, while setPreSignature(false) only revokes the pre-sign authorization.
      if (signed) {
        require(orderUid.length == ORDER_UID_LENGTH, "GPv2Guard: invalid Uid length");

        // Extract orderDigest and owner from orderUid
        // orderUid = abi.encodePacked(orderDigest, owner, validTo)
        //          = [0..31: orderDigest][32..51: owner][52..55: validTo]
        bytes32 orderDigest;
        address owner;
        uint32 validTo;
        // solhint-disable-next-line no-inline-assembly
        assembly {
          // orderUid is a bytes memory, so first 32 bytes are length
          // orderDigest is at offset 32 (skip length)
          orderDigest := mload(add(orderUid, 32))
          // owner is at offset 64 (32 length + 32 orderDigest), but we need to shift right by 96 bits
          // to extract the 20-byte address from the 32-byte word
          owner := shr(96, mload(add(orderUid, 64)))
          // validTo is at offset 84 (32 length + 32 orderDigest + 20 owner), shift right by 224 bits
          // to extract the 4-byte uint32 from the 32-byte word
          validTo := shr(224, mload(add(orderUid, 84)))
        }

        // Order must not be expired
        require(validTo > block.timestamp, "GPv2Guard: order expired");

        // Owner in the orderUid must be the pool
        require(owner == poolLogic, "GPv2Guard: owner must be pool");

        // Check that this orderDigest was validated via TypedStructuredDataValidator
        address dataValidator = poolFactory.dataValidator();

        require(dataValidator != address(0), "GPv2Guard: dataValidator not set");
        require(
          IDataValidator(dataValidator).isValidatedHash(poolLogic, orderDigest),
          "GPv2Guard: order not validated"
        );

        txType = uint16(TransactionType.CowSwapPreSign);
      }
    } else if (method == IGPv2Settlement.invalidateOrder.selector) {
      bytes memory orderUid = abi.decode(getParams(_data), (bytes));

      require(orderUid.length == ORDER_UID_LENGTH, "GPv2Guard: invalid Uid length");

      // Extract owner from orderUid
      address owner;
      // solhint-disable-next-line no-inline-assembly
      assembly {
        owner := shr(96, mload(add(orderUid, 64)))
      }

      // Owner in the orderUid must be the pool
      require(owner == poolLogic, "GPv2Guard: owner must be pool");

      txType = uint16(TransactionType.CowSwapInvalidateOrder);
    }

    return (txType, false);
  }
}
