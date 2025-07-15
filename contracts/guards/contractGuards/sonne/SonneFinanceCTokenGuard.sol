// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/sonne/CTokenInterfaces.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/ITransactionTypes.sol";
import "../../../interfaces/IHasSupportedAsset.sol";

contract SonneFinanceCTokenGuard is TxDataUtils, IGuard, ITransactionTypes {
  /// @notice Mapping containing whitelisted vaults (PoolLogic) which can call Sonne Finance methods without strict checks.
  mapping(address => bool) public dHedgeVaultsWhitelist;

  constructor(address[] memory _whitelistedVaults) {
    for (uint256 i = 0; i < _whitelistedVaults.length; i++) {
      dHedgeVaultsWhitelist[_whitelistedVaults[i]] = true;
    }
  }

  /// @notice Transaction guard for Sonne Finance.
  /// @dev This is applicable to Compound Protocol V2 forks
  /// @param _poolManagerLogic The pool manager logic address.
  /// @param _to The CToken address.
  /// @param _data The transaction data payload.
  /// @return _txType The transaction type of a given transaction data.
  /// @return _isPublic If the transaction is public or private
  function txGuard(
    address _poolManagerLogic,
    address _to,
    bytes calldata _data
  ) external virtual override returns (uint16 _txType, bool _isPublic) {
    bytes4 method = getMethod(_data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    require(dHedgeVaultsWhitelist[poolLogic], "only whitelisted vaults");

    if (method == CErc20Interface.mint.selector) {
      _txType = _mint(_poolManagerLogic, _to);
    } else if (method == CErc20Interface.redeem.selector || method == CErc20Interface.redeemUnderlying.selector) {
      // `redeem` and `redeemUnderlying` differ in the sense that `redeem` takes the amount of CToken to redeem (converts the specified amount of CToken)
      // while `redeemUnderlying` takes the amount of underlying asset to redeem (gets you the specified amount of underlying asset).
      _txType = _redeem(method, _poolManagerLogic, _to);
    } else if (method == CErc20Interface.borrow.selector) {
      _txType = _borrow(_poolManagerLogic, _to);
    } else if (method == CErc20Interface.repayBorrow.selector) {
      _txType = _repay(_poolManagerLogic, _to);
    }

    return (_txType, false);
  }

  function _mint(address _poolManagerLogic, address _to) internal view returns (uint16 _txType) {
    address underlyingAsset = CErc20Interface(_to).underlying();

    _unsupportedAssetChecks(_poolManagerLogic, _to, underlyingAsset);

    return uint16(ITransactionTypes.TransactionType.SonneMint);
  }

  function _redeem(bytes4 _method, address _poolManagerLogic, address _to) internal view returns (uint16 _txType) {
    address underlyingAsset = CErc20Interface(_to).underlying();
    _unsupportedAssetChecks(_poolManagerLogic, _to, underlyingAsset);

    if (_method == CErc20Interface.redeem.selector) {
      _txType = uint16(ITransactionTypes.TransactionType.SonneRedeem);
    } else {
      _txType = uint16(ITransactionTypes.TransactionType.SonneRedeemUnderlying);
    }
  }

  function _borrow(address _poolManagerLogic, address _to) internal view returns (uint16 _txType) {
    address underlyingAsset = CErc20Interface(_to).underlying();

    _unsupportedAssetChecks(_poolManagerLogic, _to, underlyingAsset);

    return uint16(ITransactionTypes.TransactionType.SonneBorrow);
  }

  function _repay(address _poolManagerLogic, address _to) internal view returns (uint16 _txType) {
    address underlyingAsset = CErc20Interface(_to).underlying();
    _unsupportedAssetChecks(_poolManagerLogic, _to, underlyingAsset);

    return uint16(ITransactionTypes.TransactionType.SonneRepay);
  }

  function _unsupportedAssetChecks(address _poolManagerLogic, address _to, address _underlyingAsset) internal view {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    require(poolManagerLogicAssets.isSupportedAsset(_to), "Given cToken not supported");
    require(poolManagerLogicAssets.isSupportedAsset(_underlyingAsset), "unsupported underlying asset");
  }
}
