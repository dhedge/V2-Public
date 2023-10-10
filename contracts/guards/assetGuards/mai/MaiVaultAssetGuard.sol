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
// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./MaiVaultWithdrawProcessing.sol";

/// @title MaiVault Asset Guard
/// @dev Asset type = 17
/// @dev A wallet/user can only have one position per market
contract MaiVaultAssetGuard is MaiVaultWithdrawProcessing {
  using SafeMath for uint256;

  constructor(address _usdc, address _aaveLendingPoolV3)
    MaiVaultWithdrawProcessing(_usdc, _aaveLendingPoolV3) // solhint-disable-next-line no-empty-blocks
  {}

  /// @notice Returns the USD value of all the pools vaults
  /// @param pool address of the pool
  /// @param asset address of the maiVault
  /// @return balance The asset balance of given pool
  function getBalance(address pool, address asset) public view override returns (uint256 balance) {
    IPoolManagerLogic poolManagerLogic = IPoolManagerLogic(IPoolLogic(pool).poolManagerLogic());
    (uint256 collateralAmount, uint256 debtAmountInMai) = _getTotalDebtAndCollateral(pool, asset);
    IStableQiVault maiVault = IStableQiVault(asset);
    uint256 fee = maiVault.calculateFee(maiVault.closingFee(), debtAmountInMai, maiVault.promoter(PROMOTER_ID));
    uint256 collateralValue = poolManagerLogic.assetValue(maiVault.collateral(), collateralAmount);
    uint256 debtValue = poolManagerLogic.assetValue(maiVault.mai(), debtAmountInMai);

    if (collateralValue > debtValue.add(fee)) {
      return collateralValue.sub(debtValue).sub(fee);
    } else {
      return 0;
    }
  }

  /// @notice Returns decimal of USD value
  /// @dev Returns decimal 18
  function getDecimals(address) external pure override returns (uint256 decimals) {
    decimals = 18;
  }

  /// @notice Returns total collateral and debt amounts for all positions for this vault
  /// @param pool address of the pool
  /// @param asset address of the maiVault
  /// @return collateralAmount The amount of collateral in all positions
  /// @return debtAmountInMai The amount of mai owing across all positions
  function _getTotalDebtAndCollateral(address pool, address asset)
    private
    view
    returns (uint256 collateralAmount, uint256 debtAmountInMai)
  {
    address maiVaultContactGuard = IHasGuardInfo(IPoolLogic(pool).factory()).getContractGuard(asset);
    IStableQiVault maiVault = IStableQiVault(asset);

    uint256[] memory vaultIds = MaiVaultContractGuard(maiVaultContactGuard).getNftIds(pool, asset);

    // (vaultCollateral * collateralPrice) - (vaultDebt * maiPrice)
    for (uint256 i = 0; i < vaultIds.length; i++) {
      uint256 vaultId = vaultIds[i];
      collateralAmount = collateralAmount.add(maiVault.vaultCollateral(vaultId));
      debtAmountInMai = debtAmountInMai.add(maiVault.vaultDebt(vaultId));
    }
  }
}
