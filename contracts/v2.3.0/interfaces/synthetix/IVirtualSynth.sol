// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./ISynth.sol";

interface IVirtualSynth {
  // Views
  function balanceOfUnderlying(address account) external view returns (uint256);

  function rate() external view returns (uint256);

  function readyToSettle() external view returns (bool);

  function secsLeftInWaitingPeriod() external view returns (uint256);

  function settled() external view returns (bool);

  function synth() external view returns (ISynth);

  // Mutative functions
  function settle(address account) external;
}
