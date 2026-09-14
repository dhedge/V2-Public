// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

interface IHyperliquidWithdrawalManager {
  enum WithdrawalState {
    NONE,
    REDUCED,
    BRIDGED
  }

  struct PendingWithdrawal {
    uint256 amount;
    uint256 announcedAt;
    uint256 announcedBlock;
    uint256 bridgedBlock;
    WithdrawalState state;
    // Spot pair IDs (10000+) supplied at announce. Stored so `bridge` can size the Core->EVM bridge
    // to also cover the Core spot value the spot guard(s) demand in USDC at settle.
    uint32[] spotAssetIds;
    // USDC (6 decimals) this withdrawal reserved against the pool's shared Core free-USDC buffer:
    // its expected bridge draw, on both paths (a reduce-path withdrawal's freed margin is earmarked
    // for its own pending bridge). Released at settle/cancel.
    uint256 reservedBridge;
    // True when the announce skipped the reduce (the bridge was funded by free Core cash). Appended
    // for upgrade safety: pre-existing pending entries read false, and those all took the reduce path.
    bool reduceSkipped;
    // USDC (6 decimals) this withdrawal actually bridged Core->EVM, earmarked for its own settle so a
    // concurrent announce cannot credit it as idle pool liquidity. Set at bridge, released at
    // settle/cancel. Appended for upgrade safety: pre-existing entries read 0, which only makes the
    // idle-USDC credit as generous as it was before.
    uint256 bridgedUsdc;
  }

  event WithdrawalAnnounced(address indexed user, address indexed pool, uint256 amount);
  event WithdrawalBridged(address indexed user, address indexed pool);
  event WithdrawalSettled(address indexed user, address indexed pool, uint256 amount);
  event WithdrawalCancelled(address indexed user, address indexed pool, uint256 amount);
  event CoreWriterGuardUpdated(address indexed previousGuard, address indexed newGuard);

  function announceAndReduce(
    address pool,
    uint256 tokenAmount,
    uint32[] calldata perpAssetIds,
    uint32[] calldata spotAssetIds
  ) external;
  function bridge(address pool) external;
  function settle(address pool) external;
  function cancel(address pool) external;

  function pendingWithdrawals(address user, address pool) external view returns (PendingWithdrawal memory);

  /// @notice Returns true if the WM is currently executing a pool.execTransaction call.
  /// @dev Used by the guard to gate isPublic=true to only WM-initiated transactions.
  function isExecuting() external view returns (bool);
}
