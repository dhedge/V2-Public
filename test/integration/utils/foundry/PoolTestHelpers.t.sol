// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PoolLogic} from "contracts/PoolLogic.sol";
import {IPoolLogic} from "contracts/interfaces/IPoolLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";

/// @notice Pool test helpers that read no deployment state: each one takes the pool it acts on, or
/// is pure. Both the fork-based `BackboneSetup` and the forkless `PoolUnitTestSetup` inherit this,
/// so the two suites cannot drift apart on how a deposit or a supported-asset array is built.
abstract contract PoolTestHelpers is Test {
  function _getEmptyPoolComplexAssetsData(
    address _pool
  ) internal view returns (IPoolLogic.ComplexAsset[] memory complexAssetsData) {
    complexAssetsData = new IPoolLogic.ComplexAsset[](
      IHasSupportedAsset(IPoolLogic(_pool).poolManagerLogic()).getSupportedAssets().length
    );
  }

  function _makeDeposit(
    PoolLogic _pool,
    address _depositor,
    address _token,
    uint256 _amount
  ) internal returns (uint256 liquidityMinted) {
    deal(_token, _depositor, _amount);

    vm.startPrank(_depositor);
    IERC20(_token).approve(address(_pool), _amount);
    liquidityMinted = _pool.deposit(_token, _amount);
    vm.stopPrank();
  }

  function _toArray(address _item) internal pure returns (address[] memory array) {
    array = new address[](1);
    array[0] = _item;
  }

  function _toSupportedAssets(
    address _asset,
    bool _isDeposit
  ) internal pure returns (IHasSupportedAsset.Asset[] memory assets) {
    assets = new IHasSupportedAsset.Asset[](1);
    assets[0] = IHasSupportedAsset.Asset({asset: _asset, isDeposit: _isDeposit});
  }
}
