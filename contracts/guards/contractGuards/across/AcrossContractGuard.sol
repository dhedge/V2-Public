// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IGuard} from "../../../interfaces/guards/IGuard.sol";
import {ITransactionTypes} from "../../../interfaces/ITransactionTypes.sol";
import {TxDataUtils} from "../../../utils/TxDataUtils.sol";
import {V3SpokePoolInterface} from "../../../interfaces/across/V3SpokePoolInterface.sol";
import {IPoolManagerLogic} from "../../../interfaces/IPoolManagerLogic.sol";
import {IHasSupportedAsset} from "../../../interfaces/IHasSupportedAsset.sol";

contract AcrossContractGuard is IGuard, ITransactionTypes, TxDataUtils {
  using SafeMath for uint256;

  struct CrossChainBridge {
    address sourcePool;
    address destinationPool;
    address sourceToken;
    address destinationToken;
    uint256 destinationChainId;
  }

  // Nested mapping: poolLogic => (destinationHash => bool)
  mapping(address => mapping(bytes32 => bool)) public approvedDestinations;

  constructor(CrossChainBridge[] memory _settings) {
    for (uint256 i; i < _settings.length; ++i) {
      CrossChainBridge memory setting = _settings[i];
      bytes32 destinationHash = getDestinationHash(
        setting.destinationPool,
        setting.sourceToken,
        setting.destinationToken,
        setting.destinationChainId
      );
      approvedDestinations[setting.sourcePool][destinationHash] = true;
    }
  }

  function getDestinationHash(
    address _destinationPool,
    address _sourceToken,
    address _destinationToken,
    uint256 _destinationChainId
  ) public pure returns (bytes32 destinationHash) {
    return keccak256(abi.encodePacked(_destinationPool, _sourceToken, _destinationToken, _destinationChainId));
  }

  function txGuard(
    address _poolManagerLogic,
    address /* _to */,
    bytes calldata _data
  ) external view override returns (uint16 txType, bool isPublic) {
    address poolLogic = IPoolManagerLogic(_poolManagerLogic).poolLogic();

    bytes4 method = getMethod(_data);

    if (method == V3SpokePoolInterface.depositV3.selector) {
      (
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId
      ) = abi.decode(getParams(_data), (address, address, address, address, uint256, uint256, uint256));

      _validateDeposit(
        _poolManagerLogic,
        poolLogic,
        depositor,
        recipient,
        inputToken,
        outputToken,
        inputAmount,
        outputAmount,
        destinationChainId
      );

      txType = uint16(TransactionType.AcrossDepositV3);
      isPublic = false;
    } else if (method == V3SpokePoolInterface.deposit.selector) {
      // Newer bytes32-typed entrypoint. Same parameter ordering as depositV3, with the address
      // fields widened to bytes32; we convert them back to addresses and run identical validation.
      (
        bytes32 depositor,
        bytes32 recipient,
        bytes32 inputToken,
        bytes32 outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId
      ) = abi.decode(getParams(_data), (bytes32, bytes32, bytes32, bytes32, uint256, uint256, uint256));

      _validateDeposit(
        _poolManagerLogic,
        poolLogic,
        _toCheckedAddress(depositor),
        _toCheckedAddress(recipient),
        _toCheckedAddress(inputToken),
        _toCheckedAddress(outputToken),
        inputAmount,
        outputAmount,
        destinationChainId
      );

      txType = uint16(TransactionType.AcrossDeposit);
      isPublic = false;
    }
  }

  /// @dev Shared validation for the address-typed `depositV3` and the bytes32-typed `deposit`.
  // We don't verify message length, as approved recipient (dHEDGE vault) doesn't implement 'handleV3AcrossMessage' interface hence tx will revert
  function _validateDeposit(
    address _poolManagerLogic,
    address _poolLogic,
    address _depositor,
    address _recipient,
    address _inputToken,
    address _outputToken,
    uint256 _inputAmount,
    uint256 _outputAmount,
    uint256 _destinationChainId
  ) internal view {
    require(
      _isApprovedDestination(_poolLogic, _recipient, _inputToken, _outputToken, _destinationChainId),
      "not approved"
    );

    require(_depositor == _poolLogic, "depositor is not pool");

    require(IHasSupportedAsset(_poolManagerLogic).isSupportedAsset(_inputToken), "unsupported src token");

    // Hard stop when total fees for bridging are more than 1%
    require(_outputAmount >= _inputAmount.mul(99).div(100), "output too low");
  }

  /// @dev Converts a bytes32 to an address, reverting if the upper 96 bits are set (not an EVM address).
  function _toCheckedAddress(bytes32 _value) internal pure returns (address) {
    require(uint256(_value) >> 160 == 0, "invalid bytes32 address");
    return convert32toAddress(_value);
  }

  function _isApprovedDestination(
    address _poolLogic,
    address _destinationPool,
    address _sourceToken,
    address _destinationToken,
    uint256 _destinationChainId
  ) internal view returns (bool approved) {
    return
      approvedDestinations[_poolLogic][
        getDestinationHash(_destinationPool, _sourceToken, _destinationToken, _destinationChainId)
      ];
  }
}
