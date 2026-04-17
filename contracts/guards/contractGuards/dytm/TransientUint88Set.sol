// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title TransientUint88Set
/// @notice Transient storage-backed set with O(1) dedup via hash table and generation counter.
///         Safe for sequential reuse within the same transaction (generation bump invalidates old entries).
/// @dev Slot layout:
///      arrayBase + 0 = length, arrayBase + 1..n = elements
///      dedupBase + 0 = generation, dedupBase + value = insertion marker
abstract contract TransientUint88Set {
  /// @dev Adds value to the set if not already present. O(1) via transient hash table.
  function _addToSet(bytes32 arrayBase, bytes32 dedupBase, uint88 value) internal {
    // The generation counter ensures dedup correctness across sequential uses within the same tx.
    // When _readAndClearSet() is called, it bumps the generation so old dedup entries become stale
    // without needing to clear them individually.
    // We use generation + 1 as the marker value so that the transient default of 0 never matches.
    uint256 marker;
    assembly ("memory-safe") {
      marker := add(tload(dedupBase), 1)
    }

    // Check if already inserted this generation
    uint256 stored;
    assembly ("memory-safe") {
      stored := tload(add(dedupBase, value))
    }
    if (stored == marker) return;

    // Mark as inserted
    assembly ("memory-safe") {
      tstore(add(dedupBase, value), marker)
    }

    // Append to array
    assembly ("memory-safe") {
      let length := tload(arrayBase)
      tstore(add(add(arrayBase, 1), length), value)
      tstore(arrayBase, add(length, 1))
    }
  }

  /// @dev Reads all values into memory, resets length, and bumps generation to invalidate dedup entries.
  function _readAndClearSet(bytes32 arrayBase, bytes32 dedupBase) internal returns (uint88[] memory result) {
    uint256 length;
    assembly ("memory-safe") {
      length := tload(arrayBase)
    }

    result = new uint88[](length);
    for (uint256 i; i < length; ++i) {
      uint256 val;
      assembly ("memory-safe") {
        val := tload(add(add(arrayBase, 1), i))
      }
      result[i] = uint88(val);
    }

    // Reset length and bump generation
    assembly ("memory-safe") {
      tstore(arrayBase, 0)
      let gen := tload(dedupBase)
      tstore(dedupBase, add(gen, 1))
    }
  }
}
