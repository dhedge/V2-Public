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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../../utils/tracker/DhedgeNftTrackerStorage.sol";
import "../../utils/TxDataUtils.sol";
import "../../interfaces/ITransactionTypes.sol";
import "../../interfaces/IPoolManagerLogic.sol";
import "../../interfaces/IHasSupportedAsset.sol";
import "../../interfaces/guards/ITxTrackingGuard.sol";
import "../../interfaces/guards/IGuard.sol";
import "../../interfaces/mai/IStableQiVault.sol";

/// @title MaiVaultContractGuard
/// @dev inherited by MaiVaultAssetGuard contains txGuard and afterTxGuard logic
contract MaiVaultContractGuard is TxDataUtils, IGuard, ITxTrackingGuard, ITransactionTypes {
  using SafeMath for uint256;

  event MaiEvent(address fundAddress, address maiVault);

  bool public override isTxTrackingGuard = true;
  uint256 public constant MAX_POSITION_COUNT = 1;
  DhedgeNftTrackerStorage public immutable nftTracker;

  constructor(address _nftTracker) {
    nftTracker = DhedgeNftTrackerStorage(_nftTracker);
  }

  /// @notice We use the vaultAddress as the NFT_Type
  /// @param to // the mai vault
  /// @return nftType the byte key used to store data
  function getNftType(
    address to // the vault
  ) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(to));
  }

  /// @notice This function is called after execution transaction (used to track transactions)
  /// @dev It supports createVault/destroyVault
  /// @param _poolManagerLogic the pool manager logic
  /// @param to the mai vault
  /// @param data the transaction data
  function afterTxGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  ) public virtual override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");
    bytes4 method = getMethod(data);
    if (method == IStableQiVault(to).createVault.selector) {
      uint256 id = IStableQiVault(to).vaultCount().sub(1);
      nftTracker.addUintId(to, getNftType(to), poolLogic, id, MAX_POSITION_COUNT);
    } else if (method == IStableQiVault(to).destroyVault.selector) {
      uint256 tokenId = abi.decode(getParams(data), (uint256));
      nftTracker.removeUintId(to, getNftType(to), poolLogic, tokenId);
    }
  }

  /// @notice Transaction guard for a Synthetix Mai Market
  /// @dev It supports functions that allow creating a vault and taking out a loan (no transferring)
  /// @param _poolManagerLogic the pool manager logic
  /// @param to the mai vault
  /// @param data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address to,
    bytes calldata data
  )
    external
    virtual
    override
    returns (
      uint16 txType,
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    // The pool the manager is operating against
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    require(poolManagerLogicAssets.isSupportedAsset(to), "unsupported asset");

    require(poolManagerLogicAssets.isSupportedAsset(IStableQiVault(to).collateral()), "collateral not enabled");
    require(poolManagerLogicAssets.isSupportedAsset(IStableQiVault(to).mai()), "mai not enabled");

    if (
      method == IStableQiVault(to).createVault.selector ||
      method == IStableQiVault(to).destroyVault.selector ||
      method == IStableQiVault(to).depositCollateral.selector ||
      method == IStableQiVault(to).borrowToken.selector ||
      method == IStableQiVault(to).payBackToken.selector ||
      method == IStableQiVault(to).paybackTokenAll.selector ||
      method == IStableQiVault(to).withdrawCollateral.selector
    ) {
      emit MaiEvent(poolLogic, to);
      txType = txType = uint16(TransactionType.MaiTx);
    }

    return (txType, false);
  }

  /// @notice We use the vaultAddress as the NFT_Type
  /// @param pool // the dhedge pool
  /// @param maiVault // the mai vault
  /// @return nftIds the ids in storage for this vault
  function getNftIds(address pool, address maiVault) public view returns (uint256[] memory) {
    return nftTracker.getAllUintIds(getNftType(maiVault), pool);
  }
}
