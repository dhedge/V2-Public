// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

interface IVelodromeVotingEscrow {
  struct Point {
    int128 bias;
    int128 slope; // # -dweight / dt
    uint256 ts;
    uint256 blk; // block
  }

  function token() external view returns (address);

  function team() external returns (address);

  function epoch() external view returns (uint256);

  // solhint-disable-next-line func-name-mixedcase
  function point_history(uint256 loc) external view returns (Point memory);

  // solhint-disable-next-line func-name-mixedcase
  function user_point_history(uint256 tokenId, uint256 loc) external view returns (Point memory);

  // solhint-disable-next-line func-name-mixedcase
  function user_point_epoch(uint256 tokenId) external view returns (uint256);

  function ownerOf(uint256) external view returns (address);

  function isApprovedOrOwner(address, uint256) external view returns (bool);

  function transferFrom(
    address,
    address,
    uint256
  ) external;

  function voting(uint256 tokenId) external;

  function abstain(uint256 tokenId) external;

  function attach(uint256 tokenId) external;

  function detach(uint256 tokenId) external;

  function checkpoint() external;

  // solhint-disable-next-line func-name-mixedcase
  function deposit_for(uint256 tokenId, uint256 value) external;

  // solhint-disable-next-line func-name-mixedcase
  function create_lock_for(
    uint256,
    uint256,
    address
  ) external returns (uint256);

  function balanceOfNFT(uint256) external view returns (uint256);

  function totalSupply() external view returns (uint256);
}
