// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;
import {DytmParamStructs} from "../../utils/dytm/DytmParamStructs.sol";
interface IDytmPeriphery {
  function getAccountPosition(
    uint256 account,
    uint88 market
  ) external view returns (DytmParamStructs.AccountPosition memory position);
}
