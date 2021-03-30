pragma solidity ^0.6.2;

interface IExchanger {

    function settle(address from, bytes32 currencyKey)
        external
        returns (
            uint reclaimed,
            uint refunded,
            uint numEntries
        );

    function maxSecsLeftInWaitingPeriod(address account, bytes32 currencyKey) external view returns (uint);

}