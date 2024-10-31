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
// Copyright (c) 2023 dHEDGE DAO
//
// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";

import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";
import {IERC721VerifyingGuard} from "../../../interfaces/guards/IERC721VerifyingGuard.sol";
import {IAccountModule} from "../../../interfaces/synthetixV3/IAccountModule.sol";
import {ICollateralModule} from "../../../interfaces/synthetixV3/ICollateralModule.sol";
import {ICollateralConfigurationModule} from "../../../interfaces/synthetixV3/ICollateralConfigurationModule.sol";
import {IIssueUSDModule} from "../../../interfaces/synthetixV3/IIssueUSDModule.sol";
import {IPoolConfigurationModule} from "../../../interfaces/synthetixV3/IPoolConfigurationModule.sol";
import {IRewardDistributor} from "../../../interfaces/synthetixV3/IRewardDistributor.sol";
import {IRewardsManagerModule} from "../../../interfaces/synthetixV3/IRewardsManagerModule.sol";
import {IVaultModule} from "../../../interfaces/synthetixV3/IVaultModule.sol";
import {IERC721Enumerable} from "../../../interfaces/IERC721Enumerable.sol";
import {IHasAssetInfo} from "../../../interfaces/IHasAssetInfo.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";
import {IPoolFactory} from "../../../interfaces/IPoolFactory.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {SynthetixV3Structs} from "../../../utils/synthetixV3/libraries/SynthetixV3Structs.sol";
import {WeeklyWindowsHelper} from "../../../utils/synthetixV3/libraries/WeeklyWindowsHelper.sol";
import {DhedgeNftTrackerStorage} from "../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import {PrecisionHelper} from "../../../utils/PrecisionHelper.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

contract SynthetixV3ContractGuard is TxDataUtils, ITxTrackingGuard, ITransactionTypes, IERC721VerifyingGuard {
  using Math for uint256;
  using SafeMath for uint256;
  using SafeCast for uint256;
  using WeeklyWindowsHelper for SynthetixV3Structs.Window;
  using WeeklyWindowsHelper for SynthetixV3Structs.WeeklyWindows;
  using PrecisionHelper for address;

  /// @dev Hardcoded limit of Synthetix V3 NFT account per pool
  uint256 public constant MAX_ACCOUNT_LIMIT = 1;

  DhedgeNftTrackerStorage public immutable nftTracker;

  mapping(address => SynthetixV3Structs.VaultSetting) public dHedgeVaultsWhitelist;

  SynthetixV3Structs.WeeklyWindows public windows;

  SynthetixV3Structs.WeeklyWithdrawalLimit public withdrawalLimit;

  bool public override isTxTrackingGuard = true;

  /// @dev For the sake of simplicity, setting configurational parameters during init instead of getting from Synthetix V3 Core contract
  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _whitelisteddHedgeVaults dHEDGE vaults that are allowed to use Synthetix V3, each with own parameters we are going to support
  /// @param _snxV3Core Synthetix V3 Core contract address
  /// @param _windows Periods when specific actions are allowed
  /// @param _withdrawalLimit Params for withdrawal limit
  constructor(
    address _nftTracker,
    SynthetixV3Structs.VaultSetting[] memory _whitelisteddHedgeVaults,
    address _snxV3Core,
    SynthetixV3Structs.WeeklyWindows memory _windows,
    SynthetixV3Structs.WeeklyWithdrawalLimit memory _withdrawalLimit
  ) {
    require(_nftTracker != address(0), "invalid nftTracker");
    require(_snxV3Core != address(0), "invalid snxV3Core");

    nftTracker = DhedgeNftTrackerStorage(_nftTracker);

    address poolFactory = DhedgeNftTrackerStorage(_nftTracker).poolFactory();
    for (uint256 i; i < _whitelisteddHedgeVaults.length; ++i) {
      SynthetixV3Structs.VaultSetting memory vaultSetting = _whitelisteddHedgeVaults[i];
      _validateVaultSetting(
        _snxV3Core,
        poolFactory,
        vaultSetting.poolLogic,
        vaultSetting.collateralAsset,
        vaultSetting.debtAsset,
        vaultSetting.snxLiquidityPoolId
      );
      dHedgeVaultsWhitelist[vaultSetting.poolLogic] = vaultSetting;
    }

    _windows.validateWindows();
    windows = _windows;

    withdrawalLimit = _withdrawalLimit;
  }

  /// @notice Returns Synthetix Account NFT ID associated with the pool stored in dHEDGE NFT Tracker contract
  /// @dev Assumes that in our inner tracking system the pool always holds only one Synthetix V3 NFT
  /// @param _poolLogic Pool address
  /// @param _to Synthetix V3 Core address
  /// @return tokenId Synthetix Account NFT ID
  function getAccountNftTokenId(address _poolLogic, address _to) public view returns (uint128 tokenId) {
    uint256[] memory tokenIds = nftTracker.getAllUintIds(
      _getNftType(IAccountModule(_to).getAccountTokenAddress()),
      _poolLogic
    );

    if (tokenIds.length == 1) {
      tokenId = tokenIds[0].toUint128();
    }
  }

  /// @notice Helper function to check if the vault is whitelisted
  /// @param _wanted PoolLogic address of interest
  /// @return isWhitelisted If the address is whitelisted
  function isVaultWhitelisted(address _wanted) public view returns (bool) {
    require(_wanted != address(0), "invalid pool logic");
    return dHedgeVaultsWhitelist[_wanted].poolLogic == _wanted;
  }

  /// @notice Helper function to calculate withdrawal limit
  /// @param _totalCollateralD18 Total collateral deposited, denominated with 18 decimals of precision
  /// @param _collateralType Collateral asset address
  /// @param _poolManagerLogic Pool manager logic address
  /// @return limitD18 Amount of withdrawal limit
  function calculateWithdrawalLimit(
    uint256 _totalCollateralD18,
    address _collateralType,
    IPoolManagerLogic _poolManagerLogic
  ) public view returns (uint256 limitD18) {
    // Pass the amount, denominated with asset's native decimal representation
    uint256 amountToPass = _totalCollateralD18.div(_collateralType.getPrecisionForConversion());
    // Calculate how much USD is percent limit
    uint256 percentUsdLimit = _poolManagerLogic.assetValue(
      _collateralType,
      amountToPass.mul(withdrawalLimit.percent).div(10 ** 18)
    );
    // Pick the biggest one
    uint256 usdLimit = percentUsdLimit.max(withdrawalLimit.usdValue);
    // Get the limit in collateral tokens, denominated with 18 decimals of precision
    limitD18 = usdLimit.mul(10 ** 18).div(IHasAssetInfo(_poolManagerLogic.factory()).getAssetPrice(_collateralType));
  }

  /// @notice Transaction guard for Synthetix V3 Core
  /// @dev Supports general flow for Synthetix V3 Protocol
  /// @dev Can be called only by PoolLogic during execTransaction
  /// @dev Includes account creation, collateral deposit/withdrawal, delegate collateral, mint/burn snxUSD
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _to Synthetix V3 Core address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) external override returns (uint16 txType, bool isPublic) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    require(isVaultWhitelisted(poolLogic), "dhedge vault not whitelisted");

    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    // Not allowing anything before enabling Synthetix V3 position asset (which is basically Synthetix V3 Core address)
    require(poolManagerLogicAssets.isSupportedAsset(_to), "enable synthetix v3 asset");

    SynthetixV3Structs.VaultSetting storage vaultSetting = dHedgeVaultsWhitelist[poolLogic];

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == bytes4(keccak256("createAccount()")) || method == bytes4(keccak256("createAccount(uint128)"))) {
      address snxAccountNft = IAccountModule(_to).getAccountTokenAddress();
      // Revert if pool already has associated Synthetix V3 NFT account
      require(nftTracker.getDataCount(_getNftType(snxAccountNft), poolLogic) == 0, "only one account allowed");

      txType = uint16(TransactionType.SynthetixV3CreateAccount);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == ICollateralModule.deposit.selector) {
      (uint128 accountId, address collateralType) = abi.decode(params, (uint128, address));

      // Collateral deposited into pool's Synthetix V3 account must be the one we support
      require(
        collateralType == vaultSetting.collateralAsset || collateralType == vaultSetting.debtAsset,
        "unsupported collateral type"
      );
      // Deposit must happen only into the account owned by the pool
      // We check not by ownership of the nft, but using our inner tracking system not to count airdropped NFTs
      require(getAccountNftTokenId(poolLogic, _to) == accountId, "account not owned by pool");

      txType = uint16(TransactionType.SynthetixV3DepositCollateral);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == ICollateralModule.withdraw.selector) {
      (, address collateralType) = abi.decode(params, (uint128, address));

      // Must match collateral we support
      require(
        collateralType == vaultSetting.collateralAsset || collateralType == vaultSetting.debtAsset,
        "unsupported collateral type"
      );
      // Upon withdrawing from its account, pool must have collateral asset enabled as it's going to receive it
      require(poolManagerLogicAssets.isSupportedAsset(collateralType), "collateral asset must be enabled");

      txType = uint16(TransactionType.SynthetixV3WithdrawCollateral);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IVaultModule.delegateCollateral.selector) {
      (txType, isPublic) = _verifyDelegateCollateral(params, poolLogic, _to, _poolManagerLogic, vaultSetting);
    } else if (method == IIssueUSDModule.mintUsd.selector) {
      (uint128 accountId, uint128 poolId, address collateralType) = abi.decode(params, (uint128, uint128, address));

      // Minting should happen only from the account owned by the pool
      require(getAccountNftTokenId(poolLogic, _to) == accountId, "account not owned by pool");
      // Must mint snxUSD against liquidity pool we support
      require(vaultSetting.snxLiquidityPoolId == poolId, "lp not allowed");
      // Must match collateral we support
      require(collateralType == vaultSetting.collateralAsset, "unsupported collateral type");
      // Only allowed during predefined so-called "delegation period"
      require(windows.delegationWindow.isWithinAllowedWindow(block.timestamp), "outside delegation window");

      txType = uint16(TransactionType.SynthetixV3MintUSD);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IIssueUSDModule.burnUsd.selector) {
      (uint128 accountId, uint128 poolId, address collateralType) = abi.decode(params, (uint128, uint128, address));

      // Burning should happen only from the account owned by the pool
      require(getAccountNftTokenId(poolLogic, _to) == accountId, "account not owned by pool");
      // Must burn snxUSD against liquidity pool we support
      require(vaultSetting.snxLiquidityPoolId == poolId, "lp not allowed");
      // Must match collateral we support
      require(collateralType == vaultSetting.collateralAsset, "unsupported collateral type");
      // Not allowed outside of delegation and undelegation windows. To undelegate, positive debt must be burned first
      require(
        windows.delegationWindow.isWithinAllowedWindow(block.timestamp) ||
          windows.undelegationWindow.isWithinAllowedWindow(block.timestamp),
        "outside allowed windows"
      );

      txType = uint16(TransactionType.SynthetixV3BurnUSD);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IRewardsManagerModule.claimRewards.selector) {
      (uint128 accountId, uint128 poolId, address collateralType, address distributor) = abi.decode(
        params,
        (uint128, uint128, address, address)
      );

      require(getAccountNftTokenId(poolLogic, _to) == accountId, "account not owned by pool");

      require(vaultSetting.snxLiquidityPoolId == poolId, "lp not allowed");

      require(
        collateralType == vaultSetting.collateralAsset || collateralType == vaultSetting.debtAsset,
        "unsupported collateral type"
      );
      address rewardToken = IRewardDistributor(distributor).token();
      if (IHasAssetInfo(IPoolManagerLogic(_poolManagerLogic).factory()).isValidAsset(rewardToken)) {
        require(poolManagerLogicAssets.isSupportedAsset(rewardToken), "unsupported reward asset");
      }

      txType = uint16(TransactionType.SynthetixV3ClaimReward);

      emit SynthetixV3Event(poolLogic, txType);
    }

    return (txType, isPublic);
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

  /// @dev Required because we need to track minted Synthetix V3 NFT Account IDs
  /// @dev Can be called only by PoolLogic during execTransaction
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _to Synthetix V3 Core address
  /// @param _data Transaction data
  function afterTxGuard(address _poolManagerLogic, address _to, bytes memory _data) external override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(msg.sender == poolLogic, "not pool logic");

    require(isVaultWhitelisted(poolLogic), "dhedge vault not whitelisted");

    bytes4 method = getMethod(_data);

    // Runs only after Synthetix V3 Core contract calls related to account creation
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
  /// @param _to Synthetix V3 Core address
  function _afterTxGuardHelper(uint256 _id, address _poolLogic, address _to) internal {
    bytes32 nftType = _getNftType(IAccountModule(_to).getAccountTokenAddress());
    // Storing Synthetix V3 NFT Account ID associated with the pool in dHEDGE NFT Tracker contract by NFT type
    // It ensures that max positions limit is not breached
    nftTracker.addUintId(_to, nftType, _poolLogic, _id, MAX_ACCOUNT_LIMIT);
  }

  /// @notice Helper function to build NFT type
  /// @dev NFT type is a keccak256 hash of Synthetix V3 Account NFT address
  /// @param _accountNftToken Synthetix V3 Account NFT address
  /// @return nftType NFT type
  function _getNftType(address _accountNftToken) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_accountNftToken));
  }

  /// @notice Handles delegation and undelegation
  /// @dev Limits execution according to predefined time periods
  /// @param _params Transaction parameters
  /// @param _poolLogic Pool logic address
  /// @param _to Synthetix V3 Core address
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _vaultSetting Vault setting
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function _verifyDelegateCollateral(
    bytes memory _params,
    address _poolLogic,
    address _to,
    address _poolManagerLogic,
    SynthetixV3Structs.VaultSetting storage _vaultSetting
  ) internal returns (uint16 txType, bool isPublic) {
    (uint128 accountId, uint128 poolId, address collateralType, uint256 newCollateralAmountD18, uint256 leverage) = abi
      .decode(_params, (uint128, uint128, address, uint256, uint256));
    // Delegate should happen only from the account owned by the pool
    require(getAccountNftTokenId(_poolLogic, _to) == accountId, "account not owned by pool");
    // Make sure leverage is 1, as it can change in the future
    require(leverage == 10 ** 18, "unsupported leverage");
    // Must delegate collateral only to allowed liquidity pool
    require(_vaultSetting.snxLiquidityPoolId == poolId, "lp not allowed");
    // Must match collateral we support
    require(collateralType == _vaultSetting.collateralAsset, "unsupported collateral type");

    // During delegation window manager is free to do anything
    if (windows.delegationWindow.isWithinAllowedWindow(block.timestamp)) {
      txType = uint16(TransactionType.SynthetixV3DelegateCollateral);

      emit SynthetixV3Event(_poolLogic, txType);
      // During undelegation window anyone is allowed to undelegate only
    } else if (windows.undelegationWindow.isWithinAllowedWindow(block.timestamp)) {
      // Total deposited = total available + total assigned
      (uint256 totalDepositedD18, uint256 totalAssignedD18, ) = ICollateralModule(_to).getAccountCollateral(
        accountId,
        collateralType
      );
      // Forbidden to delegate more during undelegation window
      require(newCollateralAmountD18 < totalAssignedD18, "only undelegation allowed");

      uint256 totalAvailableD18 = totalDepositedD18.sub(totalAssignedD18);
      uint256 amountToUndelegateD18 = totalAssignedD18.sub(newCollateralAmountD18);
      // Can proceed only if total available for withdrawal + amount to be undelegated is less than withdrawal limit
      require(
        totalAvailableD18.add(amountToUndelegateD18) <=
          calculateWithdrawalLimit(totalDepositedD18, collateralType, IPoolManagerLogic(_poolManagerLogic)),
        "undelegation limit breached"
      );

      txType = uint16(TransactionType.SynthetixV3UndelegateCollateral);
      isPublic = true;

      emit SynthetixV3Event(_poolLogic, txType);
      // Outside of delegation and undelegation windows nothing is allowed
    } else {
      revert("outside allowed windows");
    }
  }

  /// @notice Helper function to validate vault setting
  /// @dev Can call getPoolCollateralConfiguration for additional checks
  /// @param _snxV3Core Synthetix V3 Core contract address
  /// @param _poolFactory dHEDGE PoolFactory address
  /// @param _poolLogic PoolLogic address
  /// @param _collateralAsset Collateral asset address
  /// @param _debtAsset Debt asset address
  function _validateVaultSetting(
    address _snxV3Core,
    address _poolFactory,
    address _poolLogic,
    address _collateralAsset,
    address _debtAsset,
    uint128 _snxLiquidityPoolId
  ) internal view {
    require(_poolLogic != address(0) && IPoolFactory(_poolFactory).isPool(_poolLogic), "invalid pool logic");
    require(
      _collateralAsset != address(0) &&
        IHasAssetInfo(_poolFactory).isValidAsset(_collateralAsset) &&
        ICollateralConfigurationModule(_snxV3Core).getCollateralConfiguration(_collateralAsset).depositingEnabled,
      "invalid collateral asset"
    );
    require(_debtAsset != address(0) && IHasAssetInfo(_poolFactory).isValidAsset(_debtAsset), "invalid debt asset");

    // Currently is set to 1
    uint128 poolId = IPoolConfigurationModule(_snxV3Core).getPreferredPool();
    // Currently this list is empty, so to make things work we need to check both preferred pool and approved pools
    uint256[] memory poolIds = IPoolConfigurationModule(_snxV3Core).getApprovedPools();
    // First check preferred pool
    bool isPoolValid = _snxLiquidityPoolId == poolId;
    // if not found in preferred pool, check approved pools
    if (!isPoolValid) {
      for (uint256 i; i < poolIds.length; ++i) {
        if (_snxLiquidityPoolId == poolIds[i]) {
          isPoolValid = true;
          break;
        }
      }
    }
    require(isPoolValid, "invalid snx liquidity pool id");
  }
}
