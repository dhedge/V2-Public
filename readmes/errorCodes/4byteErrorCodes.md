# Error Codes

## DYTM Integration (dHEDGE Guards)

| Error String                  | 4-Byte Code  | Source Contract                         |
| ----------------------------- | ------------ | --------------------------------------- |
| `pool not whitelisted`        | `0x21448b77` | DytmOfficeContractGuard                 |
| `unsupported asset`           | `0xdbecdeb4` | DytmOfficeContractGuard                 |
| `invalid user account`        | `0x8495a575` | DytmOfficeContractGuard / DytmHelperLib |
| `invalid market`              | `0x1612cc86` | DytmOfficeContractGuard                 |
| `invalid receiver`            | `0x0eb53f43` | DytmOfficeContractGuard                 |
| `invalid delegatee`           | `0x11e0ab4f` | DytmOfficeContractGuard                 |
| `health factor too low`       | `0x160c640e` | DytmOfficeContractGuard                 |
| `nested delegate call`        | `0x7e39d91a` | DytmDelegationCallCheckGuard            |
| `no ongoing delegate call`    | `0x8e5f61be` | DytmDelegationCallCheckGuard            |
| `Invalid raw account ID`      | `0x3d2e4206` | DytmHelperLib                           |
| `invalid dytmOffice`          | `0xb6d0d48b` | DytmWithdrawProcessor                   |
| `invalid dytmPeriphery`       | `0xac8a3532` | DytmWithdrawProcessor                   |
| `invalid swapper`             | `0xfb945459` | DytmWithdrawProcessor                   |
| `only dytm office`            | `0x1caa4fc9` | DytmWithdrawProcessor                   |
| `dytm processor not set`      | `0x749abf71` | WithdrawalVault                         |
| `dytm delegation call failed` | `0xe97325de` | WithdrawalVault                         |

## DYTM Protocol (Custom Errors)

### AccountIdLibrary

| Error                                                 | 4-Byte Code  |
| ----------------------------------------------------- | ------------ |
| `AccountIdLibrary__ZeroAddress()`                     | `0xeff89123` |
| `AccountIdLibrary__ZeroAccountNumber()`               | `0x8e96791f` |
| `AccountIdLibrary__InvalidRawAccountId(uint256)`      | `0xe0336c1b` |
| `AccountIdLibrary__InvalidUserAccountId(uint256)`     | `0xbc9e1e6e` |
| `AccountIdLibrary__InvalidIsolatedAccountId(uint256)` | `0xa17adb0f` |

### ReserveKeyLibrary

| Error                                           | 4-Byte Code  |
| ----------------------------------------------- | ------------ |
| `ReserveKeyLibrary__ZeroMarketId()`             | `0x8b6d06e4` |
| `ReserveKeyLibrary__InvalidReserveKey(uint248)` | `0x4590114e` |

### MarketIdLibrary

| Error                             | 4-Byte Code  |
| --------------------------------- | ------------ |
| `MarketIdLibrary__ZeroMarketId()` | `0x7254bce5` |

### FixedBorrowRateIRM

| Error                                     | 4-Byte Code  |
| ----------------------------------------- | ------------ |
| `FixedBorrowRateIRM__NotOfficer(address)` | `0x04681b20` |

### LinearKinkIRM

| Error                                               | 4-Byte Code  |
| --------------------------------------------------- | ------------ |
| `LinearKinkIRM__NotOfficer(address)`                | `0x99e57ed1` |
| `LinearKinkIRM__InvalidOptimalUtilization(uint256)` | `0x2c44e7e9` |

### HooksCallHelpers

| Error                                           | 4-Byte Code  |
| ----------------------------------------------- | ------------ |
| `HookCallHelpers__HookCallFailed(bytes4,bytes)` | `0x0e376686` |

### TransientEnumerableHashTableStorage

| Error                                                     | 4-Byte Code  |
| --------------------------------------------------------- | ------------ |
| `TransientEnumerableHashTableStorage__QueueFull()`        | `0x2c0127cb` |
| `TransientEnumerableHashTableStorage__IndexOutOfBounds()` | `0x6ad347e7` |

### OfficeStorage

| Error                                       | 4-Byte Code  |
| ------------------------------------------- | ------------ |
| `OfficeStorage__ZeroAddress()`              | `0x314dc2c9` |
| `OfficeStorage__NotOfficer(uint88,address)` | `0xf9dda0a2` |

### Office

| Error                                                         | 4-Byte Code  |
| ------------------------------------------------------------- | ------------ |
| `Office__NoAssetsRepaid()`                                    | `0x8af6d52c` |
| `Office__ReserveIsEmpty(uint248)`                             | `0x64444f03` |
| `Office__IncorrectTokenId(uint256)`                           | `0x5c52125e` |
| `Office__AssetNotBorrowable(uint248)`                         | `0xa6d06a58` |
| `Office__ReserveNotSupported(uint248)`                        | `0xb2c44dff` |
| `Office__InvalidHooksContract(address)`                       | `0x79f2f887` |
| `Office__AccountNotCreated(uint256)`                          | `0x60093749` |
| `Office__CannotLiquidateDuringDelegationCall()`               | `0x23f5efcf` |
| `Office__InKindWithdrawalsOnlyForLiquidation()`               | `0x6a874579` |
| `Office__InvalidFraction(uint64)`                             | `0x55886773` |
| `Office__InsufficientLiquidity(uint248)`                      | `0x19838cff` |
| `Office__InvalidCollateralType(uint8)`                        | `0xd4194888` |
| `Office__AccountNotHealthy(uint256,uint88)`                   | `0xdb37ef65` |
| `Office__AssetsAndSharesNonZero(uint256,uint256)`             | `0x54c10875` |
| `Office__AccountStillHealthy(uint256,uint88)`                 | `0x2bdd4b1d` |
| `Office__MismatchedAssetsInMigration(address,address)`        | `0x3ebb7a22` |
| `Office__SameMarketInMigration(uint256,uint256)`              | `0x220c30e2` |
| `Office__ZeroAssetsOrSharesWithdrawn(uint256,uint248)`        | `0x26a38603` |
| `Office__DebtBelowMinimum(uint256,uint256)`                   | `0x0ada04c5` |
| `Office__TransferNotAllowed(uint256,uint256,uint256,uint256)` | `0x5b3a4b0e` |

### Registry

| Error                                                                                    | 4-Byte Code  |
| ---------------------------------------------------------------------------------------- | ------------ |
| `Registry__ZeroAddress()`                                                                | `0x9067ef91` |
| `Registry__ZeroAccount()`                                                                | `0x1f649ff1` |
| `Registry__NoAccountOwner(uint256)`                                                      | `0xd5e797d1` |
| `Registry__InvalidSpender(uint256)`                                                      | `0xdf2e4f8a` |
| `Registry__IsNotAccountOwner(uint256,address)`                                           | `0x68626913` |
| `Registry__NotAuthorizedCaller(uint256,address)`                                         | `0x46c0a3dc` |
| `Registry__TokenRemovalFromSetFailed(uint256,uint256)`                                   | `0x0821e76d` |
| `Registry__DebtIdMismatch(uint256,uint256,uint256)`                                      | `0x3db4169c` |
| `Registry__InsufficientBalance(uint256,uint256,uint256,uint256)`                         | `0xaa0bf547` |
| `Registry__DifferentOwnersWhenTransferringDebt(uint256,uint256,address,address,uint256)` | `0x33e114b6` |
| `Registry__InsufficientAllowance(uint256,uint256,uint256,uint256,uint256)`               | `0x106f778c` |

### Context

| Error                          | 4-Byte Code  |
| ------------------------------ | ------------ |
| `Context__ContextAlreadySet()` | `0x5bcbaeb4` |

### AddressAccountBaseWhitelist

| Error                                                         | 4-Byte Code  |
| ------------------------------------------------------------- | ------------ |
| `AddressAccountBaseWhitelist_ZeroAddress()`                   | `0xdfc1c7cf` |
| `AddressAccountBaseWhitelist_NotWhitelisted(uint256,address)` | `0xb319e709` |

### AccountSplitterAndMerger

| Error                                               | 4-Byte Code  |
| --------------------------------------------------- | ------------ |
| `AccountSplitterAndMerger_ZeroAddress()`            | `0x8f7e5a3b` |
| `AccountSplitterAndMerger_OnlyOffice(address)`      | `0x62c6aa58` |
| `AccountSplitterAndMerger_InvalidFraction(uint256)` | `0x6ba35cb5` |
| `AccountSplitterAndMerger_InvalidOperation(uint8)`  | `0x946f17ef` |

### SimpleDelegatee

| Error                                          | 4-Byte Code  |
| ---------------------------------------------- | ------------ |
| `SimpleDelegatee__CallFailed((address,bytes))` | `0x984a13ef` |

### OwnableDelegatee

| Error                                           | 4-Byte Code  |
| ----------------------------------------------- | ------------ |
| `OwnableDelegatee__NotOwner()`                  | `0x849181f4` |
| `OwnableDelegatee__CallFailed((address,bytes))` | `0x66ff4375` |

### BaseHook

| Error                                      | 4-Byte Code  |
| ------------------------------------------ | ------------ |
| `BaseHook_OnlyOffice()`                    | `0xec8ee2df` |
| `BaseHook_ZeroAddress()`                   | `0xc6679829` |
| `BaseHook_IncorrectHooks(uint160,uint160)` | `0x722b1f58` |

### BorrowerWhitelist

| Error                              | 4-Byte Code  |
| ---------------------------------- | ------------ |
| `BorrowerWhitelist_ZeroMarketId()` | `0x6845415e` |

### SimpleAccountWhitelist

| Error                                   | 4-Byte Code  |
| --------------------------------------- | ------------ |
| `SimpleAccountWhitelist_ZeroMarketId()` | `0x893ccc05` |

### SimpleMarketConfig

| Error                                           | 4-Byte Code  |
| ----------------------------------------------- | ------------ |
| `SimpleMarketConfig__ZeroAddress()`             | `0xd8cba5fd` |
| `SimpleMarketConfig__ParamsNotSet()`            | `0x6008ace7` |
| `SimpleMarketConfig__InvalidPercentage(uint64)` | `0xa65233c2` |

### dHEDGEPoolPriceAggregator

| Error                                                    | 4-Byte Code  |
| -------------------------------------------------------- | ------------ |
| `dHEDGEPoolPriceAggregator__ZeroValue()`                 | `0xa8ca0a85` |
| `dHEDGEPoolPriceAggregator__ZeroAddress()`               | `0xbea4e316` |
| `dHEDGEPoolPriceAggregator__PriceNotFound(address)`      | `0xd4486b91` |
| `dHEDGEPoolPriceAggregator__StalePrice(address,uint256)` | `0xec092f5c` |

### SimpleWeights

| Error                                            | 4-Byte Code  |
| ------------------------------------------------ | ------------ |
| `SimpleWeights__ZeroAddress()`                   | `0x4db811a3` |
| `SimpleWeights__NotOfficer(uint88,address)`      | `0xd9228d2c` |
| `SimpleWeights__InvalidWeight(uint64,uint64)`    | `0x1fca77a0` |
| `SimpleWeights__WeightNotFound(uint256,uint248)` | `0x622ac828` |

### DYTMPeriphery

| Error                          | 4-Byte Code  |
| ------------------------------ | ------------ |
| `DYTMPeriphery__ZeroAddress()` | `0x416cea8d` |

### OfficeERC6909ToERC20Wrapper

| Error                                                                          | 4-Byte Code  |
| ------------------------------------------------------------------------------ | ------------ |
| `OfficeERC6909ToERC20Wrapper__Reentrancy()`                                    | `0xc82cc1b1` |
| `OfficeERC6909ToERC20Wrapper__ZeroAddress()`                                   | `0xe2f0d2ae` |
| `OfficeERC6909ToERC20Wrapper__ERC20AlreadyRegistered(uint256)`                 | `0x1d19571d` |
| `OfficeERC6909ToERC20Wrapper__NotOfficer(uint88,address)`                      | `0xb123d09e` |
| `OfficeERC6909ToERC20Wrapper__TransferFailed(address,address,uint256,uint256)` | `0x93d8057c` |

### WrappedERC6909ERC20

| Error                                 | 4-Byte Code  |
| ------------------------------------- | ------------ |
| `WrappedERC6909ERC20__Unauthorized()` | `0xe27b5495` |

## Hyperliquid Integration (dHEDGE Guards)

### HyperliquidPositionGuard

| Error String                      | 4-Byte Code  | Source Contract          |
| --------------------------------- | ------------ | ------------------------ |
| `account value !0`                | `0x707eb93b` | HyperliquidPositionGuard |
| `withdrawal asset not enabled`    | `0xe8e0fb80` | HyperliquidPositionGuard |
| `not enough available balance`    | `0xa08407a6` | HyperliquidPositionGuard |
| `invalid withdraw portion`        | `0x62651a32` | HyperliquidPositionGuard |
| `not enough withdrawal liquidity` | `0xb5b8115d` | HyperliquidPositionGuard |

### HyperliquidSpotGuard

| Error String                     | 4-Byte Code  | Source Contract      |
| -------------------------------- | ------------ | -------------------- |
| `not authorized`                 | `0x8aed0440` | HyperliquidSpotGuard |
| `invalid transaction target`     | `0x5819c28b` | HyperliquidSpotGuard |
| `pool not whitelisted`           | `0x21448b77` | HyperliquidSpotGuard |
| `invalid transfer receiver`      | `0xe1b0bef9` | HyperliquidSpotGuard |
| `unsupported spender approval`   | `0xc8b01997` | HyperliquidSpotGuard |
| `unsupported action`             | `0x22c59301` | HyperliquidSpotGuard |
| `invalid EVM decimals`           | `0x2cbdff2e` | HyperliquidSpotGuard |
| `cannot remove non-empty asset`  | `0x4fc5e4ce` | HyperliquidSpotGuard |
| `withdrawal asset not enabled`   | `0xe8e0fb80` | HyperliquidSpotGuard |
| `not enough available balance_0` | `0xfe725dbe` | HyperliquidSpotGuard |
| `invalid withdraw portion`       | `0x62651a32` | HyperliquidSpotGuard |
| `not enough available balance_1` | `0x3d8a7ab3` | HyperliquidSpotGuard |

### HyperliquidCoreDepositWalletContractGuard

| Error String               | 4-Byte Code  | Source Contract                           |
| -------------------------- | ------------ | ----------------------------------------- |
| `not authorized`           | `0x8aed0440` | HyperliquidCoreDepositWalletContractGuard |
| `pool not whitelisted`     | `0x21448b77` | HyperliquidCoreDepositWalletContractGuard |
| `invalid target contract`  | `0x62b218bd` | HyperliquidCoreDepositWalletContractGuard |
| `USDC not supported asset` | `0x6a73f278` | HyperliquidCoreDepositWalletContractGuard |
| `invalid dex id`           | `0x76f2b681` | HyperliquidCoreDepositWalletContractGuard |
| `unsupported action`       | `0x22c59301` | HyperliquidCoreDepositWalletContractGuard |

### HyperliquidCoreWriterContractGuard

| Error String                       | 4-Byte Code  | Source Contract                    |
| ---------------------------------- | ------------ | ---------------------------------- |
| `invalid caller`                   | `0x3014fc45` | HyperliquidCoreWriterContractGuard |
| `pool not whitelisted`             | `0x21448b77` | HyperliquidCoreWriterContractGuard |
| `unsupported method`               | `0x6cd7db32` | HyperliquidCoreWriterContractGuard |
| `GTC reduce-only for spot`         | `0x55d87b58` | HyperliquidCoreWriterContractGuard |
| `Slippage exceeds limit`           | `0x16a8de1d` | HyperliquidCoreWriterContractGuard |
| `unsupported order type`           | `0x6452fcd9` | HyperliquidCoreWriterContractGuard |
| `unsupported spot asset`           | `0xab7d4940` | HyperliquidCoreWriterContractGuard |
| `unsupported asset`                | `0xdbecdeb4` | HyperliquidCoreWriterContractGuard |
| `invalid destination`              | `0x8ccde237` | HyperliquidCoreWriterContractGuard |
| `invalid destination addr`         | `0x365552a4` | HyperliquidCoreWriterContractGuard |
| `invalid sub-account addr`         | `0xc339eef1` | HyperliquidCoreWriterContractGuard |
| `invalid destination dex`          | `0xed1ebb91` | HyperliquidCoreWriterContractGuard |
| `unsupported action`               | `0x22c59301` | HyperliquidCoreWriterContractGuard |
| `unsupported version`              | `0x3b0fd64c` | HyperliquidCoreWriterContractGuard |
| `invalid asset ID`                 | `0x826e336b` | HyperliquidCoreWriterContractGuard |
| `only perp assets can be approved` | `0x7beedf78` | HyperliquidCoreWriterContractGuard |
| `max slippage must be <= 100%`     | `0x8e7f6aa3` | HyperliquidCoreWriterContractGuard |
| `invalid pool logic`               | `0x5a76e914` | HyperliquidCoreWriterContractGuard |

### HyperliquidSpotPriceAggregator

| Error String   | 4-Byte Code  | Source Contract                |
| -------------- | ------------ | ------------------------------ |
| `Spot index 0` | `0x480bc2c2` | HyperliquidSpotPriceAggregator |

### ERC20 Errors

| Error                                                 | 4-Byte Code  |
| ----------------------------------------------------- | ------------ |
| `ERC20InsufficientBalance(address,uint256,uint256)`   | `0xe450d38c` |
| `ERC20InvalidSender(address)`                         | `0x96c6fd1e` |
| `ERC20InvalidReceiver(address)`                       | `0xec442f05` |
| `ERC20InsufficientAllowance(address,uint256,uint256)` | `0xfb8f41b2` |
| `ERC20InvalidApprover(address)`                       | `0xe602df05` |
| `ERC20InvalidSpender(address)`                        | `0x94280d62` |
