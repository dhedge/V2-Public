# What are the `contracts/v2.4.1` ie PoolFactoryV24

In `PoolFactoryTest` there are tests that deploy an older version of our contracts and then simulate an upgrade, they then check that the contracts work as intended post upgrade. The files should under most circumstances never need to be changed.

When adding new storage to upgradable contracts, the upgrade process will sometimes complain that the storage layout of the contract with the new storage does not match the layout stored in the `.openzeppelin` files.

There are more details about it here:

- https://forum.openzeppelin.com/t/using-storage-gaps-with-hardhat-upgrades/14567/6
- https://forum.openzeppelin.com/t/storage-layout-upgrade-with-hardhat-upgrades/14567/3


