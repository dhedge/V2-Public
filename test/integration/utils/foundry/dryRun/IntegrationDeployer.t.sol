// SPDX-License-Identifier: MIT

pragma solidity >=0.7.6 <0.9.0;

import {PoolFactory} from "contracts/PoolFactory.sol";

/// @dev Extend from this contract if you want your integration tests deployment to be dry run agains production contracts
abstract contract IntegrationDeployer {
  function deployIntegration(
    PoolFactory /* _poolFactory */,
    address /* nftTracker */,
    address /* _slippageAccumulator */,
    address /* _usdPriceAggregator */
  ) external virtual {
    revert("implement deployIntegration");
  }
}
