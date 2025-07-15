// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6;
pragma abicoder v2;

interface IPoolLogic {
  struct ComplexAsset {
    address supportedAsset;
    bytes withdrawData; // at the moment could be only struct ComplexAssetSwapData
    uint256 slippageTolerance; // duplicated from ComplexAssetSwapData on purpose
  }

  function factory() external view returns (address);

  function poolManagerLogic() external view returns (address);

  function setPoolManagerLogic(address _poolManagerLogic) external;

  function calculateAvailableManagerFee(uint256 _fundValue) external view returns (uint256 fee);

  function tokenPrice() external view returns (uint256 price);

  function tokenPriceWithoutManagerFee() external view returns (uint256 price);

  function mintManagerFee() external;

  function deposit(address _asset, uint256 _amount) external returns (uint256 liquidityMinted);

  function depositFor(address _recipient, address _asset, uint256 _amount) external returns (uint256 liquidityMinted);

  function depositForWithCustomCooldown(
    address _recipient,
    address _asset,
    uint256 _amount,
    uint256 _cooldown
  ) external returns (uint256 liquidityMinted);

  function withdraw(uint256 _fundTokenAmount) external;

  function withdrawSafe(uint256 _fundTokenAmount, ComplexAsset[] memory _complexAssetsData) external;

  function withdrawToSafe(
    address _recipient,
    uint256 _fundTokenAmount,
    ComplexAsset[] memory _complexAssetsData
  ) external;

  function transfer(address to, uint256 value) external returns (bool);

  function balanceOf(address owner) external view returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function symbol() external view returns (string memory);

  function transferFrom(address from, address to, uint256 value) external returns (bool);

  function getExitRemainingCooldown(address sender) external view returns (uint256 remaining);
}
