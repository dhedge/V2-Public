// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import {IHasSupportedAsset} from "../../interfaces/IHasSupportedAsset.sol";

abstract contract SourceAssetCheckGuard {
  /// @dev poolLogic -> srcAsset -> bool
  mapping(address => mapping(address => bool)) internal _beforeSwapSrcAssetCheck;

  function _setSourceAsset(address _poolLogic, address _poolManagerLogic, address _srcAsset) internal virtual {
    if (IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_srcAsset)) {
      _beforeSwapSrcAssetCheck[_poolLogic][_srcAsset] = true;
    }
  }

  function _checkSourceAsset(address _poolLogic, address _poolManagerLogic, address _srcAsset) internal virtual {
    if (_beforeSwapSrcAssetCheck[_poolLogic][_srcAsset]) {
      require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_srcAsset), "unsupported source asset");

      _beforeSwapSrcAssetCheck[_poolLogic][_srcAsset] = false;
    }
  }
}
