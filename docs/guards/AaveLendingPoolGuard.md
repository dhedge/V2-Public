

# Functions:
- [`txGuard(address _poolManagerLogic, address to, bytes data)`](#AaveLendingPoolGuard-txGuard-address-address-bytes-)

# Events:
- [`Deposit(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)`](#AaveLendingPoolGuard-Deposit-address-address-address-uint256-uint256-)
- [`Withdraw(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)`](#AaveLendingPoolGuard-Withdraw-address-address-address-uint256-uint256-)
- [`SetUserUseReserveAsCollateral(address fundAddress, address asset, bool useAsCollateral, uint256 time)`](#AaveLendingPoolGuard-SetUserUseReserveAsCollateral-address-address-bool-uint256-)
- [`Borrow(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)`](#AaveLendingPoolGuard-Borrow-address-address-address-uint256-uint256-)
- [`Repay(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)`](#AaveLendingPoolGuard-Repay-address-address-address-uint256-uint256-)
- [`SwapBorrowRateMode(address fundAddress, address asset, uint256 rateMode)`](#AaveLendingPoolGuard-SwapBorrowRateMode-address-address-uint256-)
- [`RebalanceStableBorrowRate(address fundAddress, address asset)`](#AaveLendingPoolGuard-RebalanceStableBorrowRate-address-address-)


# Function `txGuard(address _poolManagerLogic, address to, bytes data) → uint16 txType` {#AaveLendingPoolGuard-txGuard-address-address-bytes-}
Transaction guard for Aave Lending Pool


## Parameters:
- `_poolManagerLogic`: the pool manager logic

- `data`: the transaction data


## Return Values:
- txType the transaction type of a given transaction data. 2 for `Exchange` type


# Event `Deposit(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)` {#AaveLendingPoolGuard-Deposit-address-address-address-uint256-uint256-}
No description

# Event `Withdraw(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)` {#AaveLendingPoolGuard-Withdraw-address-address-address-uint256-uint256-}
No description

# Event `SetUserUseReserveAsCollateral(address fundAddress, address asset, bool useAsCollateral, uint256 time)` {#AaveLendingPoolGuard-SetUserUseReserveAsCollateral-address-address-bool-uint256-}
No description

# Event `Borrow(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)` {#AaveLendingPoolGuard-Borrow-address-address-address-uint256-uint256-}
No description

# Event `Repay(address fundAddress, address asset, address lendingPool, uint256 amount, uint256 time)` {#AaveLendingPoolGuard-Repay-address-address-address-uint256-uint256-}
No description

# Event `SwapBorrowRateMode(address fundAddress, address asset, uint256 rateMode)` {#AaveLendingPoolGuard-SwapBorrowRateMode-address-address-uint256-}
No description

# Event `RebalanceStableBorrowRate(address fundAddress, address asset)` {#AaveLendingPoolGuard-RebalanceStableBorrowRate-address-address-}
No description

