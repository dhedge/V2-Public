// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";
import {IOrderAnnouncementModule} from "./IOrderAnnouncementModule.sol";
import {IFlatcoinVaultV2} from "./IFlatcoinVaultV2.sol";

interface ILeverageModuleV2 is IERC721Enumerable {
  struct AnnouncedLeverageOpen {
    uint256 margin;
    uint256 additionalSize;
    uint256 maxFillPrice;
    uint256 stopLossPrice;
    uint256 profitTakePrice;
    uint256 tradeFee;
    address announcedBy;
  }

  struct AnnouncedLeverageClose {
    uint256 tokenId;
    uint256 minFillPrice;
    uint256 tradeFee;
  }

  struct Position {
    uint256 averagePrice;
    uint256 marginDeposited;
    uint256 additionalSize;
    int256 entryCumulativeFunding;
  }

  struct PositionSummary {
    int256 profitLoss;
    int256 accruedFunding;
    int256 marginAfterSettlement;
  }

  function executeOpen(
    address account,
    IOrderAnnouncementModule.Order calldata order
  ) external returns (uint256 tokenId);

  function executeAdjust(IOrderAnnouncementModule.Order calldata order) external;

  function executeClose(
    IOrderAnnouncementModule.Order calldata order
  ) external returns (uint256 marginAfterPositionClose);

  function getPositionSummary(uint256 tokenId) external view returns (PositionSummary memory positionSummary);

  function vault() external view returns (IFlatcoinVaultV2 vaultAddress);
}
