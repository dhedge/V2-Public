// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC721VerifyingGuard} from "../../../../interfaces/guards/IERC721VerifyingGuard.sol";
import {ClosedContractGuard} from "../../ClosedContractGuard.sol";
import {FlatMoneyV2PerpsConfig} from "../shared/FlatMoneyV2PerpsConfig.sol";
import {FlatMoneyBasisContractGuard} from "../shared/FlatMoneyBasisContractGuard.sol";

contract FlatMoneyV2OrderExecutionGuard is FlatMoneyBasisContractGuard, IERC721VerifyingGuard, ClosedContractGuard {
  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _whitelisteddHedgePools dHEDGE pools that are allowed to use Order Announcement
  constructor(
    address _nftTracker,
    PoolSetting[] memory _whitelisteddHedgePools
  )
    FlatMoneyBasisContractGuard(
      _nftTracker,
      FlatMoneyV2PerpsConfig.NFT_TYPE,
      FlatMoneyV2PerpsConfig.MAX_POSITIONS,
      _whitelisteddHedgePools,
      FlatMoneyV2PerpsConfig.MAX_ALLOWED_LEVERAGE
    )
  {}

  /// @param _operator Address which calls onERC721Received callback
  /// @param _from Address which transfers the NFT
  /// @param _tokenId ID of the NFT
  /// @return verified True if the NFT is verified
  function verifyERC721(
    address _operator,
    address _from,
    uint256 _tokenId,
    bytes calldata
  ) external override returns (bool verified) {
    require(_isPoolWhitelisted(msg.sender), "not whitelisted");

    return _verifyERC721(_operator, _from, _tokenId);
  }
}
