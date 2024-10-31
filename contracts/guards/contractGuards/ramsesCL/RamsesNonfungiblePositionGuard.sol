// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {IRamsesNonfungiblePositionManager} from "../../../interfaces/ramses/IRamsesNonfungiblePositionManager.sol";
import {UniswapV3PriceLibrary} from "../../../utils/uniswap/UniswapV3PriceLibrary.sol";
import {DhedgeNftTrackerStorage} from "../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IRamsesGaugeV2} from "../../../interfaces/ramses/IRamsesGaugeV2.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IRamsesVoter} from "../../../interfaces/ramses/IRamsesVoter.sol";

/// @title Transaction guard for Ramses CL NonfungiblePositionManager contract
contract RamsesNonfungiblePositionGuard is TxDataUtils, ITxTrackingGuard, ITransactionTypes {
  using SafeMath for uint256;

  bytes32 public constant NFT_TYPE = keccak256("RAMSES_CL_NFT_TYPE");
  DhedgeNftTrackerStorage public immutable nftTracker;

  // ramses cl liquidity position count limit
  uint256 public immutable positionsLimit;

  bool public override isTxTrackingGuard = true;

  /// @notice Initialiser for the contract
  /// @dev Set up the position count limit and the nft tracker
  /// @param maxPositions Velodrome Cl liquidity position count limit
  /// @param nftTrackerAddress Address of the DhedgeNftTrackerStorage
  constructor(uint256 maxPositions, address nftTrackerAddress) {
    positionsLimit = maxPositions;
    nftTracker = DhedgeNftTrackerStorage(nftTrackerAddress);
  }

  /// @notice Retrieves the tokenIds owned by the specified poolLogic address
  /// @param poolLogic The address of the pool logic contract
  /// @return tokenIds An array of uint256 representing the tokenIds owned by the poolLogic address
  function getOwnedTokenIds(address poolLogic) public view returns (uint256[] memory tokenIds) {
    return nftTracker.getAllUintIds(NFT_TYPE, poolLogic);
  }

  /// @notice Checks if the specified tokenId is owned by the given pool
  /// @param poolLogic The address of the pool logic contract
  /// @param tokenId The specified tokenId
  /// @return isValid A boolean indicating whether the specified tokenId is owned by the pool
  function isValidOwnedTokenId(address poolLogic, uint256 tokenId) public view returns (bool isValid) {
    // find token ids from nft tracker
    uint256[] memory tokenIds = getOwnedTokenIds(poolLogic);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      if (tokenId == tokenIds[i]) {
        return true;
      }
    }
    return false;
  }

  /// @notice Transaction guard for Ramses CL non-fungible Position Manager
  /// @dev Parses the manager transaction data to ensure transaction is valid
  /// @param poolManagerLogicAddress Pool address
  /// @param data Transaction call data attempt by manager
  /// @return txType transaction type described in PoolLogic
  /// @return isPublic if the transaction is public or private
  function txGuard(
    address poolManagerLogicAddress,
    address to,
    bytes memory data
  )
    public
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    bytes memory params = getParams(data);
    IRamsesNonfungiblePositionManager nonfungiblePositionManager = IRamsesNonfungiblePositionManager(to);

    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(poolManagerLogicAddress);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogicAddress);
    address pool = poolManagerLogic.poolLogic();
    address factory = IPoolLogic(pool).factory();
    IRamsesVoter voter = IRamsesVoter(nonfungiblePositionManager.voter());
    require(msg.sender == pool, "not pool logic");

    if (method == IRamsesNonfungiblePositionManager.mint.selector) {
      IRamsesNonfungiblePositionManager.MintParams memory mintParams = abi.decode(
        params,
        (IRamsesNonfungiblePositionManager.MintParams)
      );

      require(poolManagerLogicAssets.isSupportedAsset(mintParams.token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(mintParams.token1), "unsupported asset: tokenB");
      require(poolManagerLogicAssets.isSupportedAsset(to), "ramses cl asset not enabled");
      require(mintParams.veRamTokenId == 0, "veRamTokenId must be 0"); // CL Boosting deprecated
      require(pool == mintParams.recipient, "recipient is not pool");

      address ramsesFactory = nonfungiblePositionManager.factory();
      // can use UniswapV3PriceLibrary
      UniswapV3PriceLibrary.assertFairPrice(
        factory,
        ramsesFactory,
        mintParams.token0,
        mintParams.token1,
        mintParams.fee
      );

      IRamsesGaugeV2 gauge = IRamsesGaugeV2(
        voter.gauges(IUniswapV3Factory((ramsesFactory)).getPool(mintParams.token0, mintParams.token1, mintParams.fee))
      );
      address[] memory rewardTokens = gauge.getRewardTokens();
      for (uint256 i = 0; i < rewardTokens.length; ++i) {
        // staking-equivalent checks
        if (IHasAssetInfo(factory).isValidAsset(rewardTokens[i])) {
          require(poolManagerLogicAssets.isSupportedAsset(rewardTokens[i]), "reward asset not enabled");
        }
      }

      txType = uint16(TransactionType.RamsesCLMint);
    } else if (method == IRamsesNonfungiblePositionManager.increaseLiquidity.selector) {
      IRamsesNonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = abi.decode(
        params,
        (IRamsesNonfungiblePositionManager.IncreaseLiquidityParams)
      );

      // validate token id from nft tracker
      bool isValidTokenId = isValidOwnedTokenId(pool, increaseLiquidityParams.tokenId);
      require(isValidTokenId, "position is not in track");

      (, , address token0, address token1, uint24 fee, , , , , , , ) = nonfungiblePositionManager.positions(
        increaseLiquidityParams.tokenId
      );

      // can use UniswapV3PriceLibrary
      UniswapV3PriceLibrary.assertFairPrice(factory, nonfungiblePositionManager.factory(), token0, token1, fee);

      txType = uint16(TransactionType.RamsesCLIncreaseLiquidity);
    } else if (method == IRamsesNonfungiblePositionManager.decreaseLiquidity.selector) {
      txType = uint16(TransactionType.RamsesCLDecreaseLiquidity);
    } else if (method == IRamsesNonfungiblePositionManager.burn.selector) {
      txType = uint16(TransactionType.RamsesCLBurn);
    } else if (method == IRamsesNonfungiblePositionManager.collect.selector) {
      IRamsesNonfungiblePositionManager.CollectParams memory collectParams = abi.decode(
        params,
        (IRamsesNonfungiblePositionManager.CollectParams)
      );
      (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(
        collectParams.tokenId
      );

      require(poolManagerLogicAssets.isSupportedAsset(token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(token1), "unsupported asset: tokenB");
      require(pool == collectParams.recipient, "recipient is not pool");

      txType = uint16(TransactionType.RamsesCLCollect);
    } else if (method == IRamsesNonfungiblePositionManager.getReward.selector) {
      uint256 tokenId = abi.decode(params, (uint256));

      bool isValidTokenId = isValidOwnedTokenId(pool, tokenId);
      require(isValidTokenId, "position is not in track");

      txType = uint16(TransactionType.RamsesCLGetReward);
    } else if (method == IMulticall.multicall.selector) {
      bytes[] memory multicallParams = abi.decode(params, (bytes[]));

      for (uint256 i = 0; i < multicallParams.length; i++) {
        (txType, ) = txGuard(poolManagerLogicAddress, to, multicallParams[i]);
        require(txType > 0, "invalid transaction");
      }

      txType = uint16(TransactionType.RamsesCLMulticall);
    }
    return (txType, false);
  }

  /// @notice This function is called after execution transaction (used to track transactions)
  /// @dev Necessary for tracking minted NFT tokenIds and removing them upon burning the NFT position
  /// @dev Can be called only by PoolLogic during execTransaction
  /// @param poolManagerLogic Pool manager logic address
  /// @param to Ramses CL NonfungiblePositionManager address
  /// @param data Transaction data
  function afterTxGuard(address poolManagerLogic, address to, bytes memory data) public virtual override {
    _afterTxGuardHandle(poolManagerLogic, to, data);
  }

  function _afterTxGuardHandle(
    address poolManagerLogic,
    address to,
    bytes memory data
  ) internal returns (bool isMintOrBurn) {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(data);
    IRamsesNonfungiblePositionManager nonfungiblePositionManager = IRamsesNonfungiblePositionManager(to);

    if (method == IRamsesNonfungiblePositionManager.mint.selector) {
      uint256 index = nonfungiblePositionManager.totalSupply();
      nftTracker.addUintId(
        to,
        NFT_TYPE,
        poolLogic,
        nonfungiblePositionManager.tokenByIndex(index - 1), // revert if index is zero
        positionsLimit
      );

      return true;
    } else if (method == IRamsesNonfungiblePositionManager.burn.selector) {
      uint256 tokenId = abi.decode(getParams(data), (uint256));

      // validate token id from nft tracker
      bool isValidTokenId = isValidOwnedTokenId(poolLogic, tokenId);
      require(isValidTokenId, "position is not in track");

      nftTracker.removeUintId(to, NFT_TYPE, poolLogic, tokenId);

      return true;
    } else if (method == IMulticall.multicall.selector) {
      bytes[] memory params = abi.decode(getParams(data), (bytes[]));

      bool includeMintOrBurn;
      for (uint256 i = 0; i < params.length; i++) {
        if (_afterTxGuardHandle(poolManagerLogic, to, params[i])) {
          require(!includeMintOrBurn, "invalid multicall");
          includeMintOrBurn = true;
        }
      }

      return includeMintOrBurn;
    }

    return false;
  }
}
