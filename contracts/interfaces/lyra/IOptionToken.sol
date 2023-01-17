// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";

import "./IOptionMarket.sol";

interface IOptionToken is IERC721Enumerable {
  enum PositionState {
    EMPTY,
    ACTIVE,
    CLOSED,
    LIQUIDATED,
    SETTLED,
    MERGED
  }

  enum PositionUpdatedType {
    OPENED,
    ADJUSTED,
    CLOSED,
    SPLIT_FROM,
    SPLIT_INTO,
    MERGED,
    MERGED_INTO,
    SETTLED,
    LIQUIDATED,
    TRANSFER
  }

  struct OptionPosition {
    uint256 positionId;
    uint256 strikeId;
    IOptionMarket.OptionType optionType;
    uint256 amount;
    uint256 collateral;
    PositionState state;
  }

  struct PositionWithOwner {
    uint256 positionId;
    uint256 strikeId;
    IOptionMarket.OptionType optionType;
    uint256 amount;
    uint256 collateral;
    PositionState state;
    address owner;
  }

  function nextId() external view returns (uint256);

  function getOwnerPositions(address target) external view returns (OptionPosition[] memory);

  function positions(uint256 positionId) external view returns (OptionPosition memory);

  function getPositionState(uint256 positionId) external view returns (PositionState);

  function getPositionWithOwner(uint256 positionId) external view returns (PositionWithOwner memory);
}
