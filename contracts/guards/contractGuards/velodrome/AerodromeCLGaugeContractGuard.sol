// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {IVelodromeCLGauge} from "../../../interfaces/velodrome/IVelodromeCLGauge.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IERC721VerifyingGuard} from "../../../interfaces/guards/IERC721VerifyingGuard.sol";
import {VelodromeNonfungiblePositionGuard} from "./VelodromeNonfungiblePositionGuard.sol";

/// @title Transaction guard for Aerodrome CL Gauge contract
/// @dev The Aerodrome Gauge contract is essentially identical to the Velodrome Gauge contract,
/// @dev except it excludes the `increaseStakedLiquidity` and `decreaseStakedLiquidity` functions.
contract AerodromeCLGaugeContractGuard is TxDataUtils, IGuard, ITransactionTypes, IERC721VerifyingGuard {
  /// @notice Transaction guard for Aerodrome CL Gauge
  /// @dev It supports depositing, withdrawing, and claiming rewards
  /// @param poolManagerLogic the pool manager logic
  /// @param to the gauge address
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogic,
    address to,
    bytes calldata data
  ) public virtual override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");
    IVelodromeCLGauge velodromeCLGauge = IVelodromeCLGauge(to);
    address nonfungiblePositionManager = velodromeCLGauge.nft();
    address nonfungiblePositionManagerGuard = IHasGuardInfo(IPoolLogic(poolLogic).factory()).getContractGuard(
      nonfungiblePositionManager
    );

    bytes4 method = getMethod(data);
    bytes memory params = getParams(data);

    if (method == IVelodromeCLGauge.deposit.selector) {
      uint256 tokenId = abi.decode(params, (uint256));
      _validateTokenId(nonfungiblePositionManagerGuard, tokenId, poolLogic);

      txType = uint16(TransactionType.VelodromeCLStake);
    } else if (method == IVelodromeCLGauge.withdraw.selector) {
      uint256 tokenId = abi.decode(params, (uint256));
      _validateTokenId(nonfungiblePositionManagerGuard, tokenId, poolLogic);

      txType = uint16(TransactionType.VelodromeCLUnstake);
    } else if (method == bytes4(keccak256("getReward(uint256)"))) {
      // it's possible to claim any reward token and sell it, we don't check if the reward token is supported
      uint256 tokenId = abi.decode(params, (uint256));
      _validateTokenId(nonfungiblePositionManagerGuard, tokenId, poolLogic);

      txType = uint16(TransactionType.Claim);
    }

    return (txType, false);
  }

  // Function to validate a token ID if it's from the NFT tracker
  function _validateTokenId(address nonfungiblePositionManagerGuard, uint256 tokenId, address poolLogic) internal view {
    // find token ids from nft tracker
    bool isValid = VelodromeNonfungiblePositionGuard(nonfungiblePositionManagerGuard).isValidOwnedTokenId(
      poolLogic,
      tokenId
    );
    require(isValid, "position is not tracked");
  }

  /// @notice Verifies an ERC721 token transaction
  /// @dev Called by the PoolLogic contract upon the onERC721Received function call
  /// @dev Allow receiving NFT positions from the Aerodrome CL Gauge
  function verifyERC721(
    address /* operator */,
    address /* from */,
    uint256 /* tokenId */,
    bytes calldata
  ) external pure override returns (bool verified) {
    verified = true;
  }
}
