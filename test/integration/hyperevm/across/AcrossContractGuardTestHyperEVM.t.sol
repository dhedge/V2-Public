// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IAssetHandler} from "contracts/interfaces/IAssetHandler.sol";

import {AcrossContractGuardTestSetup} from "test/integration/common/across/AcrossContractGuardTestSetup.t.sol";
import {BackboneSetup} from "test/integration/utils/foundry/BackboneSetup.t.sol";
import {EthereumConfig} from "test/integration/utils/foundry/config/EthereumConfig.sol";
import {AssetTypes} from "test/integration/utils/foundry/AssetTypes.sol";

/// @title Minimal BackboneSetup-based HyperEVM fork setup (mirrors BaseSetup/EthereumSetup).
/// @dev Defined inline here rather than reusing `chains/HyperEVMSetup.t.sol`: that one is the heavier
/// Hyperliquid (CoreSimulator) harness which is NOT a `BackboneSetup`, so it is incompatible with the
/// `BackboneSetup`-based common Across suite. The Across guard tests only need a forked dHEDGE stack
/// with USDC enabled, which this provides.
abstract contract HyperEVMBackboneSetup is BackboneSetup {
  uint256 public forkBlockNumber;

  constructor(
    uint256 _forkBlockNumber
  )
    BackboneSetup(
      // usdc — USDC on HyperEVM + USDC/USD Chainlink feed.
      IAssetHandler.Asset({
        asset: 0xb88339CB7199b77E23DB6E890353E22632Ba630f,
        assetType: uint16(AssetTypes.AssetTypeIncomplete.CHAINLINK),
        aggregator: 0xA0Adc43ce7AfE3EE7d7eac3C994E178D0620223B
      }),
      // weth slot — HyperEVM has no WETH, so use WHYPE + HYPE/USD Chainlink feed. The Across tests only
      // use `wethData` as the generic non-USDC token in the negative (revert) cases.
      IAssetHandler.Asset({
        asset: 0x5555555555555555555555555555555555555555,
        assetType: uint16(AssetTypes.AssetTypeIncomplete.CHAINLINK),
        aggregator: 0xa5a72eF19F82A579431186402425593a559ed352
      }),
      // dai slot — the Across tests only ever read `usdcData`/`wethData`, so the third ("dai") asset is
      // unused by them; reusing USDC here is harmless (it just needs to be a valid registered asset).
      IAssetHandler.Asset({
        asset: 0xb88339CB7199b77E23DB6E890353E22632Ba630f,
        assetType: uint16(AssetTypes.AssetTypeIncomplete.CHAINLINK),
        aggregator: 0xA0Adc43ce7AfE3EE7d7eac3C994E178D0620223B
      })
    )
  {
    forkBlockNumber = _forkBlockNumber;
  }

  function setUp() public virtual override {
    vm.createSelectFork("hyperevm", forkBlockNumber);
    // BackboneSetup.setUp() calls setChainlinkTimeout(365 days), so the real HyperEVM Chainlink feeds
    // configured above are accepted as-is on the fork — no price mocking needed.
    super.setUp();
  }
}

contract AcrossContractGuardTestHyperEVM is AcrossContractGuardTestSetup, HyperEVMBackboneSetup {
  uint256 private acrossTestForkBlockNumber = 39000000;
  address private acrossSpokePool = 0x35E63eA3eb0fb7A3bc543C71FB66412e1F6B0E04; // Across SpokePool on HyperEVM
  address private approvedDestToken = EthereumConfig.USDC; // USDC on Ethereum
  uint256 private approvedDestChainId = EthereumConfig.CHAIN_ID; // 1

  constructor()
    AcrossContractGuardTestSetup(acrossSpokePool, approvedDestToken, approvedDestChainId)
    HyperEVMBackboneSetup(acrossTestForkBlockNumber)
  {}

  function setUp() public override(AcrossContractGuardTestSetup, HyperEVMBackboneSetup) {
    super.setUp();
  }
}
