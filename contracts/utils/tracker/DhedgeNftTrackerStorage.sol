// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../interfaces/IHasGuardInfo.sol";

contract DhedgeNftTrackerStorage is OwnableUpgradeable {
  address public poolFactory; // dhedge pool factory
  mapping(bytes32 => mapping(address => bytes[])) internal _nftTrackData; // keccak of NFT_TYPE -> poolAddress -> data[]

  // solhint-disable-next-line no-empty-blocks
  function initialize(address _poolFactory) external initializer {
    __Ownable_init();
    poolFactory = _poolFactory;
  }

  /// @notice implementations should not be left unintialized
  // solhint-disable-next-line no-empty-blocks
  function implInitializer() external initializer {}

  modifier checkContractGuard(address _guardedContract) {
    require(IHasGuardInfo(poolFactory).getContractGuard(_guardedContract) == msg.sender, "not correct contract guard");

    _;
  }

  /**
   * @notice record new NFT data
   * @dev only called by authorized guard
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @param _data the nft track data to be recorded in storage
   */
  function addData(
    address _guardedContract,
    bytes32 _nftType,
    address _pool,
    bytes memory _data
  ) external checkContractGuard(_guardedContract) {
    _nftTrackData[_nftType][_pool].push(_data);
  }

  /**
   * @notice delete NFT data
   * @dev only called by authorized guard
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @param _index the nft track data index to be removed from storage
   */
  function removeData(
    address _guardedContract,
    bytes32 _nftType,
    address _pool,
    uint256 _index
  ) external checkContractGuard(_guardedContract) {
    uint256 length = _nftTrackData[_nftType][_pool].length;
    require(_index < length, "invalid index");

    _nftTrackData[_nftType][_pool][_index] = _nftTrackData[_nftType][_pool][length - 1];
    _nftTrackData[_nftType][_pool].pop();
  }

  /**
   * @notice returns tracked nft by index
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @param _index the index of nft track data
   * @return data the nft track data of given NFT_TYPE & poolLogic & index
   */
  function getData(
    bytes32 _nftType,
    address _pool,
    uint256 _index
  ) external view returns (bytes memory) {
    return _nftTrackData[_nftType][_pool][_index];
  }

  /**
   * @notice returns all tracked nfts by NFT_TYPE & poolLogic
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @return data all tracked nfts of given NFT_TYPE & poolLogic
   */
  function getAllData(bytes32 _nftType, address _pool) external view returns (bytes[] memory) {
    return _nftTrackData[_nftType][_pool];
  }

  /**
   * @notice returns all tracked nfts by NFT_TYPE & poolLogic
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @return count all tracked nfts count of given NFT_TYPE & poolLogic
   */
  function getDataCount(bytes32 _nftType, address _pool) external view returns (uint256) {
    return _nftTrackData[_nftType][_pool].length;
  }
}
