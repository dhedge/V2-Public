// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;

interface IPoolManagerLogic {
  function poolLogic() external view returns (address poolLogicAddress);

  function isDepositAsset(address asset) external view returns (bool isDeposit);

  function validateAsset(address asset) external view returns (bool isValid);

  function assetValue(address asset) external view returns (uint256 value);

  function assetValue(address asset, uint256 amount) external view returns (uint256 value);

  function assetBalance(address asset) external view returns (uint256 balance);

  function factory() external view returns (address factoryAddress);

  function setPoolLogic(address fundAddress) external returns (bool success);

  function totalFundValue() external view returns (uint256 total);

  function totalFundValueWithMaxAge() external view returns (uint256 total);

  function isMemberAllowed(address member) external view returns (bool isAllowed);

  function getFee()
    external
    view
    returns (
      uint256 performanceFeeNumerator,
      uint256 managerFeeNumerator,
      uint256 entryFeeNumerator,
      uint256 exitFeeNumerator,
      uint256 feeDenominator
    );

  function minDepositUSD() external view returns (uint256 minDeposit);

  function getEntryFeeInfo()
    external
    view
    returns (uint256 entryFeeNumerator, uint256 poolFeeShareNumerator, uint256 feeDenominator);

  function getExitFeeInfo()
    external
    view
    returns (uint256 exitFeeNumerator, uint256 poolFeeShareNumerator, uint256 feeDenominator);

  function maxSupplyCap() external view returns (uint256 supplyCap);

  function getReferralShare() external view returns (uint256 shareNumerator);
}
