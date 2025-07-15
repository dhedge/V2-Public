// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IPancakeNonfungiblePositionManager} from "../../../interfaces/pancake/IPancakeNonfungiblePositionManager.sol";
import {IMulticall} from "@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {UniswapV3PriceLibrary} from "../../../utils/uniswap/UniswapV3PriceLibrary.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {PancakeCLBaseContractGuard} from "./PancakeCLBaseContractGuard.sol";

/// @title Transaction guard for Pancake CL NonfungiblePositionManager contract
contract PancakeNonfungiblePositionGuard is PancakeCLBaseContractGuard {
  using SafeMath for uint256;

  // Pancake masterchef address
  address public immutable stakingAddress;

  /// @notice Initialiser for the contract
  /// @param _nftTracker Address of the DhedgeNftTrackerStorage
  /// @param _stakingAddress Pancake MasterchefV3 contract address
  constructor(address _nftTracker, address _stakingAddress) PancakeCLBaseContractGuard(_nftTracker) {
    stakingAddress = _stakingAddress;
  }

  /// @notice Transaction guard for Pancake CL non-fungible Position Manager
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
    IPancakeNonfungiblePositionManager nonfungiblePositionManager = IPancakeNonfungiblePositionManager(to);

    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(poolManagerLogicAddress);
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(poolManagerLogicAddress);
    address pool = poolManagerLogic.poolLogic();
    require(msg.sender == pool, "not pool logic");

    if (method == IPancakeNonfungiblePositionManager.mint.selector) {
      IPancakeNonfungiblePositionManager.MintParams memory mintParams = abi.decode(
        params,
        (IPancakeNonfungiblePositionManager.MintParams)
      );

      require(poolManagerLogicAssets.isSupportedAsset(mintParams.token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(mintParams.token1), "unsupported asset: tokenB");
      require(poolManagerLogicAssets.isSupportedAsset(to), "pancake cl asset not enabled");
      require(pool == mintParams.recipient, "recipient is not pool");

      UniswapV3PriceLibrary.assertFairPrice(
        IPoolLogic(pool).factory(),
        nonfungiblePositionManager.factory(),
        mintParams.token0,
        mintParams.token1,
        mintParams.fee
      );

      txType = uint16(TransactionType.PancakeCLMint);
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
    } else if (method == IPancakeNonfungiblePositionManager.decreaseLiquidity.selector) {
      txType = uint16(TransactionType.PancakeCLDecreaseLiquidity);
    } else if (method == IPancakeNonfungiblePositionManager.burn.selector) {
      txType = uint16(TransactionType.PancakeCLBurn);
    } else if (method == IPancakeNonfungiblePositionManager.collect.selector) {
      IPancakeNonfungiblePositionManager.CollectParams memory collectParams = abi.decode(
        params,
        (IPancakeNonfungiblePositionManager.CollectParams)
      );
      (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(
        collectParams.tokenId
      );

      require(poolManagerLogicAssets.isSupportedAsset(token0), "unsupported asset: tokenA");
      require(poolManagerLogicAssets.isSupportedAsset(token1), "unsupported asset: tokenB");
      require(pool == collectParams.recipient, "recipient is not pool");

      txType = uint16(TransactionType.PancakeCLCollect);
    } else if (method == bytes4(keccak256("safeTransferFrom(address,address,uint256)"))) {
      (address transferFrom, address transferTo, uint256 tokenId) = abi.decode(params, (address, address, uint256));
      // validate token id from nft tracker
      bool isValidTokenId = isValidOwnedTokenId(pool, tokenId);
      require(isValidTokenId, "position is not in track");
      require(transferFrom == pool, "from is not pool");
      require(transferTo == stakingAddress, "to is not staking address");
      txType = uint16(TransactionType.PancakeCLStake);
    } else if (method == IMulticall.multicall.selector) {
      bytes[] memory multicallParams = abi.decode(params, (bytes[]));

      for (uint256 i = 0; i < multicallParams.length; i++) {
        (txType, ) = txGuard(poolManagerLogicAddress, to, multicallParams[i]);
        require(txType > 0, "invalid transaction");
      }

      txType = uint16(TransactionType.PancakeCLMulticall);
    }

    return (txType, false);
  }

  /// @notice This function is called after execution transaction (used to track transactions)
  /// @dev Necessary for tracking minted NFT tokenIds and removing them upon burning the NFT position
  /// @dev Can be called only by PoolLogic during execTransaction
  /// @param poolManagerLogic Pool manager logic address
  /// @param to Pancake CL NonfungiblePositionManager address
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
    IPancakeNonfungiblePositionManager nonfungiblePositionManager = IPancakeNonfungiblePositionManager(to);

    if (method == IPancakeNonfungiblePositionManager.mint.selector) {
      uint256 index = nonfungiblePositionManager.totalSupply();
      nftTracker.addUintId(
        to,
        nftType,
        poolLogic,
        nonfungiblePositionManager.tokenByIndex(index - 1), // revert if index is zero
        positionsLimit
      );

      return true;
    } else if (method == IPancakeNonfungiblePositionManager.burn.selector) {
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
