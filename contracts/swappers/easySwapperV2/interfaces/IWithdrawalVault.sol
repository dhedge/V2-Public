// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma abicoder v2;

import {ISwapper} from "../../../interfaces/flatMoney/swapper/ISwapper.sol";

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

  function unrollAssets(address _dHedgeVault) external;

  function getTrackedAssets() external view returns (TrackedAsset[] memory trackedAssets);
}
