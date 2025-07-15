// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/math/SignedSafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";

import {IGuard} from "../../../../interfaces/guards/IGuard.sol";
import {IDelayedOrder} from "../../../../interfaces/flatMoney/IDelayedOrder.sol";
import {IFlatcoinVault} from "../../../../interfaces/flatMoney/IFlatcoinVault.sol";
import {ILeverageModule} from "../../../../interfaces/flatMoney/ILeverageModule.sol";
import {IHasAssetInfo} from "../../../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../../../interfaces/IHasSupportedAsset.sol";
import {IPoolFactory} from "../../../../interfaces/IPoolFactory.sol";
import {FlatcoinModuleKeys} from "../../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {DhedgeNftTrackerStorage} from "../../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {NftTrackerConsumerGuard} from "../../shared/NftTrackerConsumerGuard.sol";

abstract contract FlatMoneyBasisContractGuard is NftTrackerConsumerGuard, IGuard {
  using SignedSafeMath for int256;
  using SafeCast for int256;
  using SafeMath for uint256;
  using SafeCast for uint256;

  struct PoolSetting {
    address poolLogic;
    address withdrawalAsset;
  }

  uint256 public immutable MAX_ALLOWED_LEVERAGE;

  mapping(address => PoolSetting) public dHedgePoolsWhitelist;

  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _whitelisteddHedgePools dHEDGE pools that are allowed to use Flat Money Perp Market
  constructor(
    address _nftTracker,
    bytes32 _nftType,
    uint256 _maxPositions,
    PoolSetting[] memory _whitelisteddHedgePools,
    uint256 _maxAllowedLeverage
  ) NftTrackerConsumerGuard(_nftTracker, _nftType, _maxPositions) {
    address poolFactory = DhedgeNftTrackerStorage(_nftTracker).poolFactory();
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

    MAX_ALLOWED_LEVERAGE = _maxAllowedLeverage;
  }

  /// @notice Helper function to check if the pool is whitelisted
  /// @param _wanted PoolLogic address of interest
  /// @return whitelisted If the address is whitelisted
  function _isPoolWhitelisted(address _wanted) internal view returns (bool whitelisted) {
    require(_wanted != address(0), "invalid pool logic");

    whitelisted = dHedgePoolsWhitelist[_wanted].poolLogic == _wanted;
  }

  /// @notice Asserts that the position to be opened meets max allowed leverage criteria.
  /// @param _margin The margin to be deposited.
  /// @param _size The size of the position.
  function _getResultingLeverage(uint256 _margin, uint256 _size) internal pure returns (uint256 resultingLeverage) {
    resultingLeverage = ((_margin.add(_size)).mul(1e18)).div(_margin);
  }

  function _verifyStableDeposit(address _poolManagerLogic, address _vault) internal view returns (uint16 txType) {
    address stableModule = IFlatcoinVault(_vault).moduleAddress(FlatcoinModuleKeys._STABLE_MODULE_KEY);

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(stableModule), "unsupported destination asset");

    txType = uint16(TransactionType.FlatMoneyStableDeposit);
  }

  function _verifyStableWithdraw(
    address _poolManagerLogic,
    address _collateralAsset
  ) internal view returns (uint16 txType) {
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_collateralAsset), "unsupported destination asset");

    txType = uint16(TransactionType.FlatMoneyStableWithdraw);
  }

  function _verifyLeverageOpen(
    address _poolManagerLogic,
    address _leverageModule,
    bytes memory _params
  ) internal view returns (uint16 txType) {
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_leverageModule), "unsupported destination asset");

    (uint256 margin, uint256 size) = abi.decode(_params, (uint256, uint256));
    uint256 resultingLeverage = _getResultingLeverage(margin, size);
    require(resultingLeverage <= MAX_ALLOWED_LEVERAGE, "leverage too high");

    txType = uint16(TransactionType.FlatMoneyLeverageOpen);
  }

  function _verifyLeverageAdjust(
    address _poolManagerLogic,
    address _poolLogic,
    address _collateralAsset,
    address _leverageModule,
    address _vault,
    bytes memory _params
  ) internal view returns (uint16 txType) {
    // Adjusting leverage position allows some portion of collateral to be withdrawn
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_collateralAsset), "unsupported destination asset");

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_leverageModule), "unsupported destination asset");

    (uint256 tokenId, int256 marginAdjustment, int256 additionalSizeAdjustment) = abi.decode(
      _params,
      (uint256, int256, int256)
    );

    require(isValidOwnedTokenId(_poolLogic, tokenId), "position is not in track");
    int256 currentMargin = ILeverageModule(_leverageModule).getPositionSummary(tokenId).marginAfterSettlement;
    int256 resultingMargin = currentMargin.add(marginAdjustment);
    require(resultingMargin > 0, "adjusted margin is negative");

    int256 currentAdditonalSize = (IFlatcoinVault(_vault).getPosition(tokenId).additionalSize).toInt256();
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
  }

  function _verifyLeverageClose(
    address _poolManagerLogic,
    address _poolLogic,
    address _collateralAsset,
    bytes memory _params
  ) internal view returns (uint16 txType) {
    // Closing leverage positions sends collateral back to the pool
    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_collateralAsset), "unsupported destination asset");

    uint256 tokenId = abi.decode(_params, (uint256));
    require(isValidOwnedTokenId(_poolLogic, tokenId), "position is not in track");

    txType = uint16(TransactionType.FlatMoneyLeverageClose);
  }

  /// @param _operator Address which calls onERC721Received callback
  /// @param _from Address which transfers the NFT
  /// @param _tokenId ID of the NFT
  /// @return verified True if the NFT is verified
  function _verifyERC721(address _operator, address _from, uint256 _tokenId) internal returns (bool verified) {
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
          _nftType: nftType,
          _pool: msg.sender,
          _nftID: tokenIds[i]
        });
      }
    }

    // This is the only place where NFT IDs are added to the tracker.
    nftTracker.addUintId({
      _guardedContract: _operator,
      _nftType: nftType,
      _pool: msg.sender,
      _nftID: _tokenId,
      _maxPositions: positionsLimit
    });

    verified = true;
  }
}
