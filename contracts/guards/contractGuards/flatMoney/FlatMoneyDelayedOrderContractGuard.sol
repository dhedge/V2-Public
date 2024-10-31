// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";

import {FlatcoinModuleKeys} from "../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {IDelayedOrder} from "../../../interfaces/flatMoney/IDelayedOrder.sol";
import {IFlatcoinVault} from "../../../interfaces/flatMoney/IFlatcoinVault.sol";
import {ILeverageModule} from "../../../interfaces/flatMoney/ILeverageModule.sol";
import {IFlatMoneyDelayedOrderContractGuard} from "../../../interfaces/flatMoney/IFlatMoneyDelayedOrderContractGuard.sol";
import {IERC721VerifyingGuard} from "../../../interfaces/guards/IERC721VerifyingGuard.sol";
import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPoolFactory} from "../../../interfaces/IPoolFactory.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {DhedgeNftTrackerStorage} from "../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

/// @notice Allows buying and selling FlatMoney's flatcoin UNIT and manage leverage positions (NFTs).
contract FlatMoneyDelayedOrderContractGuard is
  IFlatMoneyDelayedOrderContractGuard,
  IERC721VerifyingGuard,
  IGuard,
  ITransactionTypes,
  TxDataUtils
{
  using SignedSafeMath for int256;
  using SafeCast for int256;
  using SafeMath for uint256;
  using SafeCast for uint256;

  /// @dev Limit of Flat Money leverage NFTs per pool
  uint256 public constant POSITIONS_LIMIT = 3;

  uint256 public constant MAX_ALLOWED_LEVERAGE = 6e18;

  bytes32 public constant NFT_TYPE = keccak256("FLAT_MONEY_LEVERAGE_NFT");

  DhedgeNftTrackerStorage public immutable nftTracker;

  mapping(address => PoolSetting) public override dHedgePoolsWhitelist;

  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _whitelisteddHedgePools dHEDGE pools that are allowed to use Flat Money Perp Market
  constructor(DhedgeNftTrackerStorage _nftTracker, PoolSetting[] memory _whitelisteddHedgePools) {
    require(address(_nftTracker) != address(0), "invalid nftTracker");

    nftTracker = _nftTracker;

    address poolFactory = _nftTracker.poolFactory();
    for (uint256 i; i < _whitelisteddHedgePools.length; ++i) {
      PoolSetting memory poolSetting = _whitelisteddHedgePools[i];
      require(
        poolSetting.poolLogic != address(0) && IPoolFactory(poolFactory).isPool(poolSetting.poolLogic),
        "invalid pool logic"
      );
      require(
        poolSetting.withdrawalAsset != address(0) &&
          IHasAssetInfo(poolFactory).isValidAsset(poolSetting.withdrawalAsset),
        "invalid withdrawal asset"
      );
      dHedgePoolsWhitelist[poolSetting.poolLogic] = poolSetting;
    }
  }

  /// @notice Retrieves the tokenIds owned by the specified PoolLogic address
  /// @param _poolLogic The address of the PoolLogic contract
  /// @return tokenIds An array of uint256 representing the tokenIds owned by the PoolLogic address
  function getOwnedTokenIds(address _poolLogic) public view override returns (uint256[] memory tokenIds) {
    tokenIds = nftTracker.getAllUintIds(NFT_TYPE, _poolLogic);
  }

  /// @notice Transaction guard for FlatMoney's DelayedOrder contract.
  /// @dev Whitelisting `cancelExistingOrder` is a must to be able to retrieve funds from the DelayedOrder contract
  ///      in case something wents wrong with the order.
  /// @dev Experiment: not emitting any events, because I've never seen their use case yet.
  /// @param _poolManagerLogic Address of the PoolManagerLogic contract
  /// @param _to DelayedOrder contract address
  /// @param _data Transaction data payload
  /// @return txType The transaction type of a given transaction data
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external view override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(_data);
    IFlatcoinVault vault = IDelayedOrder(_to).vault();
    address collateralAsset = vault.collateral();
    address leverageModule = vault.moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY);

    if (method == IDelayedOrder.announceStableDeposit.selector) {
      address stableModule = vault.moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY);

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(stableModule), "unsupported destination asset");

      txType = uint16(TransactionType.FlatMoneyStableDeposit);
    } else if (method == IDelayedOrder.announceStableWithdraw.selector) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(collateralAsset), "unsupported destination asset");

      txType = uint16(TransactionType.FlatMoneyStableWithdraw);
    } else if (method == IDelayedOrder.cancelExistingOrder.selector) {
      txType = uint16(TransactionType.FlatMoneyCancelOrder);
    } else if (method == IDelayedOrder.announceLeverageOpen.selector) {
      require(_isPoolWhitelisted(poolLogic), "not perps whitelisted");

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(leverageModule), "unsupported destination asset");

      (uint256 margin, uint256 size) = abi.decode(getParams(_data), (uint256, uint256));
      uint256 resultingLeverage = _getResultingLeverage(margin, size);
      require(resultingLeverage <= MAX_ALLOWED_LEVERAGE, "leverage too high");

      txType = uint16(TransactionType.FlatMoneyLeverageOpen);
    } else if (method == IDelayedOrder.announceLeverageAdjust.selector) {
      require(_isPoolWhitelisted(poolLogic), "not perps whitelisted");

      // Adjusting leverage position allows some portion of collateral to be withdrawn
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(collateralAsset), "unsupported destination asset");

      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(leverageModule), "unsupported destination asset");

      (uint256 tokenId, int256 marginAdjustment, int256 additionalSizeAdjustment) = abi.decode(
        getParams(_data),
        (uint256, int256, int256)
      );

      require(_isTokenIdOwned(tokenId, poolLogic), "position is not in track");
      int256 currentMargin = ILeverageModule(leverageModule).getPositionSummary(tokenId).marginAfterSettlement;
      int256 resultingMargin = currentMargin.add(marginAdjustment);
      require(resultingMargin > 0, "adjusted margin is negative");

      int256 currentAdditonalSize = (vault.getPosition(tokenId).additionalSize).toInt256();
      int256 resultingSize = currentAdditonalSize.add(additionalSizeAdjustment);
      require(resultingSize > 0, "adjusted size is negative");

      uint256 resultingLeverage = _getResultingLeverage(resultingMargin.toUint256(), resultingSize.toUint256());
      // always allow resultingLeverage <= MAX_ALLOWED_LEVERAGE
      if (resultingLeverage > MAX_ALLOWED_LEVERAGE) {
        // allow leverage decreased
        require(
          currentMargin > 0 &&
            currentAdditonalSize > 0 &&
            // only make sense to do this stricter check if currentLeverage is over max
            // under this situation, it implies: currentMargin > 0 && currentAdditonalSize > 0
            resultingLeverage < _getResultingLeverage(currentMargin.toUint256(), currentAdditonalSize.toUint256()),
          "leverage too high"
        );
      }

      txType = uint16(TransactionType.FlatMoneyLeverageAdjust);
    } else if (method == IDelayedOrder.announceLeverageClose.selector) {
      // Closing leverage positions sends collateral back to the pool
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(collateralAsset), "unsupported destination asset");

      uint256 tokenId = abi.decode(getParams(_data), (uint256));
      require(_isTokenIdOwned(tokenId, poolLogic), "position is not in track");

      txType = uint16(TransactionType.FlatMoneyLeverageClose);
    }

    return (txType, false);
  }

  /// @param _operator Address which calls onERC721Received callback
  /// @param _from Address which transfers the NFT
  /// @param _tokenId ID of the NFT
  /// @return verified True if the NFT is verified
  function verifyERC721(
    address _operator,
    address _from,
    uint256 _tokenId,
    bytes calldata
  ) external override returns (bool verified) {
    require(_isPoolWhitelisted(msg.sender), "not perps whitelisted");

    // Leverage NFTs should be minted from Flat Money protocol, not transferred from other addresses
    require(_from == address(0), "nft not minted");

    // Get currently tracked NFTs
    uint256[] memory tokenIds = getOwnedTokenIds(msg.sender);

    // Loop through tracked NFTs and check the ownership of each ID. `ownerOf` call fails if owner is address(0) which means position was burnt.
    // Catch block removes this NFT from tracked NFTs. No checks on the owner are made because what's in tracker belongs to the vault by default.
    for (uint256 i; i < tokenIds.length; ++i) {
      try
        ILeverageModule(IDelayedOrder(_operator).vault().moduleAddress(FlatcoinModuleKeys._LEVERAGE_MODULE_KEY))
          .ownerOf(tokenIds[i])
      returns (
        address // solhint-disable-next-line no-empty-blocks
      ) {} catch {
        nftTracker.removeUintId({
          _guardedContract: _operator,
          _nftType: NFT_TYPE,
          _pool: msg.sender,
          _nftID: tokenIds[i]
        });
      }
    }

    // This is the only place where NFT IDs are added to the tracker.
    nftTracker.addUintId({
      _guardedContract: _operator,
      _nftType: NFT_TYPE,
      _pool: msg.sender,
      _nftID: _tokenId,
      _maxPositions: POSITIONS_LIMIT
    });

    verified = true;
  }

  /// @notice Helper function to check if the pool is whitelisted
  /// @param _wanted PoolLogic address of interest
  /// @return whitelisted If the address is whitelisted
  function _isPoolWhitelisted(address _wanted) internal view returns (bool whitelisted) {
    require(_wanted != address(0), "invalid pool logic");

    whitelisted = dHedgePoolsWhitelist[_wanted].poolLogic == _wanted;
  }

  /// @notice Checks if the specified tokenId is owned by the given pool
  /// @param _tokenId The specified tokenId
  /// @param _poolLogic The address of the PoolLogic contract
  /// @return valid A boolean indicating whether the specified tokenId is owned by the pool
  function _isTokenIdOwned(uint256 _tokenId, address _poolLogic) internal view returns (bool valid) {
    uint256[] memory tokenIds = getOwnedTokenIds(_poolLogic);
    for (uint256 i; i < tokenIds.length; ++i) {
      if (_tokenId == tokenIds[i]) {
        return true;
      }
    }
    return false;
  }

  /// @notice Asserts that the position to be opened meets max allowed leverage criteria.
  /// @param _margin The margin to be deposited.
  /// @param _size The size of the position.
  function _getResultingLeverage(uint256 _margin, uint256 _size) internal pure returns (uint256 resultingLeverage) {
    resultingLeverage = ((_margin.add(_size)).mul(1e18)).div(_margin);
  }
}
