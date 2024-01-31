// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

/**
 * @title Module for spot market factory
 */
interface ISpotMarketFactoryModule {
  /**
   * @notice Get the proxy address of the synth for the provided marketId
   * @dev Uses associated systems module to retrieve the token address.
   * @param marketId id of the market
   * @return synthAddress address of the proxy for the synth
   */
  function getSynth(uint128 marketId) external view returns (address synthAddress);
}
