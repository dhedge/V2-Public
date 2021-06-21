// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
    
    function getPriceOracle() external view returns (address);
}
