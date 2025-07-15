// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FlatcoinModuleKeys} from "../../../utils/flatMoney/libraries/FlatcoinModuleKeys.sol";
import {IFlatcoinVault} from "../../../interfaces/flatMoney/IFlatcoinVault.sol";
import {IPointsModule} from "../../../interfaces/flatMoney/IPointsModule.sol";
import {IStableModule} from "../../../interfaces/flatMoney/IStableModule.sol";
import {ERC20Guard} from "../ERC20Guard.sol";
import {FlatMoneyOrderHelperGuard} from "./FlatMoneyOrderHelperGuard.sol";

/// @notice AssetType - 21
/// @dev `removeAssetCheck` from inherited contract will also revert in case of pending order, because
/// @dev `getBalance` from derived contract overrides the one from ERC20Guard.
/// @dev This will prevent the scenario when deposit/withdraw order is announced and manager can disable corresponding asset.
contract FlatMoneyUNITAssetGuard is FlatMoneyOrderHelperGuard, ERC20Guard {
  using SafeMath for uint256;

  uint256 private constant DECIMAL_FACTOR = 1e18;

  /// @notice Returns the balance of the UNIT asset in the vault.
  /// @dev Logic is the same as for regular ERC20 tokens, but reverts in case there is a pending order.
  /// @dev Revert is required because once order is opened, value of the vault is transferred out,
  /// @dev but there is always a delay before order is executed and the value is received back.
  /// @dev During order execution deposits as well as withdrawals at lower tokenPrice are possible, thus revert is required.
  /// @param _pool Vault address
  /// @param _asset UNIT asset address
  /// @return balance Balance of the UNIT asset in the vault
  function getBalance(address _pool, address _asset) public view override returns (uint256 balance) {
    require(_hasNoBlockingOrder(_pool, _asset), "order in progress");

    balance = IERC20(_asset).balanceOf(_pool);
  }

  /// @notice Calculates the amount of the UNIT asset to be withdrawn from the vault AND the amount of points.
  /// @dev It will revert the whole flow if there is a pending order, because `getBalance` is called internally.
  /// @dev User's portion of points is transferred directly.
  /// @param _pool Vault address
  /// @param _asset UNIT asset address
  /// @param _portion Portion of the asset to be withdrawn
  /// @param _to Address to receive the UNIT asset
  /// @return withdrawAsset UNIT asset address
  /// @return withdrawBalance Amount of the UNIT asset to be withdrawn
  /// @return transactions Array of transactions to be executed. This is where points are transferred
  function withdrawProcessing(
    address _pool,
    address _asset,
    uint256 _portion,
    address _to
  )
    external
    view
    override
    returns (address withdrawAsset, uint256 withdrawBalance, MultiTransaction[] memory transactions)
  {
    withdrawAsset = _asset;
    uint256 totalAssetBalance = getBalance(_pool, _asset);
    withdrawBalance = totalAssetBalance.mul(_portion).div(DECIMAL_FACTOR);

    IFlatcoinVault vault = IStableModule(_asset).vault();
    address pointsModule = vault.moduleAddress(FlatcoinModuleKeys._POINTS_MODULE_KEY);
    uint256 totalPointsBalance = getBalance(_pool, pointsModule);
    uint256 pointsToUnlock = totalPointsBalance.mul(_portion).div(DECIMAL_FACTOR);

    if (pointsToUnlock != 0) {
      transactions = new MultiTransaction[](2);

      transactions[0].to = pointsModule;
      transactions[0].txData = abi.encodeWithSelector(IPointsModule.unlock.selector, pointsToUnlock);

      uint256 unlockTax = IPointsModule(pointsModule).getUnlockTax(_pool);
      uint256 pointsLeftToTransfer = pointsToUnlock.sub(pointsToUnlock.mul(unlockTax).div(DECIMAL_FACTOR));

      transactions[1].to = pointsModule;
      transactions[1].txData = abi.encodeWithSelector(IERC20.transfer.selector, _to, pointsLeftToTransfer);
    }

    return (withdrawAsset, withdrawBalance, transactions);
  }
}
