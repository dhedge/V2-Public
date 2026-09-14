// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {PoolLogic} from "contracts/PoolLogic.sol";
import {PoolManagerLogic} from "contracts/PoolManagerLogic.sol";
import {IHasSupportedAsset} from "contracts/interfaces/IHasSupportedAsset.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";

/// @notice The backbone plus the single vault most guard suites drive, and the actions those suites
/// repeat against it: running a transaction as the manager, dropping a supported asset, and
/// withdrawing half the investor's shares. A suite that needs more than one vault declares the
/// extra ones itself.
abstract contract SingleFundTestSetup is BackboneSetup {
  PoolLogic internal fund;
  PoolManagerLogic internal fundManagerLogic;

  function _managerExec(address _to, bytes memory _data) internal {
    vm.prank(manager);
    fund.execTransaction(_to, _data);
  }

  /// @dev An asset can only be dropped once the vault no longer holds it.
  function _removeSupportedAsset(address _asset) internal {
    deal(_asset, address(fund), 0);

    vm.prank(manager);
    fundManagerLogic.changeAssets(new IHasSupportedAsset.Asset[](0), _toArray(_asset));
  }

  function _withdrawHalf() internal {
    uint256 shares = fund.balanceOf(investor) / 2;

    vm.prank(investor);
    fund.withdraw(shares);
  }
}
