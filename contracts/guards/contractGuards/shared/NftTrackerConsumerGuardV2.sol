// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {NftTrackerConsumerGuardBase} from "./NftTrackerConsumerGuardBase.sol";
import {TxDataUtilsV2} from "../../../utils/TxDataUtilsV2.sol";

abstract contract NftTrackerConsumerGuardV2 is NftTrackerConsumerGuardBase, TxDataUtilsV2, ITransactionTypes {
  constructor(
    address _nftTracker,
    bytes32 _nftType,
    uint256 _maxPositions
  ) NftTrackerConsumerGuardBase(_nftTracker, _nftType, _maxPositions) {}
}
