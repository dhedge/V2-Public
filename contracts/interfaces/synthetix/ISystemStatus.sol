pragma solidity 0.7.6;

interface ISystemStatus {
  struct Status {
    bool canSuspend;
    bool canResume;
  }

  struct Suspension {
    bool suspended;
    // reason is an integer code,
    // 0 => no reason, 1 => upgrading, 2+ => defined by system usage
    uint248 reason;
  }

  // Views
  function requireSynthActive(bytes32 currencyKey) external view;
}
