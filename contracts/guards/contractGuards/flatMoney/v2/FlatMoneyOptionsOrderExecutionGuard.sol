// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IERC721VerifyingGuard} from "../../../../interfaces/guards/IERC721VerifyingGuard.sol";
import {IFlatcoinVaultV2} from "../../../../interfaces/flatMoney/v2/IFlatcoinVaultV2.sol";
import {ClosedContractGuard} from "../../ClosedContractGuard.sol";
import {FlatMoneyBasisContractGuard} from "../shared/FlatMoneyBasisContractGuard.sol";
import {FlatMoneyV2OptionsConfig} from "../shared/FlatMoneyV2OptionsConfig.sol";

contract FlatMoneyOptionsOrderExecutionGuard is
  FlatMoneyBasisContractGuard,
  IERC721VerifyingGuard,
  ClosedContractGuard
{
  IFlatcoinVaultV2 public immutable vault;

  /// @param _nftTracker dHEDGE system NFT tracker contract address
  /// @param _vault Flat Money V2 Options vault contract address
  constructor(
    address _nftTracker,
    IFlatcoinVaultV2 _vault
  )
    FlatMoneyBasisContractGuard(
      _nftTracker,
      FlatMoneyV2OptionsConfig.NFT_TYPE,
      FlatMoneyV2OptionsConfig.MAX_POSITIONS,
      new PoolSetting[](0),
      FlatMoneyV2OptionsConfig.MAX_ALLOWED_LEVERAGE
    )
  {
    require(address(_vault) != address(0), "invalid vault");

    vault = _vault;
  }

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
    require(vault.isPositionOpenWhitelisted(msg.sender), "not whitelisted");

    return _verifyERC721(_operator, _from, _tokenId);
  }
}
