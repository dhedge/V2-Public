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

import "@openzeppelin/contracts/utils/SafeCast.sol";

import "../../../interfaces/guards/ITxTrackingGuard.sol";
import "../../../interfaces/guards/IERC721VerifyingGuard.sol";
import "../../../interfaces/synthetixV3/IAccountModule.sol";
import "../../../interfaces/synthetixV3/ICollateralModule.sol";
import "../../../interfaces/synthetixV3/IIssueUSDModule.sol";
import "../../../interfaces/synthetixV3/IMulticallModule.sol";
import "../../../interfaces/synthetixV3/IVaultModule.sol";
import "../../../interfaces/IERC721Enumerable.sol";
import "../../../interfaces/IHasAssetInfo.sol";
import "../../../interfaces/IHasSupportedAsset.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/ITransactionTypes.sol";
import "../../../utils/tracker/DhedgeNftTrackerStorage.sol";
import "../../../utils/TxDataUtils.sol";

contract SynthetixV3ContractGuard is TxDataUtils, ITxTrackingGuard, ITransactionTypes, IERC721VerifyingGuard {
  using SafeCast for uint256;

  event SynthetixV3Event(address poolLogic, uint256 txType);

  // Hardcoded limit of Synthetix V3 NFT account per pool
  uint256 public constant MAX_ACCOUNT_LIMIT = 1;

  // Using Synthetix V3 Core contract can call getCollateralConfigurations
  address public immutable collateral;
  // Using Synthetix V3 Core contract can call getPreferredPool, getApprovedPools
  uint128 public immutable allowedLiquidityPoolId;
  address public immutable debtAsset;
  DhedgeNftTrackerStorage public immutable nftTracker;

  /**
   * @dev We don't expect whitelists to grow significantly, thus arrays instead of mappings are used.
   * @dev For smaller lists, using an array is generally sufficient and more straightforward.
   * @dev Arrays are iterable, while mappings are not.
   */
  address[] public dHedgeVaultsWhitelist;

  bool public override isTxTrackingGuard = true;

  /// @dev For the sake of simplicity, setting configurational parameters during init instead of getting from Synthetix V3 Core contract
  /// @param _collateral Synthetix V3 collateral address we are going to support
  /// @param _allowedLiquidityPoolId Synthetix V3 liquidity pool ID we are going to support
  /// @param _debtAsset Synthetix V3 snxUSD address
  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _whitelisteddHedgeVaults dHEDGE vaults that are allowed to use Synthetix V3
  constructor(
    address _collateral,
    uint128 _allowedLiquidityPoolId,
    address _debtAsset,
    address _nftTracker,
    address[] memory _whitelisteddHedgeVaults
  ) {
    require(_collateral != address(0) && _debtAsset != address(0) && _nftTracker != address(0), "zero address found");
    nftTracker = DhedgeNftTrackerStorage(_nftTracker);
    IHasAssetInfo factory = IHasAssetInfo(DhedgeNftTrackerStorage(_nftTracker).poolFactory());
    require(factory.isValidAsset(_collateral) && factory.isValidAsset(_debtAsset), "unsupported assets");
    collateral = _collateral;
    allowedLiquidityPoolId = _allowedLiquidityPoolId;
    debtAsset = _debtAsset;
    dHedgeVaultsWhitelist = _whitelisteddHedgeVaults;
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

  /// @notice Transaction guard for Synthetix V3
  /// @dev Supports general flow for Synthetix V3 Protocol
  /// @dev Includes account creation, collateral deposit/withdrawal, delegate collateral, mint/burn snxUSD
  /// @dev TODO: Claiming rewards?
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _to Synthetix V3 Core address
  /// @param _data Transaction data
  /// @return txType Transaction type
  /// @return isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) public override returns (uint16 txType, bool) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(_isWhitelisted(dHedgeVaultsWhitelist, poolLogic), "dhedge vault not whitelisted");

    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    // Not allowing anything before enabling Synthetix V3 position asset (which is basically Synthetix V3 Core address)
    require(poolManagerLogicAssets.isSupportedAsset(_to), "enable synthetix v3 asset");

    bytes4 method = getMethod(_data);
    bytes memory params = getParams(_data);

    if (method == bytes4(keccak256("createAccount()")) || method == bytes4(keccak256("createAccount(uint128)"))) {
      address synthetixAccountNft = IAccountModule(_to).getAccountTokenAddress();
      // Revert if pool already has associated Synthetix V3 NFT account
      require(IERC721Enumerable(synthetixAccountNft).balanceOf(poolLogic) == 0, "only one account allowed");

      txType = uint16(TransactionType.SynthetixV3CreateAccount);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == ICollateralModule.deposit.selector) {
      (uint128 accountId, address collateralType) = abi.decode(params, (uint128, address));

      // Collateral deposited into pool's Synthetix V3 account must be the one we support
      require(collateralType == collateral || collateralType == debtAsset, "unsupported collateral type");
      // Deposit must happen only into the account owned by the pool
      // We check not by ownership of the nft, but using our inner tracking system not to count airdropped NFTs
      require(getAccountNftTokenId(poolLogic, _to) == accountId, "account not owned by pool");

      txType = uint16(TransactionType.SynthetixV3DepositCollateral);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == ICollateralModule.withdraw.selector) {
      (, address collateralType) = abi.decode(params, (uint128, address));

      // Must match collateral we support
      require(collateralType == collateral || collateralType == debtAsset, "unsupported collateral type");
      // Upon withdrawing from its account, pool must have collateral asset enabled as it's going to receive it
      require(poolManagerLogicAssets.isSupportedAsset(collateralType), "collateral asset must be enabled");

      txType = uint16(TransactionType.SynthetixV3WithdrawCollateral);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IVaultModule.delegateCollateral.selector) {
      (uint128 accountId, uint128 poolId, address collateralType, , uint256 leverage) = abi.decode(
        params,
        (uint128, uint128, address, uint256, uint256)
      );

      // Delegate should happen only from the account owned by the pool
      require(getAccountNftTokenId(poolLogic, _to) == accountId, "account not owned by pool");
      // Make sure leverage is 1, as it can change in the future
      require(leverage == 10**18, "unsupported leverage");
      // Must delegate collateral only to allowed liquidity pool
      require(allowedLiquidityPoolId == poolId, "lp not allowed");
      // Must match collateral we support
      require(collateralType == collateral, "unsupported collateral type");

      txType = uint16(TransactionType.SynthetixV3DelegateCollateral);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IIssueUSDModule.mintUsd.selector) {
      (uint128 accountId, uint128 poolId, address collateralType) = abi.decode(params, (uint128, uint128, address));

      // Minting should happen only from the account owned by the pool
      require(getAccountNftTokenId(poolLogic, _to) == accountId, "account not owned by pool");
      // Must mint snxUSD against liquidity pool we support
      require(allowedLiquidityPoolId == poolId, "lp not allowed");
      // Must match collateral we support
      require(collateralType == collateral, "unsupported collateral type");

      txType = uint16(TransactionType.SynthetixV3MintUSD);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IIssueUSDModule.burnUsd.selector) {
      (uint128 accountId, uint128 poolId, address collateralType) = abi.decode(params, (uint128, uint128, address));

      // Burning should happen only from the account owned by the pool
      require(getAccountNftTokenId(poolLogic, _to) == accountId, "account not owned by pool");
      // Must burn snxUSD against liquidity pool we support
      require(allowedLiquidityPoolId == poolId, "lp not allowed");
      // Must match collateral we support
      require(collateralType == collateral, "unsupported collateral type");

      txType = uint16(TransactionType.SynthetixV3BurnUSD);

      emit SynthetixV3Event(poolLogic, txType);
    } else if (method == IMulticallModule.multicall.selector) {
      // Multicall support has some limitations due to how ITxTrackingGuard works, see tests for details
      bytes[] memory payloads = abi.decode(params, (bytes[]));
      uint256 payloadsLength = payloads.length;

      for (uint256 i; i < payloadsLength; ++i) {
        (txType, ) = txGuard(_poolManagerLogic, _to, payloads[i]);

        require(txType > 0, "invalid transaction");
      }

      txType = uint16(TransactionType.SynthetixV3Multicall);

      emit SynthetixV3Event(poolLogic, txType);
    }

    return (txType, false);
  }

  function verifyERC721(
    address,
    address from,
    uint256,
    bytes calldata
  ) external pure override returns (bool verified) {
    // Most likely it's an overkill. Checks that the NFT is minted, not transferred
    require(from == address(0), "can't accept foreign NFTs");

    verified = true;
  }

  /// @notice Helper function to build NFT type
  /// @dev NFT type is a keccak256 hash of Synthetix V3 Account NFT address
  /// @param _accountNftToken Synthetix V3 Account NFT address
  /// @return nftType NFT type
  function _getNftType(address _accountNftToken) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_accountNftToken));
  }

  /// @dev Required because we need to track minted Synthetix V3 NFT Account IDs
  /// @param _poolManagerLogic Pool manager logic address
  /// @param _to Synthetix V3 Core address
  /// @param _data Transaction data
  function afterTxGuard(
    address _poolManagerLogic,
    address _to,
    bytes memory _data
  ) public override {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    // Can be called only by pool logic during execTransaction
    require(msg.sender == poolLogic, "not pool logic");

    require(_isWhitelisted(dHedgeVaultsWhitelist, poolLogic), "dhedge vault not whitelisted");

    bytes4 method = getMethod(_data);

    // Runs only after Synthetix V3 Core contract calls related to account creation
    // Handles both createAccount() and createAccount(uint128) methods
    if (method == bytes4(keccak256("createAccount(uint128)"))) {
      // Id was passed in advance, see https://docs.synthetix.io/v/v3/for-developers/smart-contracts#createaccount
      uint128 id = abi.decode(getParams(_data), (uint128));
      _afterTxGuardHelper(id, poolLogic, _to);
    } else if (method == bytes4(keccak256("createAccount()"))) {
      address synthetixAccountNft = IAccountModule(_to).getAccountTokenAddress();
      // Id was assigned by Synthetix V3 System and we're getting it from the Synthetix V3 Account NFT
      // Assumes that there were no other minted NFTs before, as we are guarding it in corresponding condition of txGuard
      uint256 id = IERC721Enumerable(synthetixAccountNft).tokenOfOwnerByIndex(poolLogic, 0);
      _afterTxGuardHelper(id, poolLogic, _to);
    } else if (method == IMulticallModule.multicall.selector) {
      bytes[] memory payloads = abi.decode(getParams(_data), (bytes[]));

      for (uint256 i; i < payloads.length; ++i) {
        afterTxGuard(_poolManagerLogic, _to, payloads[i]);
      }
    }
  }

  /// @notice Helper function to track minted Synthetix V3 NFT Account IDs
  /// @dev We are tracking minted Synthetix V3 NFT Account IDs in dHEDGE NFT Tracker contract
  /// @param _id Synthetix V3 NFT Account ID associated with the pool
  /// @param _poolLogic Pool logic address
  /// @param _to Synthetix V3 Core address
  function _afterTxGuardHelper(
    uint256 _id,
    address _poolLogic,
    address _to
  ) internal {
    address synthetixAccountNft = IAccountModule(_to).getAccountTokenAddress();
    // Before storing into dHEDGE NFT Tracker contract, we need to ensure that the pool has only one Synthetix V3 NFT Account
    assert(IERC721(synthetixAccountNft).balanceOf(_poolLogic) == MAX_ACCOUNT_LIMIT);
    bytes32 nftType = _getNftType(synthetixAccountNft);
    // Storing Synthetix V3 NFT Account ID associated with the pool in dHEDGE NFT Tracker contract by NFT type
    nftTracker.addUintId(_to, nftType, _poolLogic, _id, MAX_ACCOUNT_LIMIT);
  }

  /// @notice Helper function to loop through the list and check if the item is whitelisted
  /// @dev Can be overloaded once needed
  /// @param _whitelist Whitelist of addresses
  /// @param _wanted Address of interest
  /// @return isWhitelisted If the address is whitelisted
  function _isWhitelisted(address[] storage _whitelist, address _wanted) internal view returns (bool) {
    uint256 whitelistLength = _whitelist.length;
    for (uint256 i; i < whitelistLength; ++i) {
      if (_whitelist[i] == _wanted) {
        return true;
      }
    }
    return false;
  }
}
