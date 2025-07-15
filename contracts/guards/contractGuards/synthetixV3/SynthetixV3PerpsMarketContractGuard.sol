// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {IERC721VerifyingGuard} from "../../../interfaces/guards/IERC721VerifyingGuard.sol";
import {ISynthetixV3ContractGuard} from "../../../interfaces/synthetixV3/ISynthetixV3ContractGuard.sol";
import {IHasGuardInfo} from "../../../interfaces/IHasGuardInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPerpsAccountModule} from "../../../interfaces/synthetixV3/IPerpsAccountModule.sol";
import {IAsyncOrderModule} from "../../../interfaces/synthetixV3/IAsyncOrderModule.sol";
import {IAtomicOrderModule} from "../../../interfaces/synthetixV3/IAtomicOrderModule.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {IAccountModule} from "../../../interfaces/synthetixV3/IAccountModule.sol";
import {DhedgeNftTrackerStorage} from "../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {IERC721Enumerable} from "../../../interfaces/IERC721Enumerable.sol";

contract SynthetixV3PerpsMarketContractGuard is
  TxDataUtils,
  ITxTrackingGuard,
  ITransactionTypes,
  IERC721VerifyingGuard
{
  using SafeCast for uint256;
  using SafeCast for int256;
  using SafeMath for uint256;
  using SignedSafeMath for int128;
  using SignedSafeMath for int256;

  uint256 public constant MAX_ACCOUNT_LIMIT = 1;

  address public immutable snxV3Core;

  DhedgeNftTrackerStorage public immutable nftTracker;

  bool public override isTxTrackingGuard = true;

  // Maximum leverage which is allowed to reduce risk of liquidation
  uint256 public constant MAX_LEVERAGE = 5e18; // 18 decimals

  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _snxV3Core Synthetix V3 core address
  constructor(address _nftTracker, address _snxV3Core) {
    require(_nftTracker != address(0), "invalid nftTracker");
    require(_snxV3Core != address(0), "invalid snxV3Core");

    nftTracker = DhedgeNftTrackerStorage(_nftTracker);

    snxV3Core = _snxV3Core;
  }

  /// @notice Returns Synthetix Perps Account NFT ID associated with the pool stored in dHEDGE NFT Tracker contract
  /// @dev Assumes that in our inner tracking system the pool always holds only one Synthetix V3 Perps NFT
  /// @param _poolLogic Pool address
  /// @param _to Synthetix V3 Perps Market address
  /// @return tokenId Synthetix Perps Account NFT ID
  function getAccountNftTokenId(address _poolLogic, address _to) public view returns (uint128 tokenId) {
    uint256[] memory tokenIds = nftTracker.getAllUintIds(
      _getNftType(IAccountModule(_to).getAccountTokenAddress()),
      _poolLogic
    );

    if (tokenIds.length == 1) {
      tokenId = tokenIds[0].toUint128();
    }
  }

  /// @notice Transaction guard for a Synthetix V3 Perps Market
  /// @dev It supports the functions for managing margin and creating/modifying positions
  /// @param _poolManagerLogic the pool manager logic
  /// @param _to Synthetix V3 Perp Market address
  /// @param _data the transaction data
  /// @return txType the transaction type of a given transaction data.
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external view override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    ISynthetixV3ContractGuard coreContractGuard = ISynthetixV3ContractGuard(
      IHasGuardInfo(IPoolLogic(poolLogic).factory()).getContractGuard(snxV3Core)
    );

    require(coreContractGuard.isVaultWhitelisted(poolLogic), "dhedge vault not whitelisted");

    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);
    require(poolManagerLogicAssets.isSupportedAsset(_to), "enable synthetix v3 perps market");

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == bytes4(keccak256("createAccount()")) || method == bytes4(keccak256("createAccount(uint128)"))) {
      address snxPerpAccountNft = IAccountModule(_to).getAccountTokenAddress();
      // Revert if pool already has associated Synthetix V3 Perp NFT account
      require(nftTracker.getDataCount(_getNftType(snxPerpAccountNft), poolLogic) == 0, "only one account allowed");

      txType = uint16(TransactionType.SynthetixV3PerpsCreateAccount);
    } else if (method == IPerpsAccountModule.modifyCollateral.selector) {
      (uint128 accountId, uint128 synthMarketId, int256 amountDelta) = abi.decode(params, (uint128, uint128, int256));
      require(getAccountNftTokenId(poolLogic, _to) == accountId, "account not owned by pool");

      // allow only snxUSD as margin. possibly it can be expanded using other synths in the future.
      // https://github.com/Synthetixio/python-sdk/blob/main/src/synthetix/perps/perps.py#L874
      require(synthMarketId == 0, "unsupported synthMarketId");
      require(
        poolManagerLogicAssets.isSupportedAsset(IAtomicOrderModule(snxV3Core).getUsdToken()),
        "unsupported asset as margin"
      );

      uint256[] memory openPositionMarketIds = IPerpsAccountModule(_to).getAccountOpenPositions(accountId);
      int256 availableMargin = IPerpsAccountModule(_to).getAvailableMargin(accountId);
      if (amountDelta < 0 && openPositionMarketIds.length == 1 && -amountDelta < availableMargin) {
        // only needed leverage check for withdrawing margin
        _maxLeverageCheckModifyCollateral(
          _to,
          uint128(openPositionMarketIds[0]),
          accountId,
          amountDelta,
          availableMargin
        );
      }

      txType = uint16(TransactionType.SynthetixV3PerpsModifyCollateral);
    } else if (method == IAsyncOrderModule.commitOrder.selector) {
      (uint128 marketId, uint128 accountId, int128 sizeDelta, , , , ) = abi.decode(
        params,
        (uint128, uint128, int128, uint128, uint256, bytes32, address)
      );

      uint256[] memory openPositionMarketIds = IPerpsAccountModule(_to).getAccountOpenPositions(accountId);
      require(
        openPositionMarketIds.length == 0 ||
          (openPositionMarketIds.length == 1 && marketId == openPositionMarketIds[0]),
        "only one perp market allowed"
      );
      _maxLeverageCheck(_to, marketId, accountId, sizeDelta);

      txType = uint16(TransactionType.SynthetixV3PerpsCommitOrder);
    }
    return (txType, false);
  }

  /// @dev Required because we need to track minted Synthetix V3 NFT Account IDs
  /// @dev Can be called only by PoolLogic during execTransaction
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _to Synthetix V3 Perps Market   address
  /// @param _data Transaction data
  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) external override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    ISynthetixV3ContractGuard coreContractGuard = ISynthetixV3ContractGuard(
      IHasGuardInfo(IPoolLogic(poolLogic).factory()).getContractGuard(snxV3Core)
    );

    require(coreContractGuard.isVaultWhitelisted(poolLogic), "dhedge vault not whitelisted");

    bytes4 method = getMethod(_data);

    // Runs only after Synthetix V3 PerpsMarket contract calls related to account creation
    // Handles both createAccount() and createAccount(uint128) methods
    if (method == bytes4(keccak256("createAccount(uint128)"))) {
      // Id was passed in advance, see https://docs.synthetix.io/v/v3/for-developers/smart-contracts#createaccount
      uint128 id = abi.decode(getParams(_data), (uint128));
      _afterTxGuardHelper(id, poolLogic, _to);
    } else if (method == bytes4(keccak256("createAccount()"))) {
      address snxAccountNft = IAccountModule(_to).getAccountTokenAddress();
      // Id was assigned by Synthetix V3 System and we're getting it from the Synthetix V3 Account NFT
      uint256 balance = IERC721Enumerable(snxAccountNft).balanceOf(poolLogic);
      require(balance > 0, "no minted nft");
      // Most recent minted NFT is the last one
      uint256 id = IERC721Enumerable(snxAccountNft).tokenOfOwnerByIndex(poolLogic, balance - 1);
      _afterTxGuardHelper(id, poolLogic, _to);
    }
  }

  /// @notice Helper function to track minted Synthetix V3 NFT Account IDs
  /// @dev We are tracking minted Synthetix V3 NFT Account IDs in dHEDGE NFT Tracker contract
  /// @param _id Synthetix V3 NFT Account ID associated with the pool
  /// @param _poolLogic Pool logic address
  /// @param _to Synthetix V3 Perps Market address
  function _afterTxGuardHelper(uint256 _id, address _poolLogic, address _to) internal {
    bytes32 nftType = _getNftType(IAccountModule(_to).getAccountTokenAddress());
    // Storing Synthetix V3 NFT Account ID associated with the pool in dHEDGE NFT Tracker contract by NFT type
    // It ensures that max positions limit is not breached
    nftTracker.addUintId(_to, nftType, _poolLogic, _id, MAX_ACCOUNT_LIMIT);
  }

  /// @notice Helper function to build NFT type
  /// @dev NFT type is a keccak256 hash of Synthetix V3 Perps Account NFT address
  /// @param _accountNftToken Synthetix V3 Perps Account NFT address
  /// @return nftType NFT type
  function _getNftType(address _accountNftToken) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_accountNftToken));
  }

  function verifyERC721(
    address,
    address _from,
    uint256,
    bytes calldata
  ) external pure override returns (bool verified) {
    // Most likely it's an overkill. Checks that the NFT is minted, not transferred
    require(_from == address(0), "can't accept foreign NFTs");

    verified = true;
  }

  function _getNewPositionValue(
    address to,
    uint128 marketId,
    int128 positionSize,
    int128 sizeDelta
  ) internal view returns (uint256 newPositionValue) {
    int256 newPositionSize = positionSize.add(sizeDelta);
    (, uint256 fillPrice) = IAsyncOrderModule(to).computeOrderFees(marketId, sizeDelta);
    if (newPositionSize >= 0) {
      newPositionValue = uint256(newPositionSize).mul(fillPrice).div(1e18);
    } else {
      newPositionValue = uint256(-newPositionSize).mul(fillPrice).div(1e18);
    }
  }

  function _maxLeverageCheckModifyCollateral(
    address to,
    uint128 marketId,
    uint128 accountId,
    int256 amountDelta,
    int256 availableMargin
  ) internal view {
    int128 positionSize = IPerpsAccountModule(to).getOpenPositionSize(accountId, marketId);
    uint256 positionValue = _getNewPositionValue(to, marketId, positionSize, 0);
    int256 newMargin = availableMargin.add(amountDelta); // newMargin must be > 0; checks are done beforehand
    require(positionValue < newMargin.toUint256().mul(MAX_LEVERAGE).div(1e18), "leverage must be less");
  }

  function _maxLeverageCheck(address to, uint128 marketId, uint128 accountId, int128 sizeDelta) internal view {
    int256 availableMargin = IPerpsAccountModule(to).getAvailableMargin(accountId);
    int128 positionSize = IPerpsAccountModule(to).getOpenPositionSize(accountId, marketId);
    uint256 newPositionValue = _getNewPositionValue(to, marketId, positionSize, sizeDelta);
    if (
      ((positionSize >= 0 && (sizeDelta > 0 || -sizeDelta > positionSize)) ||
        (positionSize <= 0 && (sizeDelta < 0 || -sizeDelta < positionSize)))
    ) {
      require(newPositionValue < availableMargin.toUint256().mul(MAX_LEVERAGE).div(1e18), "leverage must be less");
    }
  }
}
