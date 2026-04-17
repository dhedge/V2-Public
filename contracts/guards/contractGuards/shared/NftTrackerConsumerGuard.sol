// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {NftTrackerConsumerGuardBase} from "./NftTrackerConsumerGuardBase.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";

abstract contract NftTrackerConsumerGuard is NftTrackerConsumerGuardBase, TxDataUtils, ITransactionTypes {
  constructor(
    address _nftTracker,
    bytes32 _nftType,
    uint256 _maxPositions
  ) NftTrackerConsumerGuardBase(_nftTracker, _nftType, _maxPositions) {}
}
