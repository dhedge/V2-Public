// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {EthereumSetup} from "test/integration/utils/foundry/chains/EthereumSetup.t.sol";
import {MidasMApolloTestSetup} from "test/integration/common/midas/MidasMApolloTestSetup.t.sol";

/// @notice Ethereum mainnet fork binding for the Midas mAPOLLO integration test suite.
contract MidasMApolloTestEthereum is MidasMApolloTestSetup, EthereumSetup {
  constructor()
    EthereumSetup(25538718)
    MidasMApolloTestSetup(
      MidasChainData({
        mToken: 0x7CF9DEC92ca9FD46f8d86e7798B72624Bc116C05, // mAPOLLO
        depositVault: 0xc21511EDd1E6eCdc36e8aD4c82117033e50D5921,
        redemptionVault: 0x5aeA6D35ED7B3B7aE78694B7da2Ee880756Af5C0,
        mTokenFeed: 0x84303e5568C7B167fa4fEBc6253CDdfe12b7Ee4B,
        requestRedeemer: 0xBB97Da71852ec063695e81ff5373E895bAda7aEB
      })
    )
  {}

  function setUp() public override(MidasMApolloTestSetup, EthereumSetup) {
    EthereumSetup.setUp();
    MidasMApolloTestSetup.setUp();
  }
}
