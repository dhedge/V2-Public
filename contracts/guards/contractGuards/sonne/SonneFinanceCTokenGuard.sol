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
      uint256 amount = abi.decode(getParams(_data), (uint256));

      _txType = _mint(poolLogic, _poolManagerLogic, _to, amount);
    } else if (method == CErc20Interface.redeem.selector || method == CErc20Interface.redeemUnderlying.selector) {
      // `redeem` and `redeemUnderlying` differ in the sense that `redeem` takes the amount of CToken to redeem (converts the specified amount of CToken)
      // while `redeemUnderlying` takes the amount of underlying asset to redeem (gets you the specified amount of underlying asset).
      uint256 amount = abi.decode(getParams(_data), (uint256));

      _txType = _redeem(method, poolLogic, _poolManagerLogic, _to, amount);
    } else if (method == CErc20Interface.borrow.selector) {
      uint256 amount = abi.decode(getParams(_data), (uint256));

      _txType = _borrow(poolLogic, _poolManagerLogic, _to, amount);
    } else if (method == CErc20Interface.repayBorrow.selector) {
      uint256 amount = abi.decode(getParams(_data), (uint256));

      _txType = _repay(poolLogic, _poolManagerLogic, _to, amount);
    }

    return (_txType, false);
  }

  function _mint(
    address _poolLogic,
    address _poolManagerLogic,
    address _to,
    uint256 _amount
  ) internal returns (uint16 _txType) {
    address underlyingAsset = CErc20Interface(_to).underlying();

    _unsupportedAssetChecks(_poolManagerLogic, _to, underlyingAsset);

    emit SonneMintEvent(_poolLogic, underlyingAsset, _to, _amount, block.timestamp);

    return uint16(ITransactionTypes.TransactionType.SonneMint);
  }

  function _redeem(
    bytes4 _method,
    address _poolLogic,
    address _poolManagerLogic,
    address _to,
    uint256 _amount
  ) internal returns (uint16 _txType) {
    address underlyingAsset = CErc20Interface(_to).underlying();
    _unsupportedAssetChecks(_poolManagerLogic, _to, underlyingAsset);

    if (_method == CErc20Interface.redeem.selector) {
      _txType = uint16(ITransactionTypes.TransactionType.SonneRedeem);
      emit SonneRedeemEvent(_poolLogic, underlyingAsset, _to, _amount, block.timestamp);
    } else {
      _txType = uint16(ITransactionTypes.TransactionType.SonneRedeemUnderlying);
      emit SonneRedeemUnderlyingEvent(_poolLogic, underlyingAsset, _to, _amount, block.timestamp);
    }
  }

  function _borrow(
    address _poolLogic,
    address _poolManagerLogic,
    address _to,
    uint256 _amount
  ) internal returns (uint16 _txType) {
    address underlyingAsset = CErc20Interface(_to).underlying();

    _unsupportedAssetChecks(_poolManagerLogic, _to, underlyingAsset);

    emit SonneBorrowEvent(_poolLogic, underlyingAsset, _to, _amount, block.timestamp);

    return uint16(ITransactionTypes.TransactionType.SonneBorrow);
  }

  function _repay(
    address _poolLogic,
    address _poolManagerLogic,
    address _to,
    uint256 _amount
  ) internal returns (uint16 _txType) {
    address underlyingAsset = CErc20Interface(_to).underlying();
    _unsupportedAssetChecks(_poolManagerLogic, _to, underlyingAsset);

    emit SonneRepayEvent(_poolLogic, underlyingAsset, _to, _amount, block.timestamp);

    return uint16(ITransactionTypes.TransactionType.SonneRepay);
  }

  function _unsupportedAssetChecks(address _poolManagerLogic, address _to, address _underlyingAsset) internal view {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    require(poolManagerLogicAssets.isSupportedAsset(_to), "Given cToken not supported");
    require(poolManagerLogicAssets.isSupportedAsset(_underlyingAsset), "unsupported underlying asset");
  }
}
