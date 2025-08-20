// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {SafeERC20} from "../../utils/SafeERC20.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";

import {ISwapper} from "../../interfaces/flatMoney/swapper/ISwapper.sol";
import {IHasAssetInfo} from "../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";
import {IPoolLogic} from "../../interfaces/IPoolLogic.sol";
import {EasySwapperUniV3Helpers} from "../easySwapper/EasySwapperUniV3Helpers.sol";
import {EasySwapperVelodromeCLHelpers} from "../easySwapper/EasySwapperVelodromeCLHelpers.sol";
import {EasySwapperVelodromeLPHelpers} from "../easySwapper/EasySwapperVelodromeLPHelpers.sol";
import {IEasySwapperV2} from "./interfaces/IEasySwapperV2.sol";
import {IWithdrawalVault} from "./interfaces/IWithdrawalVault.sol";
import {SwapperV2Helpers} from "./libraries/SwapperV2Helpers.sol";

/// @author dHEDGE team
contract WithdrawalVault is IWithdrawalVault, Initializable {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
  using SafeERC20 for IERC20;
  using SafeMathUpgradeable for uint256;

  /// @dev Buffer value which estimates how many basic assets maximum can be unrolled out of single asset (eg. some LP token)
  uint256 internal constant ASSET_MULTIPLIER = 5;

  /// @notice The address to which the vault belongs to
  address public depositor;
  /// @notice Factory contract which spawned this vault
  address public creator;

  /// @dev Set of all basic assets that were unrolled from dHEDGE vaults
  EnumerableSetUpgradeable.AddressSet private srcAssets;

  modifier onlyCreator() {
    require(msg.sender == creator, "only creator");
    _;
  }

  /// @param _depositor Address of the depositor, who initiated witdrawal using EasySwapperv2
  /// @param _creator Address of the creator (EasySwapperV2 contract)
  function initialize(address _depositor, address _creator) external initializer {
    require(_depositor != address(0), "invalid address");
    require(_creator != address(0), "invalid address");

    depositor = _depositor;
    creator = _creator;
  }

  /// @notice Unroll assets from dHEDGE vault to basic ERC20 tokens that can be swapped via DEXes
  /// @param _dHedgeVault dHEDGE Vault address
  function unrollAssets(address _dHedgeVault) external override onlyCreator {
    _unrollAssets(_dHedgeVault);
  }

  /// @notice Swaps basic assets to a single asset
  /// @dev Client should call `getTrackedAssets` to be able to obtain swap txs
  ///      High slippage check is performed downstream at Swapper contract
  /// @param _swapData The struct containing all the data required to process the swap(s)
  function swapToSingleAsset(
    MultiInSingleOutData calldata _swapData,
    uint256 _expectedDestTokenAmount
  ) external override onlyCreator returns (uint256 balanceAfterSwaps) {
    ISwapper swapper = IEasySwapperV2(creator).swapper();

    for (uint256 i; i < _swapData.srcData.length; ++i) {
      // Can only swap all tracked assets at one go
      require(
        _swapData.srcData[i].token.balanceOf(address(this)) == _swapData.srcData[i].amount,
        "src amount mismatch"
      );
      _swapData.srcData[i].token.safeIncreaseAllowance(address(swapper), _swapData.srcData[i].amount);
    }

    ISwapper.InOutData memory swapProps;
    ISwapper.SrcData[] memory srcData = new ISwapper.SrcData[](1);
    srcData[0].srcTokenSwapDetails = _swapData.srcData;
    srcData[0].transferMethodData.method = ISwapper.TransferMethod.ALLOWANCE;
    swapProps.srcData = srcData;
    swapProps.destData = _swapData.destData;

    swapper.swap(swapProps);

    balanceAfterSwaps = _swapData.destData.destToken.balanceOf(address(this));

    require(balanceAfterSwaps >= _expectedDestTokenAmount, "high swap slippage");

    for (uint256 i; i < _swapData.srcData.length; ++i) {
      srcAssets.remove(address(_swapData.srcData[i].token));
    }
    srcAssets.remove(address(_swapData.destData.destToken));

    if (balanceAfterSwaps > 0) _swapData.destData.destToken.safeTransfer(depositor, balanceAfterSwaps);
  }

  /// @notice If depositor wants to recover their basic assets without swapping them
  /// @dev Recover all tracked assets to the depositor
  function recoverAssets() external override onlyCreator {
    _recoverAllAssets(depositor);
  }

  function recoverAssets(uint256 _portion, address _to) external override onlyCreator {
    if (_portion == 1e18) {
      _recoverAllAssets(_to);
    } else {
      uint256 setLength = srcAssets.length();
      address srcAsset;
      uint256 portionToTransfer;
      for (uint256 i; i < setLength; ++i) {
        srcAsset = srcAssets.at(i);
        portionToTransfer = IERC20(srcAsset).balanceOf(address(this)).mul(_portion).div(1e18);
        if (portionToTransfer > 0) {
          IERC20(srcAsset).safeTransfer(_to, portionToTransfer);
        }
      }
    }
  }

  /// @notice For client code to know which assets are available for swapping
  /// @return trackedAssets full array of basic assets and their balances
  function getTrackedAssets() external view override returns (TrackedAsset[] memory trackedAssets) {
    uint256 setLength = srcAssets.length();
    trackedAssets = new TrackedAsset[](setLength);
    for (uint256 i; i < setLength; ++i) {
      trackedAssets[i] = TrackedAsset({
        token: srcAssets.at(i),
        balance: IERC20(srcAssets.at(i)).balanceOf(address(this))
      });
    }
  }

  function _unrollAssets(address _dHedgeVault) internal {
    address poolManagerLogic = IPoolLogic(_dHedgeVault).poolManagerLogic();
    IHasSupportedAsset.Asset[] memory supportedAssets = IHasSupportedAsset(poolManagerLogic).getSupportedAssets();
    address poolFactory = IPoolLogic(_dHedgeVault).factory();
    address[] memory basicAssets = new address[](supportedAssets.length.mul(ASSET_MULTIPLIER));
    uint8 hits;

    for (uint256 i; i < supportedAssets.length; ++i) {
      address asset = supportedAssets[i].asset;
      uint16 assetType = IHasAssetInfo(poolFactory).getAssetType(asset);
      address[] memory unrolledAssets;

      // Regular ERC20 tokens and dHEDGE vaults
      if (assetType == 0) {
        unrolledAssets = _detectDhedgeVault(asset);
      }
      // Regular ERC20 tokens
      else if (assetType == 1 || assetType == 4 || assetType == 14 || assetType == 22 || assetType == 200) {
        unrolledAssets = _arraify(asset);
      }
      // Aave positions (3 and 8) are withdrawn as regular ERC20s, which are guaranteed to be in `supportedAssets`.
      // Same for "Assets" which use outside liquidity for withdrawals, like Flat Money's Leverage and GMX. Underlying ERC20 is guaranteed to be in `supportedAssets`.
      else if (
        assetType == 3 || assetType == 8 || assetType == 27 || assetType == 32 || assetType == 36 || assetType == 105
        // solhint-disable-next-line no-empty-blocks
      ) {}
      // Uniswap V3 - already unrolled, just need the assets
      else if (assetType == 7) {
        unrolledAssets = EasySwapperUniV3Helpers.getUnsupportedUniV3Assets(_dHedgeVault, asset);
      }
      // Velodrome V2
      else if (assetType == 25) {
        unrolledAssets = EasySwapperVelodromeLPHelpers.unrollLpAndGetUnsupportedLpAssetsAndRewards(
          poolFactory,
          asset,
          true
        );
      }
      // Velodrome/Aerodrome CL
      else if (assetType == 26) {
        unrolledAssets = EasySwapperVelodromeCLHelpers.getUnsupportedCLAssetsAndRewards(_dHedgeVault, asset);
      }
      // Compound V3 Comet
      else if (assetType == 28) {
        unrolledAssets = _arraify(SwapperV2Helpers.getCompoundV3BaseAsset(asset));
      }
      // EasySwapperV2UnrolledAssets
      else if (assetType == 30) {
        unrolledAssets = SwapperV2Helpers.getUnrolledAssets(asset, _dHedgeVault);
      }
      // Pancake CL NFT
      else if (assetType == 31) {
        unrolledAssets = SwapperV2Helpers.getPancakeCLPositionAssets(_dHedgeVault, asset);
      }
      // Fluid Token
      else if (assetType == 34) {
        unrolledAssets = _arraify(SwapperV2Helpers.getFluidTokenUnderlying(asset));
      }
      // Pendle Principal Token
      else if (assetType == 37) {
        unrolledAssets = _arraify(SwapperV2Helpers.unrollPendlePT(_dHedgeVault, asset));
      }
      // Synthetix Perpetuals V2 - settled in sUSD
      else if (assetType == 102) {
        unrolledAssets = _arraify(SwapperV2Helpers.synthetixPerpsV2Helper(asset, poolFactory));
      } else {
        revert("assetType not handled");
      }

      for (uint256 j; j < unrolledAssets.length; ++j) {
        basicAssets[hits] = unrolledAssets[j];
        hits++;
      }
    }

    uint256 reduceLength = basicAssets.length.sub(hits);
    assembly {
      mstore(basicAssets, sub(mload(basicAssets), reduceLength))
    }

    for (uint256 i; i < basicAssets.length; ++i) {
      address basicAsset = basicAssets[i];
      if (basicAsset != address(0) && IERC20(basicAsset).balanceOf(address(this)) > 0) {
        srcAssets.add(basicAsset);
      }
    }
  }

  /// @notice Unrolls dHEDGE vaults inside dHEDGE vaults or returns the asset
  /// @dev Because dHEDGE vaults as assets are type 0 we need to check all type 0 to see if it is a vault
  /// @param _asset The address of the asset
  /// @return unrolledAssets Returns nothing when a dHEDGE vault, returns basic asset address otherwise
  function _detectDhedgeVault(address _asset) internal returns (address[] memory unrolledAssets) {
    if (IEasySwapperV2(creator).isdHedgeVault(_asset)) {
      uint256 balance = IPoolLogic(_asset).balanceOf(address(this));
      if (balance > 0) {
        // Here we sacrifice slippage protection mechanism.
        // This is equal to calling .withdrawSafe(balance, new IPoolLogic.ComplexAsset[](IHasSupportedAsset(IPoolLogic(_asset).poolManagerLogic()).getSupportedAssets().length))
        IPoolLogic(_asset).withdraw(balance);
        _unrollAssets(_asset);
      }
    } else {
      unrolledAssets = _arraify(_asset);
    }
  }

  /// @dev Helper function to convert address to address[]
  /// @param _address The address to convert
  /// @return arr Returns the address as an array
  function _arraify(address _address) internal pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = _address;
  }

  function _recoverAllAssets(address _to) internal {
    uint256 setLength = srcAssets.length();
    address srcAsset;
    uint256 balance;
    for (uint256 i; i < setLength; ) {
      srcAsset = srcAssets.at(i);
      balance = IERC20(srcAsset).balanceOf(address(this));
      srcAssets.remove(srcAsset);
      setLength--;
      IERC20(srcAsset).safeTransfer(_to, balance);
    }
  }
}
