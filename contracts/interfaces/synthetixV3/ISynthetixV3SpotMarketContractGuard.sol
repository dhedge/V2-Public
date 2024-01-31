// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "../../utils/synthetixV3/libraries/SynthetixV3Structs.sol";

interface ISynthetixV3SpotMarketContractGuard {
  function allowedMarkets(address _synthAddress)
    external
    view
    returns (SynthetixV3Structs.AllowedMarket memory allowedMarket);
}
