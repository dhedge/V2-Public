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

  modifier checkContractGuard(address _guardedContract) {
    require(IHasGuardInfo(poolFactory).getContractGuard(_guardedContract) == msg.sender, "not correct contract guard");

    _;
  }

  /**
   * @notice record new NFT data
   * @dev only called by authorized guard
   * @param _guardedContract the address of contract using nftStorage
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
    _addData(_nftType, _pool, _data);
  }

  /**
   * @notice record new NFT data
   * @dev only called by authorized guard
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @param _data the nft track data to be recorded in storage
   */
  function _addData(
    bytes32 _nftType,
    address _pool,
    bytes memory _data
  ) private {
    _nftTrackData[_nftType][_pool].push(_data);
  }

  /**
   * @notice delete NFT data
   * @dev only called by authorized guard
   * @param _guardedContract the address of contract using nftStorage
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
    _removeData(_nftType, _pool, _index);
  }

  /**
   * @notice delete NFT data
   * @dev only called by authorized guard
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @param _index the nft track data index to be removed from storage
   */
  function _removeData(
    bytes32 _nftType,
    address _pool,
    uint256 _index
  ) private {
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
  function getAllData(bytes32 _nftType, address _pool) public view returns (bytes[] memory) {
    return _nftTrackData[_nftType][_pool];
  }

  /**
   * @notice returns all tracked nfts by NFT_TYPE & poolLogic
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @return count all tracked nfts count of given NFT_TYPE & poolLogic
   */
  function getDataCount(bytes32 _nftType, address _pool) public view returns (uint256) {
    return _nftTrackData[_nftType][_pool].length;
  }

  /**
   * @notice returns all tracked nft ids by NFT_TYPE & poolLogic if stored as uint256
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @return tokenIds all tracked nfts of given NFT_TYPE & poolLogic
   */
  function getAllUintIds(bytes32 _nftType, address _pool) public view returns (uint256[] memory tokenIds) {
    bytes[] memory data = getAllData(_nftType, _pool);
    tokenIds = new uint256[](data.length);
    for (uint256 i = 0; i < data.length; i++) {
      tokenIds[i] = abi.decode(data[i], (uint256));
    }
  }

  /**
   * @notice record new NFT uint256 id
   * @dev only called by authorized guard
   * @param _guardedContract the address of contract using nftStorage
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @param _nftID the nft id recorded in storage
   */
  function addUintId(
    address _guardedContract,
    bytes32 _nftType,
    address _pool,
    uint256 _nftID,
    uint256 _maxPositions
  ) external checkContractGuard(_guardedContract) {
    _addData(_nftType, _pool, abi.encode(_nftID));
    require(getDataCount(_nftType, _pool) <= _maxPositions, "max position reached");
  }

  /**
   * @notice record new NFT uint256 id
   * @dev only called by authorized guard
   * @param _guardedContract the address of contract using nftStorage
   * @param _nftType keccak of NFT_TYPE
   * @param _pool the poolLogic address
   * @param _nftID the nft id recorded in storage
   */
  function removeUintId(
    address _guardedContract,
    bytes32 _nftType,
    address _pool,
    uint256 _nftID
  ) external checkContractGuard(_guardedContract) {
    bytes[] memory data = getAllData(_nftType, _pool);
    for (uint256 i = 0; i < data.length; i++) {
      if (abi.decode(data[i], (uint256)) == _nftID) {
        _removeData(_nftType, _pool, i);
        return;
      }
    }

    revert("not found");
  }

  function removeDataByUintId(
    bytes32 _nftType,
    address _pool,
    uint256 _nftID
  ) external onlyOwner {
    bytes[] memory data = getAllData(_nftType, _pool);
    for (uint256 i = 0; i < data.length; i++) {
      if (abi.decode(data[i], (uint256)) == _nftID) {
        _removeData(_nftType, _pool, i);
        return;
      }
    }
    revert("not found");
  }

  function removeDataByIndex(
    bytes32 _nftType,
    address _pool,
    uint256 _index
  ) external onlyOwner {
    _removeData(_nftType, _pool, _index);
  }

  function addDataByUintId(
    bytes32 _nftType,
    address _pool,
    uint256 _nftID
  ) external onlyOwner {
    _addData(_nftType, _pool, abi.encode(_nftID));
  }
}
