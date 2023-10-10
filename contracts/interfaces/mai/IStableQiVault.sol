// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Not OS AFAIK - Taken from https://optimistic.etherscan.io/address/0xbf1aea8670d2528e08334083616dd9c5f3b087ae#code
interface IStableQiVault is IERC721 {
  function mai() external view returns (address);

  function collateral() external view returns (address);

  function vaultCount() external view returns (uint256);

  function getTokenPriceSource() external view returns (uint256);

  function getEthPriceSource() external view returns (uint256);

  function closingFee() external view returns (uint256);

  function vaultCollateral(uint256 vaultID) external view returns (uint256);

  function vaultDebt(uint256 vaultId) external view returns (uint256);

  function createVault() external returns (uint256);

  function destroyVault(uint256 vaultID) external;

  function depositCollateral(uint256 vaultID, uint256 amount) external;

  function withdrawCollateral(uint256 vaultID, uint256 amount) external;

  function borrowToken(
    uint256 vaultID,
    uint256 amount,
    uint256 _front
  ) external;

  function payBackToken(
    uint256 vaultID,
    uint256 amount,
    uint256 _front // frontend tracking id
  ) external;

  function paybackTokenAll(
    uint256 vaultID,
    uint256 deadline,
    uint256 _front // frontend tracking id
  ) external;

  function checkCollateralPercentage(uint256 vaultID) external view;

  // this returns the fee for this promoter - promoFee below
  function promoter(uint256 _front) external view returns (uint256);

  function calculateFee(
    uint256 fee,
    uint256 amount,
    uint256 promoFee
  ) external view returns (uint256);

  function updateVaultDebt(uint256 vaultID) external returns (uint256);
}
