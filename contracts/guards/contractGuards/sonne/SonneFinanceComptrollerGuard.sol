// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../utils/TxDataUtils.sol";
import "../../../interfaces/guards/IGuard.sol";
import "../../../interfaces/sonne/CTokenInterfaces.sol";
import "../../../interfaces/IPoolManagerLogic.sol";
import "../../../interfaces/ITransactionTypes.sol";
import "../../../interfaces/IHasSupportedAsset.sol";

contract SonneFinanceComptrollerGuard is TxDataUtils, IGuard, ITransactionTypes {
  /// @notice Transaction guard for Sonne Finance.
  /// @dev It supports enterMarkets and exitMarket transactions.
  /// @dev `_to` is not required for this guard.
  /// @param _poolManagerLogic The pool manager logic address.
  /// @param _data The transaction data.
  /// @return _txType The transaction type.
  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes calldata _data
  ) external virtual override returns (uint16 _txType, bool _isPublic) {
    bytes4 method = getMethod(_data);
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    if (method == ComptrollerInterface.enterMarkets.selector) {
      address[] memory cTokens = abi.decode(getParams(_data), (address[]));

      _enterMarkets(poolLogic, _poolManagerLogic, cTokens);

      _txType = uint16(ITransactionTypes.TransactionType.SonneComptrollerEnterMarkets);
    } else if (method == ComptrollerInterface.exitMarket.selector) {
      // Nothing to check here. Just return the txType.
      // Note: One possible threat could have been that a pool manager can exit market
      // thus resulting in less account liquidity (collateral) for the borrowed tokens
      // And subsequently liquidate the pool borrow positions.
      // However the Sonne contract states that:
      //  "Sender must not have an outstanding borrow balance in the asset,
      //  or be providing necessary collateral for an outstanding borrow."
      // Thus this is not a threat.
      _txType = uint16(ITransactionTypes.TransactionType.SonneComptrollerExitMarket);

      emit SonneExitMarket(poolLogic, abi.decode(getParams(_data), (address)), block.timestamp);
    }

    return (_txType, false);
  }

  /// @dev This function isn't strictly required given that to enter a market, the pool must have
  ///      supplied or borrowed in a market (cToken) and the same checks that are done here are also done
  ///      in the SonneFinanceCTokenGuard.
  function _enterMarkets(address _poolLogic, address _poolManagerLogic, address[] memory _cTokens) internal {
    IHasSupportedAsset poolManagerLogicAssets = IHasSupportedAsset(_poolManagerLogic);

    for (uint16 i = 0; i < _cTokens.length; ++i) {
      address cToken = _cTokens[i];
      address underlyingAsset = CErc20Interface(cToken).underlying();

      require(poolManagerLogicAssets.isSupportedAsset(cToken), "Given cToken not supported");
      require(poolManagerLogicAssets.isSupportedAsset(underlyingAsset), "unsupported underlying asset");
    }

    emit SonneEnterMarkets(_poolLogic, _cTokens, block.timestamp);
  }
}
