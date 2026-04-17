// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {ISwapper} from "../../../interfaces/flatMoney/swapper/ISwapper.sol";
import {IPoolLogic} from "../../../interfaces/IPoolLogic.sol";

interface IWithdrawalVault {
  struct MultiInSingleOutData {
    ISwapper.SrcTokenSwapDetails[] srcData;
    ISwapper.DestData destData;
  }

  struct TrackedAsset {
    address token;
    uint256 balance;
  }

  function recoverAssets() external;

  function recoverAssets(uint256 _portion, address _to) external;

  function swapToSingleAsset(
    MultiInSingleOutData calldata _swapData,
    uint256 _expectedDestTokenAmount
  ) external returns (uint256 destTokenAmount);

  function unrollAssets(
    address _dHedgeVault,
    address _withdrawer,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) external;

  function getTrackedAssets() external view returns (TrackedAsset[] memory trackedAssets);

  function withdrawDhedgeVault(
    address _dHedgeVault,
    uint256 _amountIn,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) external;
}
