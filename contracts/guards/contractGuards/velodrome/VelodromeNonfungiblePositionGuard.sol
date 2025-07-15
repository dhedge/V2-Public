// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IVelodromeNonfungiblePositionManager} from "../../../interfaces/velodrome/IVelodromeNonfungiblePositionManager.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {VelodromeCLPriceLibrary} from "../../../utils/velodrome/VelodromeCLPriceLibrary.sol";
import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {NftTrackerConsumerGuard} from "../shared/NftTrackerConsumerGuard.sol";

/// @title Transaction guard for Velodrome CL NonfungiblePositionManager contract
contract VelodromeNonfungiblePositionGuard is NftTrackerConsumerGuard, ITxTrackingGuard {
  using SafeMath for uint256;

  bool public override isTxTrackingGuard = true;

  /// @notice Initialiser for the contract
  /// @dev Set up the position count limit and the nft tracker
  /// @param _maxPositions Velodrome Cl liquidity position count limit
  /// @param _nftTracker Address of the DhedgeNftTrackerStorage
  constructor(
    uint256 _maxPositions,
    address _nftTracker
  ) NftTrackerConsumerGuard(_nftTracker, keccak256("VELODROME_NFT_TYPE"), _maxPositions) {}

  /// @notice Transaction guard for Velodrome CL non-fungible Position Manager
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
    IVelodromeNonfungiblePositionManager nonfungiblePositionManager = IVelodromeNonfungiblePositionManager(to);

    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(poolManagerLogicAddress);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogicAddress);
    address pool = poolManagerLogic.poolLogic();
    require(msg.sender == pool, "not pool logic");

    if (method == IVelodromeNonfungiblePositionManager.mint.selector) {
      IVelodromeNonfungiblePositionManager.MintParams memory mintParams = abi.decode(
        params,
        (IVelodromeNonfungiblePositionManager.MintParams)
      );

      require(poolManagerLogicAssets.isSupportedAsset(mintParams.token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(mintParams.token1), "unsupported asset: tokenB");
      require(poolManagerLogicAssets.isSupportedAsset(to), "velodrome cl asset not enabled");
      require(mintParams.sqrtPriceX96 == 0, "sqrtPriceX96 must be 0");
      require(pool == mintParams.recipient, "recipient is not pool");

      VelodromeCLPriceLibrary.assertFairPrice(
        IPoolLogic(pool).factory(),
        nonfungiblePositionManager.factory(),
        mintParams.token0,
        mintParams.token1,
        mintParams.tickSpacing
      );

      txType = uint16(TransactionType.VelodromeCLMint);
    } else if (method == IVelodromeNonfungiblePositionManager.increaseLiquidity.selector) {
      IVelodromeNonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = abi.decode(
        params,
        (IVelodromeNonfungiblePositionManager.IncreaseLiquidityParams)
      );

      // validate token id from nft tracker
      require(isValidOwnedTokenId(pool, increaseLiquidityParams.tokenId), "position is not in track");

      (, , address token0, address token1, int24 tickSpacing, , , , , , , ) = nonfungiblePositionManager.positions(
        increaseLiquidityParams.tokenId
      );

      VelodromeCLPriceLibrary.assertFairPrice(
        IPoolLogic(pool).factory(),
        nonfungiblePositionManager.factory(),
        token0,
        token1,
        tickSpacing
      );

      txType = uint16(TransactionType.VelodromeCLIncreaseLiquidity);
    } else if (method == IVelodromeNonfungiblePositionManager.decreaseLiquidity.selector) {
      txType = uint16(TransactionType.VelodromeCLDecreaseLiquidity);
    } else if (method == IVelodromeNonfungiblePositionManager.burn.selector) {
      txType = uint16(TransactionType.VelodromeCLBurn);
    } else if (method == IVelodromeNonfungiblePositionManager.collect.selector) {
      IVelodromeNonfungiblePositionManager.CollectParams memory collectParams = abi.decode(
        params,
        (IVelodromeNonfungiblePositionManager.CollectParams)
      );
      (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(
        collectParams.tokenId
      );

      require(poolManagerLogicAssets.isSupportedAsset(token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(token1), "unsupported asset: tokenB");
      require(pool == collectParams.recipient, "recipient is not pool");

      txType = uint16(TransactionType.VelodromeCLCollect);
    } else if (method == IMulticall.multicall.selector) {
      bytes[] memory multicallParams = abi.decode(params, (bytes[]));

      for (uint256 i = 0; i < multicallParams.length; i++) {
        (txType, ) = txGuard(poolManagerLogicAddress, to, multicallParams[i]);
        require(txType > 0, "invalid transaction");
      }

      txType = uint16(TransactionType.VelodromeCLMulticall);
    }

    return (txType, false);
  }

  /// @notice This function is called after execution transaction (used to track transactions)
  /// @dev Necessary for tracking minted NFT tokenIds and removing them upon burning the NFT position
  /// @dev Can be called only by PoolLogic during execTransaction
  /// @param poolManagerLogic Pool manager logic address
  /// @param to Velodrome CL NonfungiblePositionManager address
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
    IVelodromeNonfungiblePositionManager nonfungiblePositionManager = IVelodromeNonfungiblePositionManager(to);

    if (method == IVelodromeNonfungiblePositionManager.mint.selector) {
      uint256 index = nonfungiblePositionManager.totalSupply();
      nftTracker.addUintId(
        to,
        nftType,
        poolLogic,
        nonfungiblePositionManager.tokenByIndex(index - 1), // revert if index is zero
        positionsLimit
      );

      return true;
    } else if (method == IVelodromeNonfungiblePositionManager.burn.selector) {
      uint256 tokenId = abi.decode(getParams(data), (uint256));

      // validate token id from nft tracker
      bool isValidTokenId = isValidOwnedTokenId(poolLogic, tokenId);
      require(isValidTokenId, "position is not in track");

      nftTracker.removeUintId(to, nftType, poolLogic, tokenId);

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
