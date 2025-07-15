// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {NftTrackerConsumerGuard} from "../shared/NftTrackerConsumerGuard.sol";
import {ITxTrackingGuard} from "../../../interfaces/guards/ITxTrackingGuard.sol";

abstract contract PancakeCLBaseContractGuard is NftTrackerConsumerGuard, ITxTrackingGuard {
  bool public override isTxTrackingGuard = true;

  constructor(
    address _nftTrackerAddress
  ) NftTrackerConsumerGuard(_nftTrackerAddress, keccak256("PANCAKE_NFT_TYPE"), 3) {}
}
