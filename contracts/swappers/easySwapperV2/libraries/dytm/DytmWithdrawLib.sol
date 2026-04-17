// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import {IPoolLogic} from "../../../../interfaces/IPoolLogic.sol";
import {IHasGuardInfo} from "../../../../interfaces/IHasGuardInfo.sol";
import {IDytmOffice} from "../../../../interfaces/dytm/IDytmOffice.sol";
import {IDytmDelegatee} from "../../../../interfaces/dytm/IDytmDelegatee.sol";
import {DytmParamStructs} from "../../../../utils/dytm/DytmParamStructs.sol";
import {DytmSplitTokenIdTracker} from "../../../../guards/assetGuards/dytm/DytmSplitTokenIdTracker.sol";
import {IEasySwapperV2} from "../../interfaces/IEasySwapperV2.sol";
import {DytmOfficeAssetGuard} from "../../../../guards/assetGuards/dytm/DytmOfficeAssetGuard.sol";

library DytmWithdrawLib {
  /// @notice Process DYTM position unwinding during EasySwapper withdrawal
  /// @param _dytmOffice DYTM Office address (asset type 106)
  /// @param _complexAssetsData Complex assets data from pool withdrawal
  /// @param _creator EasySwapperV2 address
  /// @param _withdrawer Address of the withdrawer (msg.sender of initWithdrawal)
  /// @return tokensToTrack Tokens expected in vault after processing
  function processDytmPosition(
    address _dytmOffice,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData,
    address _creator,
    address _withdrawer
  ) internal returns (address[] memory tokensToTrack) {
    // 1. Get split positions — skip if none (no positions for this vault)
    // Note: address(this) is the WithdrawalVault since this library runs in vault context.
    // Split positions are keyed by the vault address (set as `_to` in DytmOfficeAssetGuard.withdrawProcessing).
    address assetGuard = _getAssetGuard(_dytmOffice, _creator);
    DytmSplitTokenIdTracker.SplitPosition[] memory splitPositions = DytmSplitTokenIdTracker(assetGuard)
      .getSplitPositions(address(this));
    if (splitPositions.length == 0) return tokensToTrack;

    // 2. Find matching ComplexAsset entry — reverts if missing (frontend bug or unsupported nested DYTM vault)
    (bool found, IPoolLogic.ComplexAsset memory complexAsset) = _findComplexAsset(_dytmOffice, _complexAssetsData);
    require(found, "missing DYTM complex asset data");

    // 3. Get trusted DytmWithdrawProcessor from asset guard
    address processor = DytmOfficeAssetGuard(assetGuard).dytmWithdrawProcessor();
    require(processor != address(0), "dytm processor not set");

    // 4. Transfer isolated accounts to processor so it can operate on them
    for (uint256 i; i < splitPositions.length; ++i) {
      IDytmOffice(_dytmOffice).transfer(processor, splitPositions[i].tokenId, 1);
    }

    // 5. Execute delegationCall — verification and processing happen inside the processor
    bytes memory returnData = IDytmOffice(_dytmOffice).delegationCall(
      DytmParamStructs.DelegationCallParams({
        delegatee: IDytmDelegatee(processor),
        callbackData: abi.encode(splitPositions, _withdrawer, complexAsset)
      })
    );
    tokensToTrack = abi.decode(returnData, (address[]));
  }

  function _findComplexAsset(
    address _dytmOffice,
    IPoolLogic.ComplexAsset[] memory _complexAssetsData
  ) private pure returns (bool found, IPoolLogic.ComplexAsset memory complexAsset) {
    for (uint256 i; i < _complexAssetsData.length; ++i) {
      if (_complexAssetsData[i].supportedAsset == _dytmOffice) {
        return (true, _complexAssetsData[i]);
      }
    }
  }

  function _getAssetGuard(address _dytmOffice, address _creator) private view returns (address) {
    address poolFactory = IEasySwapperV2(_creator).dHedgePoolFactory();
    return IHasGuardInfo(poolFactory).getAssetGuard(_dytmOffice);
  }
}
