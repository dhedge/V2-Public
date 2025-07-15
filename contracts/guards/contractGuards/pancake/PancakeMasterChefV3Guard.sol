// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IPancakeMasterChefV3} from "../../../interfaces/pancake/IPancakeMasterChefV3.sol";
import {IPancakeNonfungiblePositionManager} from "../../../interfaces/pancake/IPancakeNonfungiblePositionManager.sol";
import {UniswapV3PriceLibrary} from "../../../utils/uniswap/UniswapV3PriceLibrary.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IERC721VerifyingGuard} from "../../../interfaces/guards/IERC721VerifyingGuard.sol";
import {PancakeCLBaseContractGuard} from "./PancakeCLBaseContractGuard.sol";

/// @title Transaction guard for Pancake MasterChefV3 (staking) contract
contract PancakeMasterChefV3Guard is IERC721VerifyingGuard, PancakeCLBaseContractGuard {
  using SafeMath for uint256;

  /// @notice Initialiser for the contract
  /// @dev Set up the nft tracker
  /// @param _nftTracker Address of the DhedgeNftTrackerStorage
  constructor(address _nftTracker) PancakeCLBaseContractGuard(_nftTracker) {}

  /// @notice Transaction guard for Pancake CL Staking contract
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
    view
    override
    returns (
      uint16 txType, // transaction type
      bool // isPublic
    )
  {
    bytes4 method = getMethod(data);
    bytes memory params = getParams(data);
    IPancakeMasterChefV3 masterChef = IPancakeMasterChefV3(to);

    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(poolManagerLogicAddress);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogicAddress);
    address pool = poolManagerLogic.poolLogic();
    require(msg.sender == pool, "not pool logic");
    IPancakeNonfungiblePositionManager nonfungiblePositionManager = masterChef.nonfungiblePositionManager();

    require(
      poolManagerLogicAssets.isSupportedAsset(address(nonfungiblePositionManager)),
      "pancake CL asset not enabled"
    );

    if (method == IPancakeNonfungiblePositionManager.collect.selector) {
      IPancakeNonfungiblePositionManager.CollectParams memory collectParams = abi.decode(
        params,
        (IPancakeNonfungiblePositionManager.CollectParams)
      );
      (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(
        collectParams.tokenId
      );

      require(collectParams.amount0Max == type(uint128).max, "amount0Max is not max");
      require(collectParams.amount1Max == type(uint128).max, "amount1Max is not max");
      require(isValidOwnedTokenId(pool, collectParams.tokenId), "position is not in track");
      require(poolManagerLogicAssets.isSupportedAsset(token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(token1), "unsupported asset: tokenB");
      require(collectParams.recipient == pool, "invalid recipient");
      txType = uint16(TransactionType.PancakeCLCollect);
    } else if (method == IPancakeMasterChefV3.harvest.selector) {
      _validateHarvestTx(pool, params);
      txType = uint16(TransactionType.PancakeCLHarvest);
    } else if (method == IPancakeNonfungiblePositionManager.increaseLiquidity.selector) {
      IPancakeNonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = abi.decode(
        params,
        (IPancakeNonfungiblePositionManager.IncreaseLiquidityParams)
      );
      // validate token id from nft tracker
      require(isValidOwnedTokenId(pool, increaseLiquidityParams.tokenId), "position is not in track");

      (, , address token0, address token1, uint24 fee, , , , , , , ) = nonfungiblePositionManager.positions(
        increaseLiquidityParams.tokenId
      );

      UniswapV3PriceLibrary.assertFairPrice(
        IPoolLogic(pool).factory(),
        nonfungiblePositionManager.factory(),
        token0,
        token1,
        fee
      );

      txType = uint16(TransactionType.PancakeCLIncreaseLiquidity);
    } else if (method == IPancakeMasterChefV3.withdraw.selector) {
      (uint256 tokenId, address receiver) = abi.decode(params, (uint256, address));
      require(isValidOwnedTokenId(pool, tokenId), "position is not in track");
      require(receiver == pool, "invalid recipient");
      txType = uint16(TransactionType.PancakeCLUnstake);
    } else if (method == IPancakeNonfungiblePositionManager.burn.selector) {
      txType = uint16(TransactionType.PancakeCLBurn);
    } else if (method == IMulticall.multicall.selector) {
      bytes[] memory multicallParams = abi.decode(params, (bytes[]));
      uint256 multicallParamsLength = multicallParams.length;
      for (uint256 i = 0; i < multicallParamsLength; i++) {
        if (getMethod(multicallParams[i]) == IPancakeNonfungiblePositionManager.decreaseLiquidity.selector) {
          require(multicallParamsLength > 1 && i != multicallParamsLength - 1, "no collect after decrease");
          bytes4 nextMethod = getMethod(multicallParams[i + 1]);
          //After decrease liquidity collect must be called
          require(nextMethod == IPancakeNonfungiblePositionManager.collect.selector, "no collect after decrease");
          //Decrease liquidity must not be called as a single transaction
          _validateDecreaseLiquidityTx(pool, getParams(multicallParams[i]));
          txType = uint16(TransactionType.PancakeCLDecreaseLiquidity);
        } else {
          (txType, ) = txGuard(poolManagerLogicAddress, to, multicallParams[i]);
        }
        require(txType > 0, "invalid transaction");
      }

      txType = uint16(TransactionType.PancakeCLMulticall);
    }
    return (txType, false);
  }

  function _validateDecreaseLiquidityTx(address pool, bytes memory params) internal view {
    IPancakeNonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = abi.decode(
      params,
      (IPancakeNonfungiblePositionManager.DecreaseLiquidityParams)
    );
    require(isValidOwnedTokenId(pool, decreaseLiquidityParams.tokenId), "position is not in track");
  }

  function _validateHarvestTx(address pool, bytes memory params) internal view {
    (uint256 tokenId, address receiver) = abi.decode(params, (uint256, address));
    require(isValidOwnedTokenId(pool, tokenId), "position is not in track");
    require(receiver == pool, "invalid recipient");
  }

  function verifyERC721(
    address /* operator */,
    address /* from */,
    uint256 /* tokenId */,
    bytes calldata
  ) external pure override returns (bool verified) {
    verified = true;
  }

  /// @notice This function is called after execution transaction (used to track transactions)
  /// @dev Necessary for tracking minted NFT tokenIds and removing them upon burning the NFT position
  /// @dev Can be called only by PoolLogic during execTransaction
  /// @param poolManagerLogic Pool manager logic address
  /// @param to PancakeMasterChefV3 address
  /// @param data Transaction data
  function afterTxGuard(address poolManagerLogic, address to, bytes memory data) public virtual override {
    _afterTxGuardHandle(poolManagerLogic, to, data);
  }

  function _afterTxGuardHandle(address poolManagerLogic, address to, bytes memory data) internal returns (bool isBurn) {
    address poolLogic = IPoolManagerLogic(poolManagerLogic).poolLogic();
    require(msg.sender == poolLogic, "not pool logic");

    bytes4 method = getMethod(data);

    if (method == IPancakeNonfungiblePositionManager.burn.selector) {
      uint256 tokenId = abi.decode(getParams(data), (uint256));

      // validate token id from nft tracker
      bool isValidTokenId = isValidOwnedTokenId(poolLogic, tokenId);
      require(isValidTokenId, "position is not in track");

      nftTracker.removeUintId(to, nftType, poolLogic, tokenId);

      return true;
    } else if (method == IMulticall.multicall.selector) {
      bytes[] memory params = abi.decode(getParams(data), (bytes[]));

      bool includeBurn;
      for (uint256 i = 0; i < params.length; i++) {
        if (_afterTxGuardHandle(poolManagerLogic, to, params[i])) {
          require(!includeBurn, "invalid multicall");
          includeBurn = true;
        }
      }

      return includeBurn;
    }

    return false;
  }
}
